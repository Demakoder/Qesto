import 'package:test/test.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';
import 'package:qesto_synthetic_sync/protocol.dart';
import '../lib/bounded_executor.dart';
import 'domain_owner_test.dart' show command, time;

void main() {
  test(
    'exact input and owner, single-entry admission and rejection, unchanged execution',
    () {
      final source = encodeSynthetic(), second = encodeSynthetic(count: 6);
      final e = BoundedNoteExecutor(
        budgetBytes: BoundedNoteExecutor.estimate(source),
      );
      final first = e.data(source, syntheticUser);
      expect(identical(e.data(source, syntheticUser), first), isTrue);
      expect(e.hits, 1);
      expect(e.retainedEstimate, lessThanOrEqualTo(e.budgetBytes));
      e.data(second, syntheticUser);
      expect(e.rejected, 1);
      expect(e.retainedEstimate, 0);
      final c = command('bounded');
      expect(
        e.execute(source, c, syntheticUser, time).stored,
        const QestoNoteExecutor()
            .execute(source, c, syntheticUser, time)
            .stored,
      );
      expect(
        () => e.data(source, 'synthetic-4a-foreign'),
        throwsA(isA<ApiError>()),
      );
      expect(e.retainedEstimate, 0);
      expect(() => e.data('corrupted', syntheticUser), throwsA(anything));
      expect(e.retainedEstimate, 0);
    },
  );
}
