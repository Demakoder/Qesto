import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'package:qesto_storage_spike/wal_policy.dart';
import 'package:qesto_incremental_sync_experiment/harness.dart';
import 'package:qesto_incremental_sync_experiment/measure.dart';
import '../../../windows_synthetic_ui_sync/flutter_runner/test/benchmark_test.dart'
    show heartbeat, Measured;
import '../../../windows_synthetic_ui_sync/flutter_runner/test/two_ui_hosts_test.dart'
    show NoteHost;

void main({UiSyncHarness Function()? harnessFactory, String? label, String outputDirectory = '../results'}) {
  final runs = <Object>[];
  final mode = label ?? Platform.environment['QESTO_4C_BENCH_MODE'] ?? 'incremental';
  final counts = (Platform.environment['QESTO_4C_COUNTS'] ?? '1000,10000')
      .split(',')
      .map(int.parse);
  for (final count in counts) {
    testWidgets(
      '$mode real UI/controller benchmark $count',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final UiSyncHarness h = harnessFactory != null ? harnessFactory() : mode == 'incremental'
            ? IncrementalHarness(location: '..')
            : UiSyncHarness(
                root: '../../windows_synthetic_ui_sync',
                evidence: '../../windows_synthetic_ui_sync/results',
              );
        late Measured a, b;
        late BudgetController ca, cb;
        late dynamic server;
        final opened = <Measured>[];
        var ready = false;
        await tester.runAsync(() async {
          try {
            await h.start(count: count);
            server = await h.server();
            a = Measured(await h.open(server, 0, create: true));
            opened.add(a);
            b = Measured(await h.open(server, 1, create: true));
            opened.add(b);
            final initial = (await a.owner.load()).data;
            ca = BudgetController(
              configuration: budgetConfiguration,
              financialData: initial,
              noteBoundary: a,
            );
            cb = BudgetController(
              configuration: budgetConfiguration,
              financialData: initial,
              noteBoundary: b,
            );
            ready = true;
          } finally {
            if (!ready) {
              for (final owner in opened) {
                await owner.close();
              }
              await h.close();
            }
          }
        });
        // runAsync reports its exception to Flutter rather than rethrowing.
        // Do not obscure the actual startup failure with uninitialized locals.
        if (!ready) return;
        final samples = <Object>[];
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildQestoTheme(),
              home: Scaffold(
                body: Row(
                  children: [
                    Expanded(child: NoteHost('A', ca, () {}, () {})),
                    Expanded(child: NoteHost('B', cb, () {}, () {})),
                  ],
                ),
              ),
            ),
          );
          for (var trial = 0; trial < (count == 50000 ? 1 : 3); trial++) {
            late Map<String, Object> local, send, receive;
            late SynchronizedTransactionNotes outgoing, incoming;
            late Map<String, dynamic> diagnosticsA, diagnosticsB;
            late int cpu;
            await tester.runAsync(() async {
              final start = cpuMicros();
              local = await heartbeat(
                () => ca.setTransactionNote(
                  'container-tx-${[0, 1, 3][trial]}',
                  'Synthetic measured $trial',
                  commandId: 'bench-$trial',
                ),
              );
              send = await heartbeat(() async {
                outgoing = await ca.syncTransactionNotes();
              });
              receive = await heartbeat(() async {
                incoming = await cb.syncTransactionNotes();
              });
              cpu = cpuMicros() - start;
              diagnosticsA = await a.owner.inspectForTest();
              diagnosticsB = await b.owner.inspectForTest();
              expect(ca.synoballState.toJson(), cb.synoballState.toJson());
              expect(
                jsonDecode(
                  const UserFinancialDataCodec().encode(
                    ca.mergeInto((await a.owner.load()).data),
                  ),
                ),
                (await h.serverState())['state'],
              );
              expect(await b.owner.pending(), isEmpty);
            });
            final frame = Stopwatch()..start();
            await tester.pump();
            final buildUs = frame.elapsedMicroseconds;
            expect(tester.takeException(), isNull);
            final metricFile = File('${server.control.path}.metrics.json');
            samples.add({
              'trial': trial + 1,
              'local_edit': local,
              'outbound_sync': send,
              'incoming_sync': receive,
              'host_cpu_us_three_phases': cpu,
              'local_prepare_us': a.note!.preparationMicros,
              'local_commit_us': a.note!.commitMicros,
              'outbound_worker_us': outgoing.timingsMicros,
              'incoming_worker_us': incoming.timingsMicros,
              'publication_a_us': ca.lastNotePublicationMicros,
              'publication_b_us': cb.lastNotePublicationMicros,
              'two_details_ui_pump_us': buildUs,
              'rss_bytes': ProcessInfo.currentRss,
              'peak_rss_bytes': ProcessInfo.maxRss,
              'files_a': sizes('${h.profiles[0].directory}/container-1.db'),
              'files_b': sizes('${h.profiles[1].directory}/container-1.db'),
              'storage_a': diagnosticsA['storage_metrics'],
              'storage_b': diagnosticsB['storage_metrics'],
              'http_a': diagnosticsA['transport_metrics'],
              'http_b': diagnosticsB['transport_metrics'],
              'server': metricFile.existsSync()
                  ? jsonDecode(metricFile.readAsStringSync())
                  : null,
              'full_v7_parity': true,
            });
          }
          runs.add({'count': count, 'samples': samples});
          File(
            '$outputDirectory/flutter-$mode-${counts.join('-')}.json',
          ).writeAsStringSync(
            jsonEncode({
              'mode':
                  'Flutter test debug VM + AOT server, 2 actual controllers and rendered detail screens',
              'architecture': mode,
              'runs': runs,
              'complete': runs.length == counts.length,
              'CPU':
                  'GetProcessTimes host includes both worker isolates; excludes PostgreSQL and AOT server',
              'frame': 'pump wall time, not display/raster p95',
            }),
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          ca.dispose();
          cb.dispose();
          await tester.runAsync(() async {
            await a.close();
            await b.close();
            await h.close();
          });
        }
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
