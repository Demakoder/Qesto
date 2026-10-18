import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/chunked_json.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/windows_key_probe.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_incremental_sync_experiment/cached_executor.dart';

const partition = Partition('synthetic-4c-storage', 'synthetic-4c-epoch');
String fixture([int count = 1000]) => encodeSynthetic(
  count: count,
  fixturePath: '../storage_feasibility/test/fixtures/container_profile_v7.json',
);
w.NoteCommand command(String id, [String target = 'container-tx-0']) =>
    w.NoteCommand.parse({
      'protocol_version': 1,
      'domain_version': 1,
      'workspace_id': partition.workspace,
      'device_id': 'synthetic-4c-device',
      'workspace_epoch': partition.lineage,
      'change_id': id,
      'kind': 'transaction.set_note',
      'transaction_id': target,
      'base_revision': '0',
      'note': 'Synthetic 🪙 note $id',
    });
Future<SqliteContainer> create(
  String path,
  String source, {
  void Function(String)? fault,
}) => SqliteContainer.migrate(
  path,
  MigrationManifest('chunk-test', partition, digest(source)),
  FinancialSnapshot(source),
  incremental: true,
  fault: fault,
);
Mutation edit(String source, {String id = 'chunk-edit', int revision = 0}) {
  final c = command(id),
      next = const QestoNoteExecutor().execute(
        source,
        c,
        syntheticUser,
        DateTime.utc(2026, 10, 13),
      );
  return Mutation(
    id: id,
    partition: partition,
    expectedRevision: revision,
    snapshot: FinancialSnapshot(next.stored),
    intentJson: jsonEncode(c.body),
  );
}

