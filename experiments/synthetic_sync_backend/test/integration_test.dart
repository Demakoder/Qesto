import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:qesto_synthetic_sync/client.dart';
import 'package:qesto_synthetic_sync/protocol.dart';
import 'package:test/test.dart';
import 'harness.dart';

void main() {
  late Harness h;
  late ServerProcess s;
  late SyntheticClient a, b;
  setUp(() async {
    h = Harness();
    await h.start();
    s = await h.server();
    a = h.client(s, 0);
    b = h.client(s, 1);
    await a.bootstrap();
    await b.bootstrap();
  });
  tearDown(() async => h.close());

  test('normal entry point works and has no harness crash hook', () async {
    final ordinary = await h.server(faults: false);
    final client = h.client(ordinary, 0);
    ordinary.fault('normal', 'after-state', 'database-error');
    client.prepare('normal', 'ordinary executable');
    expect((await client.push('normal'))['status'], 'accepted');
    await b.pullAll();
    expect(
      b.local['entities']['synthetic-tx-0']['transaction']['userNote'],
      'ordinary executable',
    );
  });

  test('capabilities and restricted role, exact synthetic money', () async {
    final capabilities = await a.request('GET', '/sync/v1/capabilities');
    expect(capabilities['commands'], ['transaction.set_note']);
    expect(
      a.local['entities']['synthetic-tx-0']['transaction']['amount']['minor_units'],
      '486122',
    );
    expect(
      a.local['entities']['synthetic-tx-1']['transaction']['amount']['currency'],
      'USD',
    );
  });
  test(
    'two independent client processes A to B, B to A, offline catch-up',
    () async {
      await h.work(s, 0, ['prepare', 'a1', 'A first']);
      await h.work(s, 0, ['push', 'a1']);
      expect(a.local['seq'], '0'); // HTTP receipt alone is not pull progress.
      await h.work(s, 1, ['pull']);
      expect(
        b.local['entities']['synthetic-tx-0']['transaction']['userNote'],
        'A first',
      );
      await h.work(s, 1, ['prepare', 'b1', 'B reply']);
      await h.work(s, 1, ['push', 'b1']);
      await h.work(s, 1, ['pull']);
      await h.work(s, 1, ['prepare', 'b2', 'While A offline']);
      await h.work(s, 1, ['push', 'b2']);
      await h.work(s, 0, ['pull']);
      expect(a.local['seq'], '3');
      expect(
        a.local['entities']['synthetic-tx-0']['transaction']['userNote'],
        'While A offline',
      );
      await h.work(s, 1, ['pull']);
      expect(a.local['entities'], b.local['entities']);
      File('results/two_client_scenario.json').writeAsStringSync(
        jsonEncode({
          'synthetic_only': true,
          'client_processes': true,
          'a_seq': a.local['seq'],
          'b_seq': b.local['seq'],
          'entities_equal':
              a.local['entities'].toString() == b.local['entities'].toString(),
          'entities': a.local['entities'],
          'receipts': a.local['receipts'],
        }),
      );
    },
  );
  test(
    'idempotent replay same receipt, one audit event, collision rejected',
    () async {
      final command = a.prepare('repeat', 'one');
      final first = await a.push('repeat');
      final second = await a.push('repeat');
      expect(second, first);
      await expectLater(
        a.request(
          'POST',
          '/sync/v1/workspaces/${a.principal.workspace}/push',
          body: {...command, 'note': 'different'},
        ),
        throwsA(
          isA<ApiError>().having(
            (e) => e.code,
            'code',
            'IDEMPOTENCY_KEY_REUSED',
          ),
        ),
      );
      final state = await h.inspect();
      expect(state['head'], 1);
      expect(state['receipts'], 1);
      expect(state['bundles'], 1);
      expect(state['state']['auditEntries'].length, 1);
    },
  );
  test('loss of response after commit retries same durable command', () async {
    a.prepare('lost', 'committed');
    s.fault('lost', 'after-commit', 'drop-response');
    await expectLater(a.push('lost'), throwsA(anything));
    await s.hit();
    expect((await h.inspect())['head'], 1);
    expect(a.local['pending']['lost'], isNotNull);
    expect(a.local['receipts']['lost'], isNull);
    s.clearFault();
    expect((await a.push('lost'))['status'], 'accepted');
    expect((await h.inspect())['head'], 1);
  });
  for (final stage in ['after-state', 'before-commit', 'after-commit']) {
    test(
      'native server process termination at $stage is recoverable',
      () async {
        a.prepare('crash', stage);
        s.fault('crash', stage, 'gate');
        final request = a
            .push('crash')
            .then<Object?>((v) => v, onError: (Object e) => e);
        await s.hit();
        await s.kill();
        await request;
        final before = await h.inspect();
        final committed = stage == 'after-commit';
        expect(before['head'], committed ? 1 : 0);
        expect(before['receipts'], committed ? 1 : 0);
        expect(before['bundles'], committed ? 1 : 0);
        final next = await h.server();
        a = h.client(next, 0);
        expect((await a.push('crash'))['status'], 'accepted');
        expect((await h.inspect())['head'], 1);
        expect((await h.inspect())['state']['auditEntries'].length, 1);
      },
    );
  }
  test(
    'real PostgreSQL error after state write rolls back all three records',
    () async {
      a.prepare('db-error', 'no partial');
      s.fault('db-error', 'after-state', 'database-error');
      await expectLater(
        a.push('db-error'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 503)),
      );
      await s.hit();
      final state = await h.inspect();
      expect(state['head'], 0);
      expect(state['receipts'], 0);
      expect(state['bundles'], 0);
      expect(state['state']['transactions'][0]['userNote'], isNull);
      s.clearFault();
      expect((await a.push('db-error'))['status'], 'accepted');
    },
  );
  test(
    'two server processes and client processes serialize concurrent different records without loss',
    () async {
      final s2 = await h.server();
      await h.work(s, 0, ['prepare', 'parallel-a', 'first', 'synthetic-tx-0']);
      await h.work(s2, 1, [
        'prepare',
        'parallel-b',
        'second',
        'synthetic-tx-1',
      ]);
      await Future.wait([
        h.work(s, 0, ['push', 'parallel-a']),
        h.work(s2, 1, ['push', 'parallel-b']),
      ]);
      await a.pullAll();
      await b.pullAll();
      expect(a.local['entities'], b.local['entities']);
      expect(a.local['seq'], '2');
      expect(
        a.local['entities']['synthetic-tx-0']['transaction']['userNote'],
        'first',
      );
      expect(
        a.local['entities']['synthetic-tx-1']['transaction']['userNote'],
        'second',
      );
    },
  );
  test(
    'concurrent identical command across two servers applies once',
    () async {
      final s2 = await h.server();
      final a2 = h.client(s2, 0);
      final cmd = a.prepare('same', 'same body');
      final path = '/sync/v1/workspaces/${a.principal.workspace}/push';
      final receipts = await Future.wait([
        a.request('POST', path, body: cmd),
        a2.request('POST', path, body: cmd),
      ]);
      expect(receipts[0], receipts[1]);
      expect((await h.inspect())['head'], 1);
    },
  );
  test(
    'concurrent same-field edits retain both proposals as accepted + conflict',
    () async {
      final s2 = await h.server();
      final b2 = h.client(s2, 1);
      a.prepare('conflict-a', 'proposal A');
      b.prepare('conflict-b', 'proposal B');
      final outcomes = await Future.wait([
        a.push('conflict-a'),
        b2.push('conflict-b'),
      ]);
      expect(outcomes.map((v) => v['status']).toSet(), {
        'accepted',
        'conflict',
      });
      final conflict = outcomes.singleWhere((v) => v['status'] == 'conflict');
      expect(
        {
          'proposal A',
          'proposal B',
        }.contains(conflict['conflict']['proposed_note']),
        isTrue,
      );
      expect(
        conflict['conflict']['proposed_note'],
        isNot(conflict['conflict']['current_note']),
      );
      await a.pullAll();
      await b.pullAll();
      expect(a.local['receipts'], b.local['receipts']);
      expect(a.local['pending']['conflict-a']['note'], 'proposal A');
      expect(b.local['pending']['conflict-b']['note'], 'proposal B');
      expect((await h.inspect())['state']['auditEntries'].length, 1);
      expect((await b2.push('conflict-b'))['status'], outcomes[1]['status']);
      expect((await h.inspect())['head'], 2);
    },
  );
  test(
    'delayed earlier commit cannot be skipped by pull or later writer',
    () async {
      final s2 = await h.server();
      final b2 = h.client(s2, 1);
      a.prepare('slow', 'slow');
      b.prepare('fast', 'fast', target: 'synthetic-tx-1');
      s.fault('slow', 'before-commit', 'gate');
      final first = a.push('slow');
      await s.hit();
      var completed = false;
      final second = b2.push('fast').then((v) {
        completed = true;
        return v;
      });
      await h.waitForBlockedWriter();
      expect(completed, false);
      final earlyPage = await b2.page();
      expect(earlyPage['high'], '0');
      expect(earlyPage['bundles'], isEmpty);
      s.release();
      final receipts = await Future.wait([first, second]);
      expect(receipts.map((v) => v['commit_seq']), ['1', '2']);
      await b2.pullAll(limit: 1);
      expect(b2.local['seq'], '2');
      File('results/commit_order_evidence.json').writeAsStringSync(
        jsonEncode({
          'server_pids': [s.process.pid, s2.process.pid],
          'postgres_lock_wait_observed': true,
          'head_while_first_uncommitted': earlyPage['high'],
          'commit_seq': receipts.map((v) => v['commit_seq']).toList(),
          'final_client_seq': b2.local['seq'],
          'head': (await h.inspect())['head'],
        }),
      );
    },
  );
  test(
    'pinned high watermark does not absorb new commits halfway through pagination',
    () async {
      for (var i = 0; i < 2; i++) {
        a.prepare('page-$i', 'n$i');
        await a.push('page-$i');
        await a.pullAll();
      }
      final page1 = await b.page(limit: 1);
      expect(page1['high'], '2');
      b.applyPage(page1);
      a.prepare('page-2', 'new');
      await a.push('page-2');
      final page2 = await b.page(limit: 1);
      expect(page2['high'], '2');
      expect(page2['has_more'], false);
      b.applyPage(page2);
      final nextCycle = await b.page();
      expect(nextCycle['high'], '3');
      b.applyPage(nextCycle);
      expect(b.local['seq'], '3');
    },
  );
  test(
    'page replay is idempotent; corrupt/out-of-order page never advances checkpoint',
    () async {
      a.prepare('page', 'value');
      await a.push('page');
      final p = await b.page();
      final before = b.file.readAsStringSync();
      expect(() => b.applyPage({...p, 'from_seq': '2'}), throwsStateError);
      expect(b.file.readAsStringSync(), before);
      b.applyPage(p);
      final saved = b.file.readAsStringSync();
      b.applyPage(p);
      expect(b.file.readAsStringSync(), saved);
    },
  );
  test(
    'client process exits before checkpoint: original state survives and page is reapplied',
    () async {
      a.prepare('checkpoint', 'persistent');
      await a.push('checkpoint');
      final before = b.file.readAsStringSync();
      final crash = await h.worker(s, 1, ['crash-before-checkpoint']);
      expect(crash.exitCode, 87);
      expect(b.file.readAsStringSync(), before);
      await h.work(s, 1, ['pull']);
      expect(b.local['seq'], '1');
    },
  );
  test(
    'cross-workspace path/body/cursor, fake device and unauthenticated access rejected',
    () async {
      final foreign = h.client(s, 2);
      await foreign.bootstrap();
      for (final path in ['snapshot', 'changes']) {
        await expectLater(
          foreign.request(
            'GET',
            '/sync/v1/workspaces/${a.principal.workspace}/$path',
          ),
          throwsA(isA<ApiError>().having((e) => e.status, 'status', 403)),
        );
      }
      final cmd = a.prepare('foreign', 'blocked');
      await expectLater(
        foreign.request(
          'POST',
          '/sync/v1/workspaces/${foreign.principal.workspace}/push',
          body: cmd,
        ),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        foreign.request(
          'GET',
          '/sync/v1/workspaces/${foreign.principal.workspace}/changes',
          query: {'cursor': a.local['cursor'] as String},
        ),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        a.request(
          'GET',
          '/sync/v1/capabilities',
          headers: {'x-device-id': 'fake'},
        ),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        a.request(
          'GET',
          '/sync/v1/capabilities',
          headers: {'authorization': 'Bearer fake'},
        ),
        throwsA(isA<ApiError>()),
      );
      expect((await h.inspect())['head'], 0);
      expect((await h.inspect(index: 2))['head'], 0);
    },
  );
  test(
    'RLS rejects unscoped and scoped-to-foreign direct app-role reads/writes',
    () async {
      final c = await h.config.connect();
      try {
        expect(await c.execute('SELECT workspace_id FROM workspace'), isEmpty);
        await c.runTx((t) async {
          await t.execute(
            r"SELECT set_config('qesto.workspace', $1, true)",
            parameters: [h.config.principals.last.workspace],
          );
          expect(
            await t.execute(
              r'SELECT * FROM workspace WHERE workspace_id=$1',
              parameters: [a.principal.workspace],
            ),
            isEmpty,
          );
          final update = await t.execute(
            r'UPDATE workspace SET head=99 WHERE workspace_id=$1',
            parameters: [a.principal.workspace],
          );
          expect(update.affectedRows, 0);
        });
        await expectLater(
          c.execute('DELETE FROM command_receipt'),
          throwsA(anything),
        );
      } finally {
        await c.close();
      }
    },
  );
  test(
    'version mismatch, unknown command, wrong epoch and mass assignment do not mutate',
    () async {
      final cmd = a.prepare('reject', 'valid');
      for (final change in [
        {'protocol_version': 2},
        {'domain_version': 2},
        {'kind': 'transaction.delete'},
        {'amount': '1.00'},
        {'workspace_epoch': 'old'},
        {'base_revision': 1},
        {'note': null},
      ]) {
        await expectLater(
          a.request(
            'POST',
            '/sync/v1/workspaces/${a.principal.workspace}/push',
            body: {...cmd, ...change},
          ),
          throwsA(isA<ApiError>()),
        );
      }
      await expectLater(
        a.request(
          'GET',
          '/sync/v1/capabilities',
          headers: {'x-domain-version': '9'},
        ),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        a.request(
          'GET',
          '/sync/v1/capabilities',
          headers: {'origin': 'https://example.invalid'},
        ),
        throwsA(isA<ApiError>()),
      );
      expect((await h.inspect())['head'], 0);
    },
  );
  test(
    'client corruption and incompatible local partition never silently reset',
    () async {
      b.file.writeAsStringSync('{broken');
      expect(() => b.local, throwsFormatException);
      await expectLater(b.bootstrap(), throwsStateError);
      expect(b.file.readAsStringSync(), '{broken');
      final wrong = SyntheticClient(s.base, a.principal, b.file);
      b.file.writeAsStringSync(
        jsonEncode({...a.local, 'device_id': 'someone-else'}),
      );
      expect(() => wrong.local, throwsStateError);
    },
  );
  test(
    'SQL-looking Unicode note is data; oversized body and forged cursor rejected',
    () async {
      const note = "'); DROP TABLE workspace; -- 🧾 заметка 0,13 ₽";
      final cmd = a.prepare('sql-note', note);
      await a.push('sql-note');
      await b.pullAll();
      expect(
        b.local['entities']['synthetic-tx-0']['transaction']['userNote'],
        note,
      );
      await expectLater(
        a.request(
          'POST',
          '/sync/v1/workspaces/${a.principal.workspace}/push',
          body: {...cmd, 'note': 'x' * 20000},
        ),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 413)),
      );
      await expectLater(
        a.request(
          'GET',
          '/sync/v1/workspaces/${a.principal.workspace}/changes',
          query: {'cursor': '${a.local['cursor']}tamper'},
        ),
        throwsA(isA<ApiError>()),
      );
      expect((await h.inspect())['head'], 1);
    },
  );
}
