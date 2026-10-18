import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/container/synthetic_scenario.dart';
import 'package:qesto_storage_spike/container/writer.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/wal_policy.dart';
import 'package:qesto_storage_spike/windows_key_probe.dart';

void main() {
  late Directory directory;
  late FinancialSnapshot source;
  late MigrationManifest migration;
  SqliteContainer? store;
  setUp(() async {
    directory = createSpikeDirectory();
    source = FinancialSnapshot(
      File('test/fixtures/container_profile_v7.json').readAsStringSync().trim(),
    );
    migration = MigrationManifest(
      'migration-one',
      syntheticPartition,
      source.hash,
    );
    store = await SqliteContainer.migrate(directory.path, migration, source);
  });
  tearDown(() async {
    await store?.close();
  });
  Future<void> reopen({bool recovery = false}) async {
    await store?.close();
    store = null;
    store = await SqliteContainer.open(
      directory.path,
      syntheticPartition,
      recovery: recovery,
    );
  }

  test(
    'complete codec v7 bootstrap is byte-lossless, no fake outbox',
    () async {
      expect((await store!.readSnapshot()).value.json, source.json);
      expect(await store!.readPendingCommands(), isEmpty);
      expect(await store!.readCheckpoint(), 0);
      expect(
        store!.raw.select('SELECT snapshot FROM shadow').single['snapshot'],
        isNull,
      );
      store!.verify();
    },
  );
  test(
    'migrated and edited full snapshot decode with existing app codec',
    () async {
      final artifact = File('${directory.path}/roundtrip.json');
      for (final edited in [false, true]) {
        if (edited) await store!.commitMutation(syntheticMutation(source));
        artifact.writeAsStringSync((await store!.readSnapshot()).value.json);
        final sdk = Platform.resolvedExecutable;
        final result = await Process.run(sdk, [
          '--packages=../../apps/qesto_app/.dart_tool/package_config.json',
          'tool/container_codec_fixture.dart',
          artifact.path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final parsed = jsonDecode((result.stdout as String).trim()) as Map;
        expect(parsed['passed'], isTrue);
        File(
          'results/container_codec_${edited ? 'edited' : 'migration'}.json',
        ).writeAsStringSync(jsonEncode(parsed));
      }
    },
  );
  test(
    'existing financial model edit persists and receipt differs from remote ACK',
    () async {
      final m = syntheticMutation(source);
      final r = await store!.commitMutation(m);
      expect(r.locallyDurable, isTrue);
      expect(r.remotelyAccepted, isFalse);
      await reopen();
      expect((await store!.readSnapshot()).value.json, m.snapshot.json);
      expect((await store!.lookupCommandReceipt(m.id))!.revision, 1);
      final root = jsonDecode(m.snapshot.json) as Map;
      expect(
        SynoballState.fromJson(
          Map<String, dynamic>.from(root['synoball'] as Map),
        ).transactions[0].amount.minorUnits,
        486122,
      );
      store!.verify();
    },
  );
  test(
    'same command id/content is idempotent even after later changes',
    () async {
      final m = syntheticMutation(source);
      await store!.commitMutation(m);
      await store!.commitMutation(
        syntheticMutation(m.snapshot, id: 'two', expected: 1),
      );
      expect((await store!.commitMutation(m)).revision, 1);
      expect((await store!.readSnapshot()).revision, 2);
      expect(await store!.readPendingCommands(), hasLength(2));
    },
  );
  test('id collision and stale revision cannot overwrite', () async {
    await store!.commitMutation(syntheticMutation(source));
    await expectLater(
      store!.commitMutation(syntheticMutation(source, note: 'different')),
      throwsA(isA<CommandCollision>()),
    );
    await expectLater(
      store!.commitMutation(syntheticMutation(source, id: 'stale')),
      throwsA(isA<StaleRevision>()),
    );
    expect((await store!.readSnapshot()).revision, 1);
    expect(store!.requiresReopen, isFalse);
  });
  test('partition cannot be selected by UI or changed per command', () async {
    await expectLater(
      store!.commitMutation(
        Mutation(
          id: 'alien',
          partition: const Partition('other', 'other'),
          expectedRevision: 0,
          snapshot: source,
          intentJson: '{}',
        ),
      ),
      throwsA(isA<ContractViolation>()),
    );
    expect(await store!.readPendingCommands(), isEmpty);
  });
  test(
    'migration re-run after edits does not restore old snapshot or regenerate IDs',
    () async {
      final m = syntheticMutation(source);
      await store!.commitMutation(m);
      await store!.close();
      store = null;
      store = await SqliteContainer.migrate(directory.path, migration, source);
      expect((await store!.readSnapshot()).value.json, m.snapshot.json);
      expect(await store!.readPendingCommands(), hasLength(1));
    },
  );
  test('different migration manifest is refused', () async {
    await store!.close();
    store = null;
    await expectLater(
      SqliteContainer.migrate(
        directory.path,
        MigrationManifest('different', syntheticPartition, source.hash),
        source,
      ),
      throwsA(isA<ContractViolation>()),
    );
  });
  for (final stage in [
    'migration-after-snapshot',
    'migration-before-commit',
    'migration-after-commit',
  ]) {
    test(
      'migration resumes after $stage without duplicate historical commands',
      () async {
        final other = createSpikeDirectory();
        await expectLater(
          SqliteContainer.migrate(
            other.path,
            migration,
            source,
            fault: (s) {
              if (s == stage) throw StateError('simulated interruption');
            },
          ),
          throwsStateError,
        );
        final resumed = await SqliteContainer.migrate(
          other.path,
          migration,
          source,
        );
        try {
          expect((await resumed.readSnapshot()).value.json, source.json);
          resumed.verify();
          expect(await resumed.readPendingCommands(), isEmpty);
        } finally {
          await resumed.close();
        }
      },
    );
  }
  test('immutable command SQL triggers reject update and delete', () async {
    await store!.commitMutation(syntheticMutation(source));
    expect(
      () => store!.raw.execute("UPDATE commands SET body='{}'"),
      throwsA(anything),
    );
    expect(() => store!.raw.execute('DELETE FROM commands'), throwsA(anything));
    store!.verify();
  });
  test('lease survives restart and resend uses same id/body', () async {
    await store!.commitMutation(syntheticMutation(source));
    await store!.claim('command-1', nowMs: 100, leaseMs: 1000);
    await reopen();
    await store!.retryExpired(nowMs: 500);
    expect(
      (await store!.lookupCommandReceipt('command-1'))!.state,
      DeliveryState.inFlight,
    );
    await store!.retryExpired(nowMs: 1100);
    await store!.claim('command-1', nowMs: 1200, leaseMs: 1000);
    expect((await store!.readPendingCommands()).single.attempts, 2);
    expect((await store!.readSnapshot()).revision, 1);
  });
  for (final state in [
    DeliveryState.accepted,
    DeliveryState.conflict,
    DeliveryState.blockedDependency,
    DeliveryState.rejectedRequiringAttention,
    DeliveryState.pausedAuthentication,
  ]) {
    test(
      'durable synthetic $state receipt retained; no pull cursor shortcut',
      () async {
        final r = await store!.commitMutation(syntheticMutation(source));
        await store!.claim(r.id, nowMs: 0, leaseMs: 1000);
        final ack = SyntheticReceipt(
          'receipt-1',
          r.id,
          syntheticPartition,
          r.contentDigest,
          state,
          '{"commit_seq":99}',
        );
        await store!.markCommandAcknowledged(ack);
        await reopen();
        await store!.markCommandAcknowledged(ack);
        expect((await store!.lookupCommandReceipt(r.id))!.state, state);
        expect(await store!.readPendingCommands(), hasLength(1));
        expect(await store!.readCheckpoint(), 0);
        expect(store!.raw.select('SELECT * FROM receipts'), hasLength(1));
      },
    );
  }
  test('receipt collision and conflicting accepted result rejected', () async {
    final r = await store!.commitMutation(syntheticMutation(source));
    await store!.markCommandAcknowledged(
      SyntheticReceipt(
        'r',
        r.id,
        syntheticPartition,
        r.contentDigest,
        DeliveryState.accepted,
        '{}',
      ),
    );
    await expectLater(
      store!.markCommandAcknowledged(
        SyntheticReceipt(
          'r',
          r.id,
          syntheticPartition,
          r.contentDigest,
          DeliveryState.conflict,
          '{}',
        ),
      ),
      throwsA(isA<CommandCollision>()),
    );
    await expectLater(
      store!.markCommandAcknowledged(
        SyntheticReceipt(
          'r2',
          r.id,
          syntheticPartition,
          r.contentDigest,
          DeliveryState.conflict,
          '{}',
        ),
      ),
      throwsA(isA<ContractViolation>()),
    );
  });
  test(
    'dependency blocks delivery until parent accepted and explicit resume',
    () async {
      final m = syntheticMutation(source),
          parent = await store!.commitMutation(m);
      await store!.commitMutation(
        syntheticMutation(
          m.snapshot,
          id: 'child',
          expected: 1,
          dependencies: [parent.id],
        ),
      );
      await expectLater(
        store!.resume('child'),
        throwsA(isA<ContractViolation>()),
      );
      await store!.markCommandAcknowledged(
        SyntheticReceipt(
          'r',
          parent.id,
          syntheticPartition,
          parent.contentDigest,
          DeliveryState.accepted,
          '{}',
        ),
      );
      await store!.resume('child');
      expect(
        (await store!.lookupCommandReceipt('child'))!.state,
        DeliveryState.queued,
      );
    },
  );
  test(
    'remote bundle applies shadow, aliases, revision and checkpoint but no outgoing command',
    () async {
      final remote = editSyntheticNote(source, 'server');
      final b = RemoteBundle(
        id: 'page',
        partition: syntheticPartition,
        fromCursor: 0,
        toCursor: 5,
        expectedRevision: 0,
        shadow: remote,
        aliases: {'source': 'canonical'},
      );
      final r = await store!.applyRemoteBundle(b);
      expect(r.localProjectionRetained, isFalse);
      await reopen();
      expect((await store!.applyRemoteBundle(b)).revision, 1);
      expect((await store!.readSnapshot()).value.json, remote.json);
      expect(await store!.readCheckpoint(), 5);
      expect(await store!.readPendingCommands(), isEmpty);
      expect(
        store!.raw.select('SELECT target FROM aliases').single['target'],
        'canonical',
      );
      store!.verify();
    },
  );
  test('pending local projection retained without invented LWW', () async {
    final m = syntheticMutation(source);
    await store!.commitMutation(m);
    await store!.applyRemoteBundle(
      RemoteBundle(
        id: 'page',
        partition: syntheticPartition,
        fromCursor: 0,
        toCursor: 1,
        expectedRevision: 1,
        shadow: editSyntheticNote(source, 'remote'),
      ),
    );
    expect((await store!.readSnapshot()).value.json, m.snapshot.json);
    expect(store!.raw.select('SELECT * FROM conflicts'), hasLength(1));
    expect(await store!.readPendingCommands(), hasLength(1));
    store!.verify();
  });
  test(
    'accepted command remains overlay until complete remote page covers it',
    () async {
      final m = syntheticMutation(source), r = await store!.commitMutation(m);
      await store!.markCommandAcknowledged(
        SyntheticReceipt(
          'r',
          r.id,
          syntheticPartition,
          r.contentDigest,
          DeliveryState.accepted,
          '{}',
        ),
      );
      final result = await store!.applyRemoteBundle(
        RemoteBundle(
          id: 'page',
          partition: syntheticPartition,
          fromCursor: 0,
          toCursor: 1,
          expectedRevision: 1,
          shadow: m.snapshot,
          coveredCommands: [r.id],
        ),
      );
      expect(result.localProjectionRetained, isFalse);
      expect(await store!.readPendingCommands(), isEmpty);
      expect(await store!.lookupCommandReceipt(r.id), isNotNull);
      expect(store!.raw.select('SELECT * FROM commands'), hasLength(1));
    },
  );
  for (final kind in ['stale', 'version', 'alias-cycle', 'unaccepted']) {
    test('invalid remote $kind is atomic rejection', () async {
      final b = RemoteBundle(
        id: 'invalid',
        partition: syntheticPartition,
        fromCursor: kind == 'stale' ? 3 : 0,
        toCursor: 4,
        expectedRevision: 0,
        shadow: source,
        protocolVersion: kind == 'version' ? 2 : 1,
        aliases: kind == 'alias-cycle' ? {'a': 'b', 'b': 'a'} : {},
        coveredCommands: kind == 'unaccepted' ? ['unknown'] : [],
      );
      await expectLater(
        store!.applyRemoteBundle(b),
        throwsA(isA<ContractViolation>()),
      );
      expect(await store!.readCheckpoint(), 0);
      expect((await store!.readSnapshot()).revision, 0);
      expect(store!.raw.select('SELECT * FROM aliases'), isEmpty);
    });
  }
  test(
    'backup recovery retains outbox and refuses hiding newer commands',
    () async {
      final m = syntheticMutation(source);
      await store!.commitMutation(m);
      final backup = await store!.backup();
      expect(backup.revision, 1);
      final point = await store!.recover();
      expect(point.revision, 1);
      expect((await store!.readPendingCommands()).single.receipt.id, m.id);
      expect((await store!.readSnapshot()).value.json, m.snapshot.json);
      await store!.commitMutation(
        syntheticMutation(m.snapshot, id: 'later', expected: 1),
      );
      // This backup now names the active generation; a separate test below
      // covers refusal to switch away from a newer readable source generation.
      expect((await store!.readSnapshot()).revision, 2);
    },
  );
  test(
    'stale backup cannot hide post-backup financial changes or ACK metadata',
    () async {
      final m = syntheticMutation(source), r = await store!.commitMutation(m);
      await store!.backup();
      await store!.markCommandAcknowledged(
        SyntheticReceipt(
          'after-backup',
          r.id,
          syntheticPartition,
          r.contentDigest,
          DeliveryState.accepted,
          '{}',
        ),
      );
      await expectLater(store!.recover(), throwsA(isA<ContractViolation>()));
      expect(
        (await store!.lookupCommandReceipt(r.id))!.remotelyAccepted,
        isTrue,
      );
      await store!.commitMutation(
        syntheticMutation(m.snapshot, id: 'later', expected: 1),
      );
      await expectLater(store!.recover(), throwsA(isA<ContractViolation>()));
      expect((await store!.readSnapshot()).revision, 2);
      expect(await store!.readPendingCommands(), hasLength(2));
    },
  );
  test('rotation keeps all commands and rejects overlapping writes', () async {
    final m = syntheticMutation(source);
    await store!.commitMutation(m);
    final rotation = store!.rotateKey();
    await expectLater(
      store!.commitMutation(
        syntheticMutation(m.snapshot, expected: 1, id: 'overlap'),
      ),
      throwsA(isA<ContractViolation>()),
    );
    expect((await rotation).generation, 2);
    await reopen();
    store!.verify();
    expect((await store!.readPendingCommands()).single.receipt.id, m.id);
  });
  test('corrupt vault retained, explicit verified backup recovers', () async {
    await store!.commitMutation(syntheticMutation(source));
    await store!.backup();
    await store!.close();
    store = null;
    final vault = File('${directory.path}/container-vault.bin');
    vault.writeAsBytesSync([1, 2, 3], flush: true);
    await expectLater(
      SqliteContainer.open(directory.path, syntheticPartition),
      throwsA(isA<ContractViolation>()),
    );
    expect(vault.readAsBytesSync(), [1, 2, 3]);
    await reopen(recovery: true);
    expect((await store!.readPendingCommands()).length, 1);
  });
  test(
    'missing key, wrong key, damaged DB never create empty profile',
    () async {
      final db = store!.path;
      await store!.close();
      store = null;
      final vault = File('${directory.path}/container-vault.bin'),
          saved = vault.readAsBytesSync();
      vault.renameSync('${vault.path}.held');
      await expectLater(
        SqliteContainer.open(directory.path, syntheticPartition),
        throwsA(isA<ContractViolation>()),
      );
      await expectLater(
        SqliteContainer.migrate(directory.path, migration, source),
        throwsA(isA<ContractViolation>()),
      );
      vault.writeAsBytesSync(saved);
      final manifest =
          jsonDecode(utf8.decode(WindowsKeyProbe.unprotect(saved))) as Map;
      manifest['generations']['1']['key'] = base64Encode(randomKey());
      vault.writeAsBytesSync(
        WindowsKeyProbe.protect(utf8.encode(jsonEncode(manifest))),
      );
      await expectLater(
        SqliteContainer.open(directory.path, syntheticPartition),
        throwsA(anything),
      );
      vault.writeAsBytesSync(saved);
      File(db).writeAsBytesSync([1, 2, 3]);
      await expectLater(
        SqliteContainer.open(directory.path, syntheticPartition),
        throwsA(anything),
      );
      expect(File(db).lengthSync(), 3);
    },
  );
  test('completed migration with missing DB is not re-provisioned', () async {
    final db = store!.path;
    await store!.close();
    store = null;
    File(db).renameSync('$db.held');
    await expectLater(
      SqliteContainer.migrate(directory.path, migration, source),
      throwsA(isA<ContractViolation>()),
    );
    expect(File(db).existsSync(), isFalse);
  });
  test(
    'two simultaneous readers see stable revision; writer sees fresh revision',
    () async {
      final a = await store!.leaseReader(), b = await store!.leaseReader();
      await store!.commitMutation(syntheticMutation(source));
      expect(a.read().revision, 0);
      expect(b.read().revision, 0);
      expect((await store!.readSnapshot()).revision, 1);
      a.close();
      b.close();
      expect((await store!.maintain()).busy, 0);
    },
  );
  test('reader lease expiration releases pinned WAL', () async {
    final r = await store!.leaseReader(
      duration: const Duration(milliseconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(r.read, throwsA(isA<ContractViolation>()));
    expect((await store!.maintain()).busy, 0);
  });
  test('disk pressure refuses new edit, retaining pending command', () async {
    await store!.commitMutation(syntheticMutation(source));
    await store!.close();
    store = null;
    store = await SqliteContainer.open(
      directory.path,
      syntheticPartition,
      availableBytes: () => 0,
    );
    await expectLater(
      store!.commitMutation(syntheticMutation(source, id: 'new', expected: 1)),
      throwsA(isA<StoragePressure>()),
    );
    expect(await store!.readPendingCommands(), hasLength(1));
    expect((await store!.readSnapshot()).revision, 1);
  });
  test('supervised owner queue bound, drain and late rejection', () async {
    await store!.close();
    store = null;
    final owner = await ContainerWriter.open(
      directory.path,
      syntheticPartition,
      maxQueue: 1,
    );
    final commit = owner.commitMutation(syntheticMutation(source));
    await expectLater(owner.readSnapshot(), throwsA(isA<ContractViolation>()));
    final closing = owner.close();
    await expectLater(owner.readSnapshot(), throwsA(isA<ContractViolation>()));
    expect((await commit).revision, 1);
    await closing;
    await reopen();
    expect((await store!.readSnapshot()).revision, 1);
  });
}
