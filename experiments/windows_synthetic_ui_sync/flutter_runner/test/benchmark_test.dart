import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';

class Measured implements TransactionNoteSyncBoundary {
  Measured(this.owner);
  final WindowsNoteBoundary owner;
  CommittedTransactionNote? note;
  @override
  Future<CommittedTransactionNote> commitNote(
    TransactionNoteIntent intent, {
    NoteCancellation? cancellation,
  }) async => note = await owner.commitNote(intent, cancellation: cancellation);
  @override
  Future<SynchronizedTransactionNotes> synchronize({bool pushPending = true}) =>
      owner.synchronize(pushPending: pushPending);
  @override
  Future<void> close({bool cancelPending = false}) =>
      owner.close(cancelPending: cancelPending);
}

Future<Map<String, Object>> heartbeat(Future<void> Function() work) async {
  final time = Stopwatch()..start(), samples = <double>[];
  var previous = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
    final now = time.elapsedMicroseconds;
    samples.add((now - previous) / 1000);
    previous = now;
  });
  try {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    samples.clear();
    previous = time.elapsedMicroseconds;
    final start = time.elapsedMicroseconds;
    await work();
    final elapsed = (time.elapsedMicroseconds - start) / 1000;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return {
      'total_ms': elapsed,
      'heartbeat_ticks': samples.length,
      'max_primary_isolate_timer_gap_ms': samples.fold<double>(
        0,
        (m, v) => v > m ? v : m,
      ),
    };
  } finally {
    timer.cancel();
  }
}

Map<String, int> files(WindowsNoteBoundary o, UiSyncHarness h, int index) {
  final path = '${h.profiles[index].directory}/container-1.db';
  return {
    'db_bytes': File(path).lengthSync(),
    'wal_bytes': File('$path-wal').existsSync()
        ? File('$path-wal').lengthSync()
        : 0,
  };
}

void main() {
  final runs = <Map<String, Object>>[];
  for (final count in [1000, 10000]) {
    test(
      'two actual controllers with native encrypted sync benchmark $count',
      () async {
        final h = UiSyncHarness(root: '..', evidence: '../results');
        await h.start(count: count);
        final s = await h.server();
        final a = Measured(await h.open(s, 0, create: true)),
            b = Measured(await h.open(s, 1, create: true));
        final initial = (await a.owner.load()).data;
        final ca = BudgetController(
          configuration: budgetConfiguration,
          financialData: initial,
          noteBoundary: a,
        );
        final cb = BudgetController(
          configuration: budgetConfiguration,
          financialData: initial,
          noteBoundary: b,
        );
        final samples = <Map<String, Object>>[];
        try {
          for (var trial = 0; trial < 3; trial++) {
            final target = [0, 1, 3][trial];
            final local = await heartbeat(
              () => ca.setTransactionNote(
                'container-tx-$target',
                'Synthetic measured $trial',
                commandId: 'bench-$trial',
              ),
            );
            SynchronizedTransactionNotes? outbound, incoming;
            final send = await heartbeat(() async {
              outbound = await ca.syncTransactionNotes();
            });
            final receive = await heartbeat(() async {
              incoming = await cb.syncTransactionNotes();
            });
            expect(ca.synoballState.toJson(), cb.synoballState.toJson());
            expect(
              jsonDecode(
                const UserFinancialDataCodec().encode(ca.mergeInto(initial)),
              ),
              (await h.serverState())['state'],
            );
            samples.add({
              'trial': trial + 1,
              'local_edit': local,
              'outbound_sync': send,
              'incoming_sync': receive,
              'local_core_codec_ms': a.note!.preparationMicros / 1000,
              'local_sqlite_commit_ms': a.note!.commitMicros / 1000,
              'outbound_worker_micros': outbound!.timingsMicros,
              'incoming_worker_micros': incoming!.timingsMicros,
              'ui_publication_a_ms': ca.lastNotePublicationMicros / 1000,
              'ui_publication_b_ms': cb.lastNotePublicationMicros / 1000,
              'rss_bytes': ProcessInfo.currentRss,
              'peak_rss_bytes': ProcessInfo.maxRss,
              'client_a_files': files(a.owner, h, 0),
              'client_b_files': files(b.owner, h, 1),
              'full_v7_core_server_parity': true,
            });
          }
          runs.add({
            'count': count,
            'samples': samples,
            'mode':
                'Windows Flutter test debug VM + AOT loopback server + encrypted SQLite worker',
          });
          File('../results/ui-sync-benchmarks.json').writeAsStringSync(
            jsonEncode({
              'runs': runs,
              'complete': runs.length == 2,
              'synthetic_only': true,
              'heartbeat': '8 ms UI isolate timer; not raster frame p95',
              'network_metric': 'HTTP plus backend execution; not WAN latency',
              'production_ready_claim': false,
            }),
            flush: true,
          );
        } finally {
          ca.dispose();
          cb.dispose();
          await a.close();
          await b.close();
          await h.close();
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