void main() {
  test(
    'lexical chunks preserve exact unicode, whitespace, escapes, nesting and empty arrays',
    () {
      for (final v in [
        fixture(100),
        ' { "schemaVersion":7, "x": ["🪙 ] , \\\"", {}, []], "y":null } ',
      ]) {
        expect(JsonChunks.split(v).parts.join(), v);
        expect(jsonDecode(JsonChunks.split(v).parts.join()), jsonDecode(v));
      }
    },
  );
  test(
    'memoized executor is full parity, repeat edit, multiple targets and owner isolation',
    () {
      final executor = CachedNoteExecutor();
      var source = fixture(100);
      for (final id in ['edit-a', 'edit-b', 'edit-c']) {
        final c = command(
              id,
              id == 'edit-c' ? 'container-tx-1' : 'container-tx-0',
            ),
            time = DateTime.utc(2026, 10, 13);
        final old = const QestoNoteExecutor().execute(
              source,
              c,
              syntheticUser,
              time,
            ),
            optimized = executor.execute(source, c, syntheticUser, time);
        expect(optimized.stored, old.stored);
        expect(optimized.core.toJson(), old.core.toJson());
        expect(
          const QestoNoteExecutor().read(source, syntheticUser).toJson(),
          executor.read(source, syntheticUser).toJson(),
        );
        source = optimized.stored;
      }
      expect(
        () => executor.read(source, 'synthetic-4a-other'),
        throwsA(isA<w.ApiError>()),
      );
      expect(
        () => executor.execute(
          source,
          command('deleted', 'container-tx-2'),
          syntheticUser,
          DateTime.utc(2026),
        ),
        throwsA(isA<w.ApiError>()),
      );
    },
  );
  test(
    'one note retains ALL configured-policy effects across other entities',
    () async {
      final root = jsonDecode(fixture(100)) as Map;
      // A synthetic stale policy projection deliberately requires global effects.
      for (final t in root['synoball']['transactions'] as List) {
        if (t['userCategoryOverride'] == null) {
          t['synoballCategory'] = 'business';
          (t['tags'] as List).removeWhere(
            (v) => v.toString().startsWith('user-category-rule:'),
          );
        }
      }
      final source = jsonEncode(root),
          c = command('multi-effects'),
          time = DateTime.utc(2026, 10, 13);
      final old = const QestoNoteExecutor().execute(
            source,
            c,
            syntheticUser,
            time,
          ),
          next = CachedNoteExecutor().execute(source, c, syntheticUser, time);
      expect(next.stored, old.stored);
      expect(next.core.toJson(), old.core.toJson());
      final prev = {
        for (final t in root['synoball']['transactions'] as List) t['id']: t,
      };
      final changed = next.core.transactions
          .where((t) => canonicalJson(prev[t.id]) != canonicalJson(t.toJson()))
          .length;
      expect(changed, greaterThan(1));
      final dir = createSpikeDirectory(),
          store = await create(dir.path, source);
      await store.commitMutation(
        Mutation(
          id: c.changeId,
          partition: partition,
          expectedRevision: 0,
          snapshot: FinancialSnapshot(next.stored),
          intentJson: jsonEncode(c.body),
        ),
      );
      expect((await store.readSnapshot()).value.json, old.stored);
      await store.close();
    },
  );
  test(
    'incoming receipts, financial chunks, aliases, coverage and cursor rollback together',
    () async {
      final source = fixture(100), dir = createSpikeDirectory();
      var fail = false;
      final store = await create(
        dir.path,
        source,
        fault: (s) {
          if (fail && s == 'remote-before-checkpoint')
            throw const ContractViolation('injected');
        },
      );
      await store.initializeRemoteContext('{"checkpoint":0}');
      final mutation = edit(source), r = await store.commitMutation(mutation);
      final bundle = RemoteBundle(
        id: 'atomic-page',
        partition: partition,
        fromCursor: 0,
        toCursor: 1,
        expectedRevision: 1,
        shadow: mutation.snapshot,
        projection: mutation.snapshot,
        syncContextJson: '{"checkpoint":1}',
        aliases: {'old-synthetic-id': 'canonical-synthetic-id'},
        coveredCommands: [r.id],
        receipts: [
          SyntheticReceipt(
            'receipt-atomic',
            r.id,
            partition,
            r.contentDigest,
            DeliveryState.accepted,
            '{}',
          ),
        ],
      );
      fail = true;
      await expectLater(
        store.applyRemoteBundle(bundle),
        throwsA(isA<ContractViolation>()),
      );
      expect(
        (await store.lookupCommandReceipt(r.id))!.state,
        DeliveryState.queued,
      );
      expect(await store.readCheckpoint(), 0);
      expect(store.raw.select('SELECT * FROM aliases'), isEmpty);
      expect((await store.readRemoteContext())!.shadow.json, source);
      fail = false;
      await store.applyRemoteBundle(bundle);
      expect(await store.readPendingCommands(), isEmpty);
      expect(await store.readCheckpoint(), 1);
      store.verify();
      await store.close();
    },
  );
  test(
    '10k full v7 roundtrip, durable command, revision, bounded changed bytes and reopen',
    () async {
      final source = fixture(10000),
          dir = createSpikeDirectory(),
          store = await create(dir.path, source);
      expect((await store.readSnapshot()).value.json, source);
      await store.maintain();
      store.incrementalMetrics.clear();
      final mutation = edit(source);
      final receipt = await store.commitMutation(mutation);
      expect(receipt.revision, 1);
      expect((await store.readSnapshot()).value.json, mutation.snapshot.json);
      expect(
        store.incrementalMetrics['written_payload_bytes']!,
        lessThan(utf8.encode(source).length * 0.05),
      );
      expect(
        (await store.readPendingCommands()).single.immutableJson,
        mutation.immutableJson,
      );
      expect((await store.commitMutation(mutation)).revision, 1);
      final metrics = Map.of(store.incrementalMetrics);
      await expectLater(
        store.commitMutation(edit(source, id: 'stale')),
        throwsA(isA<StaleRevision>()),
      );
      await store.close();
      final reopened = await SqliteContainer.open(dir.path, partition);
      try {
        expect(
          (await reopened.readSnapshot()).value.json,
          mutation.snapshot.json,
        );
        reopened.verify();
      } finally {
        await reopened.close();
      }
      File('results/chunk-write-evidence.json').writeAsStringSync(
        jsonEncode({
          'full_bytes': utf8.encode(source).length,
          'metrics': metrics,
          'full_v7_roundtrip': true,
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  for (final faultStage in [
    'chunk-after-row',
    'local-after-snapshot',
    'local-before-commit',
  ]) {
    test('rollback all chunks and outbox at $faultStage', () async {
      final source = fixture(100), dir = createSpikeDirectory();
      var enabled = false;
      final store = await create(
        dir.path,
        source,
        fault: (stage) {
          if (enabled && stage == faultStage)
            throw const ContractViolation('injected');
        },
      );
      enabled = true;
      await expectLater(
        store.commitMutation(edit(source)),
        throwsA(isA<ContractViolation>()),
      );
      expect((await store.readSnapshot()).value.json, source);
      expect(await store.readPendingCommands(), isEmpty);
      store.verify();
      await store.close();
      final reopened = await SqliteContainer.open(dir.path, partition);
      expect((await reopened.readSnapshot()).revision, 0);
      await reopened.close();
    });
  }
  for (final corruption in ['row', 'manifest', 'hash']) {
    test('detect $corruption corruption without resetting profile', () async {
      final dir = createSpikeDirectory(),
          source = fixture(100),
          store = await create(dir.path, source);
      await store.readSnapshot(); // prime cache; raw write must invalidate it
      switch (corruption) {
        case 'row':
          store.raw.execute(
            "UPDATE json_chunks SET body=body||'x' WHERE scope='state' AND slot=0",
          );
        case 'manifest':
          store.raw.execute("UPDATE state SET snapshot='{}'");
        case 'hash':
          store.raw.execute(
            "UPDATE json_chunks SET hash='wrong' WHERE scope='state' AND slot=0",
          );
      }
      await expectLater(
        store.readSnapshot(),
        throwsA(isA<ContractViolation>()),
      );
      final path = store.path;
      await store.close();
      final bytes = File(path).readAsBytesSync();
      await expectLater(
        SqliteContainer.open(dir.path, partition),
        throwsA(isA<ContractViolation>()),
      );
      expect(File(path).readAsBytesSync(), bytes);
    });
  }
  test(
    'format2 missing, corrupt and wrong keys fail closed; verified key restores state',
    () async {
      final source = fixture(100), dir = createSpikeDirectory();
      final store = await create(dir.path, source), mutation = edit(source);
      await store.commitMutation(mutation);
      final path = store.path;
      await store.close();
      final vault = File('${dir.path}/container-vault.bin');
      final saved = vault.readAsBytesSync(),
          dbBytes = File(path).readAsBytesSync();
      // Rename only the test-owned vault; preserve its bytes for explicit recovery.
      final held = vault.renameSync('${vault.path}.held');
      await expectLater(
        SqliteContainer.open(dir.path, partition),
        throwsA(anything),
      );
      await expectLater(create(dir.path, source), throwsA(anything));
      expect(vault.existsSync(), false);
      expect(File(path).readAsBytesSync(), dbBytes);
      held.renameSync(vault.path);
      vault.writeAsBytesSync([1, 2, 3], flush: true);
      await expectLater(
        SqliteContainer.open(dir.path, partition),
        throwsA(anything),
      );
      expect(vault.readAsBytesSync(), [1, 2, 3]);
      final manifest =
          jsonDecode(utf8.decode(WindowsKeyProbe.unprotect(saved))) as Map;
      manifest['generations']['1']['key'] = base64Encode(randomKey());
      final wrong = WindowsKeyProbe.protect(utf8.encode(jsonEncode(manifest)));
      vault.writeAsBytesSync(wrong, flush: true);
      await expectLater(
        SqliteContainer.open(dir.path, partition),
        throwsA(anything),
      );
      expect(vault.readAsBytesSync(), wrong);
      expect(File(path).readAsBytesSync(), dbBytes);
      vault.writeAsBytesSync(saved, flush: true);
      final reopened = await SqliteContainer.open(dir.path, partition);
      try {
        expect((await reopened.readSnapshot()).revision, 1);
        expect(
          (await reopened.readSnapshot()).value.json,
          mutation.snapshot.json,
        );
        expect(
          (await reopened.readPendingCommands()).single.immutableJson,
          mutation.immutableJson,
        );
        await reopened.rotateKey();
        expect(
          (await reopened.readSnapshot()).value.json,
          mutation.snapshot.json,
        );
        reopened.verify();
      } finally {
        await reopened.close();
      }
    },
  );
  test(
    'encrypted backup restores exact chunks, revisions and pending intents',
    () async {
      final source = fixture(100),
          dir = createSpikeDirectory(),
          store = await create(dir.path, source),
          mutation = edit(source);
      await store.commitMutation(mutation);
      final backup = await store.backup();
      expect(backup.revision, 1);
      await store.recover();
      expect((await store.readSnapshot()).value.json, mutation.snapshot.json);
      expect(
        (await store.readPendingCommands()).single.immutableJson,
        mutation.immutableJson,
      );
      store.verify();
      final path = store.path;
      await store.close();
      expect(
        latin1.decode(File(path).readAsBytesSync()),
        isNot(contains('Synthetic ')),
      );
      expect(
        File(path).readAsBytesSync().take(15).toList(),
        isNot(utf8.encode('SQLite format 3')),
      );
    },
  );
}
