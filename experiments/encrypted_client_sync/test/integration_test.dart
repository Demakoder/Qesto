import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_encrypted_sync_experiment/coordinator.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'harness.dart';

Map<String, dynamic> transaction(Map<String, dynamic> status, int index) =>
    (status['snapshot']['synoball']['transactions'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((t) => t['id'] == 'container-tx-$index');

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.start();
  });
  tearDown(() async {
    await h.close();
  });

  test(
    'two encrypted CLI clients: offline edits, receipts, delivery, exact values and v7 codec',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      final keyBytes = [
        for (final d in h.clients)
          File('${d.path}/container-vault.bin').readAsBytesSync(),
      ];
      // Network is genuinely absent while both local commits receive ACK.
      await s.kill();
      final a = await h.ok(s, 0, 'edit', [
        'a-first',
        'container-tx-0',
        'Client A private note',
      ]);
      final b = await h.ok(s, 1, 'edit', [
        'b-first',
        'container-tx-1',
        'Client B private note',
      ]);
      expect(a['local_ack'], true);
      expect(b['local_ack'], true);
      expect(a['checkpoint'], 0);
      expect(b['checkpoint'], 0);
      final online = await h.server();
      await h.ok(online, 0, 'push');
      expect((await h.ok(online, 0, 'verify'))['checkpoint'], 0);
      // B has a durable local proposal while accepting remote edit to a different entity.
      await h.ok(online, 1, 'pull');
      final mixed = await h.ok(online, 1, 'verify');
      expect(transaction(mixed, 0)['userNote'], 'Client A private note');
      expect(transaction(mixed, 1)['userNote'], 'Client B private note');
      expect((mixed['pending'] as List).length, 1);
      await h.ok(online, 1, 'sync');
      await h.ok(online, 0, 'pull');
      final aa = await h.ok(online, 0, 'verify'),
          bb = await h.ok(online, 1, 'verify');
      expect(
        aa['snapshot']['synoball']['transactions'],
        bb['snapshot']['synoball']['transactions'],
      );
      expect(aa['pending'], isEmpty);
      expect(bb['pending'], isEmpty);
      expect(aa['checkpoint'], 2);
      expect(bb['checkpoint'], 2);
      expect(transaction(aa, 0)['amount'], {
        'value': '4861.22',
        'currency': 'RUB',
      });
      expect(transaction(aa, 1)['amount'], {
        'value': '15000.25',
        'currency': 'USD',
      });
      expect(transaction(aa, 2)['status'], 'deleted');
      for (final data in [aa, bb]) {
        expect(
          data['snapshot']['synoball']['rawPayloads'],
          jsonDecode(h.initial.json)['synoball']['rawPayloads'],
        );
        expect(transaction(data, 0)['tags'], [
          'user-field:category',
          'user-field:note',
        ]);
        expect(transaction(data, 0)['userCategoryOverride'], 'sport');
        final legacy = (data['snapshot']['transactions'] as List).firstWhere(
          (t) => t['id'] == 'container-tx-0',
        );
        expect(legacy['comment'], 'Client A private note');
      }
      final before = jsonDecode(h.initial.json) as Map;
      for (final key in before.keys.where(
        (k) => k != 'synoball' && k != 'transactions',
      )) {
        expect(
          aa['snapshot'][key],
          before[key],
          reason: 'unrelated full-profile section $key',
        );
        expect(bb['snapshot'][key], before[key]);
      }
      for (var i = 0; i < 2; i++) {
        final status = i == 0 ? aa : bb;
        final output = File('${h.clients[i].path}/codec-output.json')
          ..writeAsStringSync(jsonEncode(status['snapshot']));
        final gate = await Process.run(dart, [
          '--packages=../../apps/qesto_app/.dart_tool/package_config.json',
          'tool/codec_gate.dart',
          output.path,
        ]);
        expect(gate.exitCode, 0, reason: '${gate.stdout} ${gate.stderr}');
        // Native file must not be ordinary SQLite or contain the private notes.
        final bytes = File(
          '${h.clients[i].path}/container-1.db',
        ).readAsBytesSync();
        final text = latin1.decode(bytes);
        expect(text.startsWith('SQLite format 3'), false);
        expect(text.contains('private note'), false);
        expect(
          File('${h.clients[i].path}/container-vault.bin').readAsBytesSync(),
          keyBytes[i],
        );
      }
      // Missed changes after another process restart/offline.
      await h.ok(online, 0, 'edit', [
        'a-second',
        'container-tx-0',
        'Later offline delivery',
      ]);
      await h.ok(online, 0, 'sync');
      await h.ok(online, 1, 'pull');
      expect(
        transaction(await h.ok(online, 1, 'verify'), 0)['userNote'],
        'Later offline delivery',
      );
      File('results/two_encrypted_clients.json').writeAsStringSync(
        jsonEncode({
          'passed': true,
          'independent_encrypted_databases': 2,
          'cli_processes': true,
          'codec_v7_lossless': true,
          'checkpoints_after_convergence': [2, 2],
          'notes_converged': true,
          'exact_minor_units': [486122, 1500025, 13],
          'currencies': ['RUB', 'USD', 'RUB'],
          'unrelated_sections_unchanged': true,
        }),
      );
    },
  );

  test(
    'same field conflict keeps both versions and survives repeated sync/restart',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      await h.ok(s, 0, 'edit', ['same-a', 'container-tx-0', 'Proposal A']);
      await h.ok(s, 1, 'edit', ['same-b', 'container-tx-0', 'Proposal B']);
      await h.ok(s, 0, 'sync');
      expect((await h.ok(s, 1, 'sync'))['outcome'], 'requires_attention');
      final conflicted = await h.ok(s, 1, 'verify');
      expect(transaction(conflicted, 0)['userNote'], 'Proposal B');
      expect(conflicted['pending'].single['state'], 'conflict');
      final receipt = jsonDecode(conflicted['pending'].single['receipt']);
      expect(receipt['payload']['conflict']['proposed_note'], 'Proposal B');
      expect(receipt['payload']['conflict']['current_note'], 'Proposal A');
      for (var i = 0; i < 2; i++) {
        await h.ok(s, 1, 'sync');
      }
      final again = await h.ok(s, 1, 'verify');
      expect(again, conflicted);
      expect((await h.serverState())['head'], 2);
      final store = await h.open(1);
      try {
        expect(
          jsonDecode(
            (await store.readRemoteContext())!.shadow.json,
          )['synoball']['transactions'][0]['userNote'],
          'Proposal A',
        );
      } finally {
        await store.close();
      }
    },
  );

  for (final stage in ['local-after-snapshot', 'local-before-commit']) {
    test('process crash $stage rolls back snapshot AND outbox', () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      final r = await h.run(s, 0, 'edit', [
        'crash-local',
        'container-tx-0',
        'Never acked',
      ], stage);
      expect(r.exitCode, 86);
      final status = await h.ok(s, 0, 'verify');
      expect(status['revision'], 0);
      expect(status['pending'], isEmpty);
      expect(transaction(status, 0)['userNote'], 'user-owned note');
    });
  }

  test(
    'after local commit process exits before push; next process recovers durable command',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      final killed = await h.run(s, 0, 'edit', [
        'durable',
        'container-tx-0',
        'Durable offline',
      ], 'after-local-commit');
      expect(killed.exitCode, 86);
      expect((await h.serverState())['head'], 0);
      final status = await h.ok(s, 0, 'verify');
      expect(status['revision'], 1);
      expect(status['pending'].single['id'], 'durable');
      await h.ok(s, 0, 'sync');
      expect((await h.serverState())['head'], 1);
    },
  );

  test(
    'HTTP response lost after server commit, bounded retries use same immutable command',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      await h.ok(s, 0, 'edit', [
        'lost',
        'container-tx-0',
        'Response may disappear',
      ]);
      s.fault('lost', 'after-commit', 'drop-response');
      final failed = await h.run(s, 0, 'push');
      expect(failed.exitCode, 2);
      expect((await h.serverState())['head'], 1);
      final waiting = await h.ok(s, 0, 'verify');
      expect(waiting['checkpoint'], 0);
      expect(waiting['pending'].single['state'], 'queued');
      s.clearFault();
      await h.ok(s, 0, 'sync');
      await h.ok(s, 1, 'pull');
      expect((await h.serverState())['head'], 1);
      expect((await h.ok(s, 0, 'verify'))['pending'], isEmpty);
      expect(
        transaction(await h.ok(s, 1, 'verify'), 0)['userNote'],
        'Response may disappear',
      );
    },
  );

  test(
    'crash during receipt persistence keeps command replayable without advancing cursor',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      await h.ok(s, 0, 'edit', ['ack-crash', 'container-tx-0', 'ACK crash']);
      expect((await h.run(s, 0, 'push', [], 'ack-after-receipt')).exitCode, 86);
      expect((await h.serverState())['head'], 1);
      final pending = await h.ok(s, 0, 'verify');
      expect(pending['checkpoint'], 0);
      expect(pending['pending'].single['state'], 'queued');
      await h.ok(s, 0, 'sync');
      expect((await h.serverState())['head'], 1);
      expect((await h.ok(s, 0, 'verify'))['pending'], isEmpty);
    },
  );

  test(
    'network break during uncommitted push, server restart and same-ID retry',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      await h.ok(s, 0, 'edit', ['break', 'container-tx-0', 'Retry me']);
      s.fault('break', 'before-commit', 'gate');
      final attempt = h.run(s, 0, 'push');
      await s.hit();
      await s.kill();
      expect((await attempt).exitCode, 2);
      expect((await h.serverState())['head'], 0);
      final fresh = await h.server();
      await h.ok(fresh, 0, 'sync');
      expect((await h.serverState())['head'], 1);
    },
  );

  for (final stage in ['remote-before-checkpoint', 'remote-before-commit']) {
    test(
      'incoming process crash $stage leaves old state/shadow/cursor recoverable',
      () async {
        final s = await h.server();
        await h.bootstrapBoth(s);
        await h.ok(s, 0, 'edit', ['remote-crash', 'container-tx-0', 'Remote']);
        await h.ok(s, 0, 'sync');
        final result = await h.run(s, 1, 'pull', [], stage);
        expect(result.exitCode, 86);
        final before = await h.ok(s, 1, 'verify');
        expect(before['checkpoint'], 0);
        expect(transaction(before, 0)['userNote'], 'user-owned note');
        await h.ok(s, 1, 'pull');
        expect((await h.ok(s, 1, 'verify'))['checkpoint'], 1);
      },
    );
  }

  test('duplicate incoming page after reopen is a no-op', () async {
    final s = await h.server();
    await h.bootstrapBoth(s);
    await h.ok(s, 0, 'edit', ['repeat', 'container-tx-0', 'Replay']);
    await h.ok(s, 0, 'sync');
    var store = await h.open(1);
    var c = h.coordinator(store, s, 1);
    final page = await c.page();
    await c.applyPage(page);
    final before = await store.readSnapshot();
    await store.close();
    store = await h.open(1);
    c = h.coordinator(store, s, 1);
    try {
      expect(await c.applyPage(page), false);
      expect((await store.readSnapshot()).value.hash, before.value.hash);
      expect((await store.readSnapshot()).revision, before.revision);
    } finally {
      await store.close();
    }
  });

  test(
    'PostgreSQL restart preserves receipt and encrypted client delivery',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      await h.ok(s, 0, 'edit', [
        'pg-restart',
        'container-tx-0',
        'Postgres durable',
      ]);
      await h.ok(s, 0, 'push');
      for (final action in ['stop', 'resume']) {
        final r = await Process.run(dart, [
          'run',
          'tool/cluster.dart',
          action,
        ], workingDirectory: backend);
        expect(r.exitCode, 0, reason: '${r.stdout} ${r.stderr}');
      }
      await h.ok(s, 0, 'sync');
      await h.ok(s, 1, 'pull');
      expect((await h.serverState())['head'], 1);
      expect(
        transaction(await h.ok(s, 1, 'verify'), 0)['userNote'],
        'Postgres durable',
      );
    },
  );

  for (final corruption in ['missing', 'corrupt']) {
    test(
      '$corruption key fails closed and retains state for explicit recovery',
      () async {
        final s = await h.server();
        await h.bootstrapBoth(s);
        await h.ok(s, 0, 'edit', [
          'key-recovery',
          'container-tx-0',
          'Preserve me',
        ]);
        final vault = File('${h.clients[0].path}/container-vault.bin');
        final bytes = vault.readAsBytesSync();
        if (corruption == 'missing') {
          vault.renameSync('${vault.path}.retained');
        } else {
          vault.writeAsBytesSync([0, 1, 2, 3], flush: true);
        }
        final result = await h.run(s, 0, 'verify');
        expect(result.exitCode, 2);
        expect(File('${h.clients[0].path}/container-1.db').existsSync(), true);
        if (corruption == 'missing') {
          expect(vault.existsSync(), false);
        } else {
          expect(vault.readAsBytesSync(), [0, 1, 2, 3]);
        }
        vault.writeAsBytesSync(
          bytes,
          flush: true,
        ); // explicit synthetic recovery
        final status = await h.ok(s, 0, 'verify');
        expect(status['pending'].single['id'], 'key-recovery');
        expect(transaction(status, 0)['userNote'], 'Preserve me');
      },
    );
  }

  test(
    'second process cannot own database; stale local revision and duplicate ID rejected',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      final store = await h.open(0);
      try {
        expect((await h.run(s, 0, 'verify')).exitCode, 2);
        final c = h.coordinator(store, s, 0);
        await c.edit('owned', 'container-tx-0', 'Once');
        expect((await c.edit('owned', 'container-tx-0', 'Once')).revision, 1);
        await expectLater(
          c.edit('owned', 'container-tx-0', 'Changed'),
          throwsA(isA<ContractViolation>()),
        );
        await expectLater(
          c.edit('stale', 'container-tx-1', 'Stale', expectedRevision: 0),
          throwsA(isA<ContractViolation>()),
        );
        await expectLater(
          c.edit('queued', 'container-tx-0', 'Another'),
          throwsA(isA<ContractViolation>()),
        );
        expect((await store.readPendingCommands()).length, 1);
      } finally {
        await store.close();
      }
    },
  );

  test(
    'stale/incompatible remote entity, unsupported financial update, bad receipt stop before apply',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      await h.ok(s, 0, 'edit', ['invalid-page', 'container-tx-0', 'Valid']);
      await h.ok(s, 0, 'sync');
      final store = await h.open(1);
      final c = h.coordinator(store, s, 1);
      try {
        final page = await c.page();
        for (final mutation in [
          'revision',
          'amount',
          'sequence',
          'version',
          'epoch',
        ]) {
          final bad = w.object(jsonDecode(jsonEncode(page)));
          switch (mutation) {
            case 'revision':
              bad['bundles'][0]['entities'][0]['revision'] = '99';
            case 'amount':
              bad['bundles'][0]['entities'][0]['transaction']['amount']['minor_units'] =
                  '1';
            case 'sequence':
              bad['bundles'][0]['seq'] = '2';
            case 'version':
              bad['domain_version'] = 2;
            case 'epoch':
              bad['workspace_epoch'] = 'unknown';
          }
          await expectLater(c.applyPage(bad), throwsA(anything));
          expect(await store.readCheckpoint(), 0);
          expect((await store.readSnapshot()).revision, 0);
        }
        await c.applyPage(page);
        expect(await store.readCheckpoint(), 1);
      } finally {
        await store.close();
      }
    },
  );

  test(
    'HTTP200 without valid receipt, auth/version errors are not ACK and not endlessly retried',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      final store = await h.open(0);
      try {
        await h
            .coordinator(store, s, 0)
            .edit('no-ack', 'container-tx-0', 'Must remain pending');
        for (final failure in ['invalid200', 'auth', 'version']) {
          var calls = 0;
          final c = Coordinator(store, h.partition, h.config.principals[0], (
            method,
            path, {
            body,
            query,
          }) async {
            calls++;
            if (failure == 'auth') throw const w.ApiError(401, 'UNAUTHORIZED');
            if (failure == 'version')
              throw const w.ApiError(409, 'VERSION_MISMATCH');
            return {'ok': true};
          });
          await expectLater(c.push(), throwsA(anything));
          expect(calls, 1);
          expect(
            (await store.readPendingCommands()).single.receipt.state,
            DeliveryState.queued,
          );
          expect(await store.readCheckpoint(), 0);
        }
      } finally {
        await store.close();
      }
    },
  );

  test(
    'encrypted sync context survives backup/rotation/restart without cursor loss',
    () async {
      final s = await h.server();
      await h.bootstrapBoth(s);
      await h.ok(s, 0, 'edit', ['rotation', 'container-tx-0', 'Rotate']);
      await h.ok(s, 0, 'sync');
      await h.ok(s, 1, 'pull');
      for (var i = 0; i < 2; i++) {
        var store = await h.open(i);
        final context = (await store.readRemoteContext())!.json;
        try {
          if (i == 0) {
            await store.backup();
          } else {
            await store.rotateKey();
          }
        } finally {
          await store.close();
        }
        store = await h.open(i);
        try {
          expect((await store.readRemoteContext())!.json, context);
          expect(await store.readCheckpoint(), 1);
          expect((await store.readPendingCommands()), isEmpty);
        } finally {
          await store.close();
        }
      }
    },
  );
}
