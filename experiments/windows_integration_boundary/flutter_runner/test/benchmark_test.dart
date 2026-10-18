import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/repositories/local_qesto_repository.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';

class MeasuredBoundary implements TransactionNoteBoundary {
  MeasuredBoundary(this.owner);
  final WindowsNoteBoundary owner;
  CommittedTransactionNote? last;
  @override
  Future<CommittedTransactionNote> commitNote(
    TransactionNoteIntent i, {
    NoteCancellation? cancellation,
  }) async => last = await owner.commitNote(i, cancellation: cancellation);
  @override
  Future<void> close({bool cancelPending = false}) =>
      owner.close(cancelPending: cancelPending);
}

Future<Map<String, Object>> heartbeat(Future<void> Function() work) async {
  final samples = <double>[], time = Stopwatch()..start();
  var previous = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
    final now = time.elapsedMicroseconds;
    samples.add((now - previous) / 1000);
    previous = now;
  });
  await Future<void>.delayed(const Duration(milliseconds: 50));
  samples.clear();
  previous = time.elapsedMicroseconds;
  final start = time.elapsedMicroseconds;
  await work();
  final elapsed = (time.elapsedMicroseconds - start) / 1000;
  // Include the first timer tick after a synchronous UI stall or response copy.
  await Future<void>.delayed(const Duration(milliseconds: 30));
  timer.cancel();
  return {
    'total_ms': elapsed,
    'heartbeat_ticks': samples.length,
    'max_primary_isolate_timer_gap_ms': samples.fold<double>(
      0,
      (m, v) => v > m ? v : m,
    ),
  };
}

void main() {
  final runs = <Map<String, Object>>[];
  for (final count in [1000, 10000]) {
    test(
      'actual Flutter controller and native boundary benchmark $count',
      () async {
        final data = syntheticFixture(
          count: count,
          fixturePath:
              '../../storage_feasibility/test/fixtures/container_profile_v7.json',
        );
        const codec = UserFinancialDataCodec();
        final owner = await WindowsNoteBoundary.open(
          SyntheticWindowsProfile.create(),
          initialSnapshot: codec.encode(data),
        );
        final measured = MeasuredBoundary(owner);
        final current = BudgetController(
          configuration: budgetConfiguration,
          financialData: data,
          noteBoundary: measured,
        );
        final repo = LocalQestoRepository(store: MemoryKeyValueStore());
        late BudgetController old;
        old = BudgetController(
          configuration: budgetConfiguration,
          financialData: data,
          onChanged: () => repo.saveUserFinancialData(old.mergeInto(data)),
        );
        final samples = <Map<String, Object>>[];
        try {
          for (var trial = 0; trial < 3; trial++) {
            final target = [0, 1, 3][trial],
                note = 'Synthetic benchmark $trial';
            final legacy = await heartbeat(
              () => old.updateTransaction(
                old.transactions
                    .firstWhere((t) => t.id == 'container-tx-$target')
                    .copyWith(comment: note),
              ),
            );
            final staged = await heartbeat(
              () => current.setTransactionNote(
                'container-tx-$target',
                note,
                commandId: 'bench-$trial',
              ),
            );
            expect(
              financialComparable(codec.encode(current.mergeInto(data))),
              financialComparable(codec.encode(old.mergeInto(data))),
            );
            final receipt = measured.last!;
            samples.add({
              'trial': trial + 1,
              'legacy_memory_repository': legacy,
              'staged_native_boundary': staged,
              'worker_prepare_core_codec_ms': receipt.preparationMicros / 1000,
              'worker_sqlite_commit_ms': receipt.commitMicros / 1000,
              'snapshot_bytes': utf8
                  .encode(codec.encode(current.mergeInto(data)))
                  .length,
              'rss_bytes': ProcessInfo.currentRss,
              'peak_rss_bytes': ProcessInfo.maxRss,
            });
          }
          runs.add({
            'count': count,
            'samples': samples,
            'full_result_parity': true,
            'mode': 'Flutter test debug VM; native encrypted SQLite worker',
          });
          File('../results/flutter-benchmarks.json').writeAsStringSync(
            jsonEncode({
              'runs': runs,
              'complete': runs.length == 2,
              'synthetic_only': true,
              'responsiveness_metric':
                  '8ms primary-isolate timer gaps, not raster-frame p95',
            }),
            flush: true,
          );
        } finally {
          old.dispose();
          current.dispose();
          await measured.close();
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
