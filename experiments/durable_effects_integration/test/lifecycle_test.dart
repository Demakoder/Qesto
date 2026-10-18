import 'package:test/test.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import '../lib/windows_driver.dart';

void main() {
  for (final after in [false, true]) {
    test(
      'shutdown queued/in-flight, commit already happened: $after',
      () async {
        final p = SyntheticWindowsProfile.create();
        final owner = await WindowsNoteBoundary.open(
          p,
          initialSnapshot: encodeSynthetic(),
          incremental: true,
          effectsDriver: const EffectsDriverFactory(),
          probe: after
              ? BoundaryProbe.afterCommitGate
              : BoundaryProbe.beforeCommitGate,
        );
        final stage = owner.stages.first;
        final a = owner.commitDeltaForExperiment(
          const TransactionNoteIntent(
            commandId: 'one',
            transactionId: 'container-tx-0',
            note: 'active',
            expectedRevision: 0,
          ),
        );
        final b = owner.commitDeltaForExperiment(
          const TransactionNoteIntent(
            commandId: 'two',
            transactionId: 'container-tx-1',
            note: 'queued',
            expectedRevision: 0,
          ),
        );
        final rejectedA = expectLater(
          a,
          throwsA(
            isA<NoteBoundaryFailure>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              after,
            ),
          ),
        );
        final rejectedB = expectLater(b, throwsA(isA<NoteBoundaryFailure>()));
        await stage;
        await owner.close(cancelPending: true);
        await rejectedA;
        await rejectedB;
        final reopened = await WindowsNoteBoundary.open(
          p,
          effectsDriver: const EffectsDriverFactory(),
        );
        try {
          expect((await reopened.load()).revision, after ? 1 : 0);
          expect((await reopened.pending()).length, after ? 1 : 0);
        } finally {
          await reopened.close();
        }
      },
    );
  }
}
