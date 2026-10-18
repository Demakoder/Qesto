import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';

const note = TransactionNoteIntent(
  commandId: 'one',
  transactionId: 'container-tx-0',
  note: 'Точная заметка 13 ₽',
  expectedRevision: 0,
);
final exe = File('build/probe/bundle/bin/probe.exe').absolute.path;
Future<ProcessResult> child(
  SyntheticWindowsProfile p,
  String mode, [
  String? fault,
]) => Process.run(
  exe,
  [mode, p.directory, p.workspace, p.device, p.epoch],
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
  environment: {if (fault != null) 'QESTO_4A_PROCESS_FAULT': fault},
);
void main() {
  test(
    'worker prepares configured policy and commits exact complete v7 result and immutable outbox',
    () async {
      final p = SyntheticWindowsProfile.create(), initial = encodeSynthetic();
      final time = SyntheticBookkeeping(DateTime.utc(2026, 10, 12));
      final owner = await WindowsNoteBoundary.open(
        p,
        initialSnapshot: initial,
        bookkeeping: time,
      );
      try {
        final result = await owner.commitNote(note);
        final expected = prepareTransactionNote(
          const UserFinancialDataCodec().decode(initial),
          note.transactionId,
          note.note,
          clock: time.now,
          ids: SyntheticIds(note.commandId),
        );
        expect(
          jsonDecode(const UserFinancialDataCodec().encode(result.data)),
          jsonDecode(const UserFinancialDataCodec().encode(expected.data)),
        );
        expect(result.revision, 1);
        expect(
          result.data.synoballState!.transactions.first.amount.minorUnits,
          486122,
        );
        expect(
          result.data.synoballState!.transactions.first.userCategoryOverride,
          'fitness-custom',
        );
        expect(
          result.data.synoballState!.transactions[1].tags,
          contains('user-category-rule:synthetic-rule'),
        );
        final pending = (await owner.pending()).single;
        expect(jsonDecode(pending.immutableJson)['intent']['note'], note.note);
        expect(
          jsonDecode(pending.immutableJson)['intent']['change_id'],
          note.commandId,
        );
        final again = await owner.commitNote(note);
        expect(again.revision, 1);
        expect(
          (await owner.pending()).single.immutableJson,
          pending.immutableJson,
        );
        final bytes = File('${p.directory}/container-1.db').readAsBytesSync();
        expect(latin1.decode(bytes).startsWith('SQLite format 3'), false);
        expect(latin1.decode(bytes).contains(note.note), false);
      } finally {
        await owner.close();
      }
      final reopened = await WindowsNoteBoundary.open(p);
      try {
        expect((await reopened.load()).revision, 1);
        expect(await reopened.pending(), hasLength(1));
      } finally {
        await reopened.close();
      }
    },
  );
  test(
    'FIFO CAS rejects a concurrent stale mutation; repeat ID with different note is rejected',
    () async {
      final owner = await WindowsNoteBoundary.open(
        SyntheticWindowsProfile.create(),
        initialSnapshot: encodeSynthetic(),
      );
      try {
        final a = owner.commitNote(note);
        final b = owner.commitNote(
          const TransactionNoteIntent(
            commandId: 'two',
            transactionId: 'container-tx-1',
            note: 'stale',
            expectedRevision: 0,
          ),
        );
        final rejection = expectLater(b, throwsA(isA<NoteBoundaryFailure>()));
        expect((await a).revision, 1);
        await rejection;
        await expectLater(
          owner.commitNote(
            const TransactionNoteIntent(
              commandId: 'one',
              transactionId: 'container-tx-0',
              note: 'collision',
              expectedRevision: 1,
            ),
          ),
          throwsA(isA<NoteBoundaryFailure>()),
        );
        expect(await owner.pending(), hasLength(1));
      } finally {
        await owner.close();
      }
    },
  );
  test('failure before commit rolls back state and command', () async {
    final owner = await WindowsNoteBoundary.open(
      SyntheticWindowsProfile.create(),
      initialSnapshot: encodeSynthetic(),
      probe: BoundaryProbe.beforeCommitError,
    );
    try {
      await expectLater(
        owner.commitNote(note),
        throwsA(isA<NoteBoundaryFailure>()),
      );
      expect((await owner.load()).revision, 0);
      expect(await owner.pending(), isEmpty);
    } finally {
      await owner.close();
    }
  });
  test(
    'failure after commit before reply is unknown but durable state survives reopen',
    () async {
      final p = SyntheticWindowsProfile.create();
      final owner = await WindowsNoteBoundary.open(
        p,
        initialSnapshot: encodeSynthetic(),
        probe: BoundaryProbe.afterCommitError,
      );
      await expectLater(
        owner.commitNote(note),
        throwsA(
          isA<NoteBoundaryFailure>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            true,
          ),
        ),
      );
      await owner.close();
      final next = await WindowsNoteBoundary.open(p);
      try {
        expect((await next.load()).revision, 1);
        expect(await next.pending(), hasLength(1));
      } finally {
        await next.close();
      }
    },
  );
  for (final after in [false, true]) {
    test(
      'cancellation ${after ? 'after' : 'before'} commit has explicit durability',
      () async {
        final owner = await WindowsNoteBoundary.open(
          SyntheticWindowsProfile.create(),
          initialSnapshot: encodeSynthetic(),
          probe: after
              ? BoundaryProbe.afterCommitGate
              : BoundaryProbe.beforeCommitGate,
        );
        final cancellation = NoteCancellation();
        final gate = owner.stages.first;
        final response = owner.commitNote(note, cancellation: cancellation);
        final rejected = expectLater(
          response,
          throwsA(
            isA<NoteBoundaryFailure>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              after,
            ),
          ),
        );
        await gate;
        cancellation.cancel();
        await rejected;
        expect((await owner.load()).revision, after ? 1 : 0);
        expect((await owner.pending()).length, after ? 1 : 0);
        await owner.close();
      },
    );
  }
  test(
    'shutdown cancels active precommit and queued mutations then closes without loss',
    () async {
      final owner = await WindowsNoteBoundary.open(
        SyntheticWindowsProfile.create(),
        initialSnapshot: encodeSynthetic(),
        probe: BoundaryProbe.beforeCommitGate,
      );
      final gate = owner.stages.first;
      final a = owner.commitNote(note);
      final b = owner.commitNote(
        const TransactionNoteIntent(
          commandId: 'two',
          transactionId: 'container-tx-1',
          note: 'queued',
          expectedRevision: 0,
        ),
      );
      final aa = expectLater(a, throwsA(isA<NoteBoundaryFailure>())),
          bb = expectLater(b, throwsA(isA<NoteBoundaryFailure>()));
      await gate;
      await owner.close(cancelPending: true);
      await aa;
      await bb;
      await expectLater(owner.load(), throwsA(isA<NoteBoundaryFailure>()));
    },
  );
  test(
    'graceful shutdown drains accepted command; shutdown error never reopens silently',
    () async {
      final p = SyntheticWindowsProfile.create();
      final owner = await WindowsNoteBoundary.open(
        p,
        initialSnapshot: encodeSynthetic(),
        probe: BoundaryProbe.closeError,
      );
      final response = owner.commitNote(note);
      final closed = expectLater(
        owner.close(),
        throwsA(isA<NoteBoundaryFailure>()),
      );
      expect((await response).revision, 1);
      await closed;
      final next = await WindowsNoteBoundary.open(p);
      try {
        expect((await next.load()).revision, 1);
      } finally {
        await next.close();
      }
    },
  );
  for (final stage in [
    'local-after-snapshot',
    'local-before-commit',
    'after-commit-before-reply',
  ]) {
    test('native process crash $stage and restart retain atomicity', () async {
      final p = SyntheticWindowsProfile.create();
      await (await WindowsNoteBoundary.open(
        p,
        initialSnapshot: encodeSynthetic(),
      )).close();
      final crash = await child(p, 'edit', stage);
      expect(crash.exitCode, 86, reason: '${crash.stdout} ${crash.stderr}');
      final restored = await child(p, 'verify');
      expect(
        restored.exitCode,
        0,
        reason: '${restored.stdout} ${restored.stderr}',
      );
      final state = jsonDecode((restored.stdout as String).trim());
      final count = stage == 'after-commit-before-reply' ? 1 : 0;
      expect(state['revision'], count);
      expect(state['pending'], count);
      expect(
        state['snapshot']['synoball']['transactions'][0]['userNote'],
        count == 1 ? 'Native durable note' : 'user-owned note',
      );
    });
  }
  test('worker death is fail closed and needs full process restart', () async {
    final p = SyntheticWindowsProfile.create();
    await (await WindowsNoteBoundary.open(
      p,
      initialSnapshot: encodeSynthetic(),
    )).close();
    final dead = await child(p, 'kill-worker');
    expect(dead.exitCode, 0, reason: '${dead.stdout} ${dead.stderr}');
    expect(jsonDecode((dead.stdout as String).trim())['hot_restart'], false);
    expect((await child(p, 'verify')).exitCode, 0);
  });
  for (final corrupt in [false, true]) {
    test(
      '${corrupt ? 'corrupt' : 'missing'} synthetic key fails closed and retains bytes',
      () async {
        final p = SyntheticWindowsProfile.create();
        final owner = await WindowsNoteBoundary.open(
          p,
          initialSnapshot: encodeSynthetic(),
        );
        await owner.commitNote(note);
        await owner.close();
        final vault = File('${p.directory}/container-vault.bin'),
            bytes = vault.readAsBytesSync();
        if (corrupt) {
          vault.writeAsBytesSync([0, 1, 2, 3], flush: true);
        } else {
          vault.renameSync('${vault.path}.retained');
        }
        await expectLater(
          WindowsNoteBoundary.open(p),
          throwsA(isA<NoteBoundaryFailure>()),
        );
        if (corrupt) {
          expect(vault.readAsBytesSync(), [0, 1, 2, 3]);
        } else {
          expect(vault.existsSync(), false);
        }
        vault.writeAsBytesSync(bytes, flush: true);
        final restored = await WindowsNoteBoundary.open(p);
        try {
          expect((await restored.load()).revision, 1);
        } finally {
          await restored.close();
        }
      },
    );
  }
  test('second native process cannot own encrypted container', () async {
    final p = SyntheticWindowsProfile.create();
    final owner = await WindowsNoteBoundary.open(
      p,
      initialSnapshot: encodeSynthetic(),
    );
    try {
      expect((await child(p, 'verify')).exitCode, 2);
    } finally {
      await owner.close();
    }
  });
  test(
    'unmarked production-looking path rejected before store access',
    () async {
      await expectLater(
        WindowsNoteBoundary.open(
          const SyntheticWindowsProfile(
            'C:/not-a-qesto-profile',
            'real',
            'real',
            'real',
          ),
        ),
        throwsA(isA<NoteBoundaryFailure>()),
      );
    },
  );
}
