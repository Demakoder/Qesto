import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/note_sync_binding.dart';
import 'package:qesto_storage_spike/windows_key_probe.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as wire;
import 'package:qesto_windows_ui_sync_experiment/harness.dart';

const codec = UserFinancialDataCodec();
Future<void> edit(
  WindowsNoteBoundary c,
  String id,
  int target,
  String note, {
  int? revision,
  NoteCancellation? cancellation,
}) async {
  await c.commitNote(
    TransactionNoteIntent(
      commandId: id,
      transactionId: 'container-tx-$target',
      note: note,
      expectedRevision: revision ?? (await c.load()).revision,
    ),
    cancellation: cancellation,
  );
}

Future<Map<String, dynamic>> snapshot(WindowsNoteBoundary c) async =>
    jsonDecode(codec.encode((await c.load()).data));
Map<String, dynamic> copy(Map<String, dynamic> x) => jsonDecode(jsonEncode(x));

void main({
  UiSyncHarness Function()? harnessFactory,
  List<String> extraCrashStages = const [],
}) {
  late UiSyncHarness h;
  final owners = <WindowsNoteBoundary>[];
  setUp(() async {
    h = harnessFactory?.call() ?? UiSyncHarness();
    await h.start();
  });
  tearDown(() async {
    for (final o in owners) {
      await o.close();
    }
    owners.clear();
    await h.close();
  });
  Future<WindowsNoteBoundary> open(
    dynamic s,
    int i, {
    bool create = true,
    BoundaryProbe probe = BoundaryProbe.none,
  }) async {
    final o = await h.open(s, i, create: create, probe: probe);
    owners.add(o);
    return o;
  }

  test(
    'two sole-writer owners: offline disjoint notes, full server parity, current entity revision, no incoming outbox',
    () async {
      final s = await h.server(), a = await open(s, 0), b = await open(s, 1);
      await s.kill();
      await edit(a, 'offline-a', 0, 'Private A');
      await edit(b, 'offline-b', 1, 'Private B');
      expect((await a.inspectForTest())['checkpoint'], 0);
      await h.server();
      await a.pushForTest();
      expect((await a.inspectForTest())['checkpoint'], 0);
      await b.synchronize(pushPending: false);
      expect((await b.load()).data.transactions.first.comment, 'Private A');
      expect((await b.pending()).length, 1);
      await b.synchronize();
      await a.synchronize();
      final server = await h.serverState();
      expect(await snapshot(a), server['state']);
      expect(await snapshot(b), server['state']);
      expect(await a.pending(), isEmpty);
      expect(await b.pending(), isEmpty);
      expect((await a.inspectForTest())['checkpoint'], 2);
      await edit(a, 'current-revision', 0, 'Second A');
      expect(
        jsonDecode(
          (await a.pending()).single.immutableJson,
        )['intent']['wire']['base_revision'],
        '1',
      );
      await a.synchronize();
      await b.synchronize();
      expect(await snapshot(a), await snapshot(b));
      expect((await h.serverState())['head'], 3);
      final before = jsonDecode(h.initial) as Map;
      for (final key in before.keys.where(
        (k) => k != 'synoball' && k != 'transactions' && k != 'accounts',
      )) {
        expect(
          (await snapshot(a))[key],
          before[key],
          reason: 'unrelated v7 root $key',
        );
      }
      for (final p in h.profiles) {
        final bytes = File('${p.directory}/container-1.db').readAsBytesSync();
        expect(latin1.decode(bytes).startsWith('SQLite format 3'), false);
        expect(latin1.decode(bytes).contains('Private A'), false);
      }
      File('results/two-owner-parity.json').writeAsStringSync(
        jsonEncode({
          'passed': true,
          'owners': 2,
          'full_v7_server_client_equality': true,
          'all_tags_audit_events_compared': true,
          'encrypted_databases': 2,
          'next_base_revision': '1',
          'incoming_generated_commands': 0,
        }),
        flush: true,
      );
    },
  );
  test(
    'same-field conflict preserves proposal, authoritative note and requires_attention after restart',
    () async {
      final s = await h.server(), a = await open(s, 0), b = await open(s, 1);
      await edit(a, 'conflict-a', 0, 'Version A');
      await edit(b, 'conflict-b', 0, 'Version B');
      await a.synchronize();
      final outcome = await b.synchronize();
      expect(outcome.status, NoteSyncStatus.requiresAttention);
      final queue = await b.pending();
      expect(queue.single.receipt.state, DeliveryState.conflict);
      final receipt = jsonDecode(queue.single.receipt.serverReceipt!);
      expect(receipt['payload']['conflict']['current_note'], 'Version A');
      expect(receipt['payload']['conflict']['proposed_note'], 'Version B');
      expect((await b.load()).data.transactions.first.comment, 'Version B');
      expect(
        (await b.inspectForTest())['shadow']['transactions'][0]['comment'],
        'Version A',
      );
      final before = await snapshot(b);
      await b.close();
      owners.remove(b);
      final reopened = await open(s, 1, create: false);
      expect(
        (await reopened.synchronize()).status,
        NoteSyncStatus.requiresAttention,
      );
      expect(await snapshot(reopened), before);
      expect((await h.serverState())['head'], 2);
    },
  );
  test(
    'lost server response does not rewrite command; repeated push yields one receipt/bundle',
    () async {
      final s = await h.server(), a = await open(s, 0), b = await open(s, 1);
      await edit(a, 'lost-response', 0, 'Saved before HTTP');
      final immutable = (await a.pending()).single.immutableJson;
      s.fault('lost-response', 'after-commit', 'drop-response');
      await expectLater(a.synchronize(), throwsA(isA<NoteBoundaryFailure>()));
      expect((await h.serverState())['head'], 1);
      expect((await a.inspectForTest())['checkpoint'], 0);
      expect((await a.pending()).single.immutableJson, immutable);
      s.clearFault();
      await a.pushForTest();
      await a.pushForTest();
      await a.synchronize();
      await b.synchronize();
      expect((await h.serverState())['head'], 1);
      expect(await a.pending(), isEmpty);
      expect(await snapshot(a), (await h.serverState())['state']);
    },
  );
  test(
    'server unavailable after local ACK remains retryable; explicit new process recovers pending',
    () async {
      final s = await h.server(), a = await open(s, 0);
      await s.kill();
      await edit(a, 'offline-restart', 0, 'Durable offline');
      await expectLater(
        a.synchronize(),
        throwsA(
          isA<NoteBoundaryFailure>().having(
            (e) => e.outcomeUnknown,
            'known',
            false,
          ),
        ),
      );
      await a.close();
      owners.remove(a);
      final online = await h.server(),
          again = await open(online, 0, create: false);
      expect((await again.pending()).single.receipt.id, 'offline-restart');
      await again.synchronize();
      expect(await again.pending(), isEmpty);
      expect(await snapshot(again), (await h.serverState())['state']);
    },
  );
  for (final stage in [
    ...extraCrashStages,
    'local-after-snapshot',
    'local-before-commit',
    'after-commit-before-reply',
  ]) {
    test(
      'native process termination $stage preserves atomic local state/outbox',
      () async {
        final s = await h.server(), a = await open(s, 0);
        await a.close();
        owners.remove(a);
        final result = await h.child(s, 0, 'edit', fault: stage);
        expect(
          result.exitCode,
          86,
          reason: '${result.stdout} ${result.stderr}',
        );
        final again = await open(s, 0, create: false);
        final durable = stage == 'after-commit-before-reply';
        expect((await again.load()).revision, durable ? 1 : 0);
        expect((await again.pending()).length, durable ? 1 : 0);
        if (durable) {
          await again.synchronize();
          expect((await h.serverState())['head'], 1);
        }
      },
    );
  }
  test(
    'native process death before checkpoint rolls back projection/cursor, then replays once',
    () async {
      final s = await h.server(), a = await open(s, 0), b = await open(s, 1);
      await edit(a, 'remote-crash', 0, 'Remote durable');
      await a.synchronize();
      final before = await snapshot(b);
      await b.close();
      owners.remove(b);
      final killed = await h.child(
        s,
        1,
        'sync',
        fault: 'remote-before-checkpoint',
      );
      expect(killed.exitCode, 86, reason: '${killed.stdout} ${killed.stderr}');
      final again = await open(s, 1, create: false);
      expect((await again.inspectForTest())['checkpoint'], 0);
      expect(await snapshot(again), before);
      final page = await again.pageForTest();
      expect(await again.applyPageForTest(page), true);
      final once = await snapshot(again), rev = (await again.load()).revision;
      expect(await again.applyPageForTest(page), false);
      expect((await again.load()).revision, rev);
      expect(await snapshot(again), once);
      expect(await snapshot(again), (await h.serverState())['state']);
      expect(await again.pending(), isEmpty);
    },
  );
  test(
    'versions, partition, tags and executor effects fail closed before cursor/snapshot changes',
    () async {
      final s = await h.server(), a = await open(s, 0), b = await open(s, 1);
      await edit(a, 'tamper', 0, 'Validated');
      await a.synchronize();
      final page = await b.pageForTest(),
          before = await snapshot(b),
          info = await b.inspectForTest();
      final mutations = <void Function(Map<String, dynamic>)>[
        (p) => p['protocol_version'] = 99,
        (p) => p['domain_version'] = 99,
        (p) => p['workspace_epoch'] = 'other',
        (p) => p['policy_digest'] = 'wrong-policy',
        (p) =>
            p['bundles'][0]['entities'][0]['transaction']['tags'] = <String>[],
        (p) => p['bundles'][0]['domain_effect']['executed_at'] =
            '2026-10-13T00:00:00+03:00',
        (p) => p['bundles'][0]['domain_effect']['after_core_digest'] =
            'bad-digest',
        (p) => p['bundles'][0]['receipt']['revision'] = '77',
        (p) {
          final body = p['bundles'][0]['domain_effect']['command'];
          body['base_revision'] = '999';
          p['bundles'][0]['receipt']['content_digest'] = wire.digest(body);
        },
      ];
      for (final mutate in mutations) {
        final bad = copy(page);
        mutate(bad);
        await expectLater(
          b.applyPageForTest(bad),
          throwsA(isA<NoteBoundaryFailure>()),
        );
        expect(await snapshot(b), before);
        expect(await b.inspectForTest(), info);
      }
      expect(await b.applyPageForTest(page), true);
    },
  );
  test(
    'cancel and stale intent before native commit never alter durable snapshot',
    () async {
      final s = await h.server(),
          a = await open(s, 0, probe: BoundaryProbe.beforeCommitGate);
      final before = await snapshot(a),
          cancel = NoteCancellation(),
          stage = a.stages.first;
      final saving = edit(
        a,
        'cancelled',
        0,
        'Do not publish',
        cancellation: cancel,
      );
      final rejected = expectLater(
        saving,
        throwsA(
          isA<NoteBoundaryFailure>().having(
            (e) => e.outcomeUnknown,
            'known rollback',
            false,
          ),
        ),
      );
      await stage;
      cancel.cancel();
      await rejected;
      expect(await snapshot(a), before);
      expect(await a.pending(), isEmpty);
      await expectLater(
        edit(a, 'stale', 0, 'Wrong revision', revision: 99),
        throwsA(isA<NoteBoundaryFailure>()),
      );
      expect(await snapshot(a), before);
    },
  );
  test(
    'missing/corrupt key cannot silently reset profile or create outbox',
    () async {
      final s = await h.server(), a = await open(s, 0);
      await edit(a, 'key-test', 0, 'Preserved');
      await a.close();
      owners.remove(a);
      final dir = h.profiles[0].directory,
          vault = File('$dir/container-vault.bin'),
          recovery = File('$dir/container-recovery.bin');
      final db = File('$dir/container-1.db'),
          bytes = db.readAsBytesSync(),
          key = vault.readAsBytesSync();
      final backup = recovery.existsSync() ? recovery.readAsBytesSync() : null;
      vault.writeAsBytesSync([1, 2, 3], flush: true);
      recovery.writeAsBytesSync([4, 5], flush: true);
      await expectLater(h.open(s, 0), throwsA(isA<NoteBoundaryFailure>()));
      expect(db.readAsBytesSync(), bytes);
      vault.deleteSync();
      recovery.deleteSync();
      await expectLater(h.open(s, 0), throwsA(isA<NoteBoundaryFailure>()));
      expect(db.readAsBytesSync(), bytes);
      vault.writeAsBytesSync(key, flush: true);
      if (backup != null) recovery.writeAsBytesSync(backup, flush: true);
      // A valid DPAPI envelope with the wrong encryption key is not corruption
      // of the envelope; it must still fail, preserving database bytes.
      final manifest = jsonDecode(utf8.decode(WindowsKeyProbe.unprotect(key)));
      manifest['generations']['1']['key'] = base64Encode(
        List<int>.filled(32, 7),
      );
      vault.writeAsBytesSync(
        WindowsKeyProbe.protect(utf8.encode(jsonEncode(manifest))),
        flush: true,
      );
      await expectLater(h.open(s, 0), throwsA(isA<NoteBoundaryFailure>()));
      expect(db.readAsBytesSync(), bytes);
      vault.writeAsBytesSync(key, flush: true);
      final again = await open(s, 0, create: false);
      expect((await again.pending()).length, 1);
    },
  );
  test(
    'restart rejects a different device/principal before exposing the local financial state',
    () async {
      final s = await h.server(), a = await open(s, 0);
      await a.close();
      owners.remove(a);
      await expectLater(
        WindowsNoteBoundary.open(
          h.profiles[0],
          synchronization: NoteSyncBinding(
            principal: h.config.principals[1],
            endpoint: s.base,
            domain: h.domain(1),
          ),
        ),
        throwsA(isA<NoteBoundaryFailure>()),
      );
      final restored = await open(s, 0, create: false);
      expect((await restored.load()).revision, 0);
    },
  );
  test(
    'unmarked non-synthetic path rejected without probing any production repository',
    () async {
      final fake = Directory('${h.run.path}/unmarked')..createSync();
      await expectLater(
        WindowsNoteBoundary.open(
          SyntheticWindowsProfile(fake.path, 'local-user', 'device', 'epoch'),
        ),
        throwsA(isA<NoteBoundaryFailure>()),
      );
      expect(fake.listSync(), isEmpty);
    },
  );
}
