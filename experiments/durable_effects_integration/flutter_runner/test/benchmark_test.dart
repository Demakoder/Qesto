import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_durable_effects_experiment/harness.dart';
import 'package:qesto_durable_effects_experiment/windows_driver.dart';
import 'package:qesto_storage_spike/wal_policy.dart';
import '../../../incremental_sync_performance/lib/measure.dart';
import '../../../windows_synthetic_ui_sync/flutter_runner/test/benchmark_test.dart'
    show heartbeat, Measured;
import '../../../windows_synthetic_ui_sync/flutter_runner/test/two_ui_hosts_test.dart'
    show NoteHost;

Future<Map<String, Object?>> heaps() async {
  final info = await developer.Service.getInfo(), uri = info.serverUri;
  if (uri == null || !(uri.host == '127.0.0.1' || uri.host == 'localhost'))
    return {'available': false, 'reason': 'VM service unavailable'};
  return Isolate.run(() => readHeaps(uri));
}

Future<Map<String, Object?>> readHeaps(Uri uri) async {
  final client = HttpClient();
  try {
    Future<Map<String, dynamic>> get(
      String method, [
      Map<String, String>? query,
    ]) async {
      final r = await client.getUrl(
        uri.resolve(method).replace(queryParameters: query),
      );
      return jsonDecode(await (await r.close()).transform(utf8.decoder).join())
          as Map<String, dynamic>;
    }

    final vm = (await get('getVM'))['result'] as Map;
    final values = <Object>[];
    for (final isolate in vm['isolates'] as List) {
      final result =
          (await get('getIsolate', {
                'isolateId': isolate['id'] as String,
              }))['result']
              as Map;
      values.add({'name': result['name'], 'heaps': result['_heaps']});
    }
    return {'available': true, 'isolates': values};
  } catch (e) {
    return {'available': false, 'reason': e.runtimeType.toString()};
  } finally {
    client.close(force: true);
  }
}

void main() {
  final mode = Platform.environment['QESTO_4F_MODE'] ?? 'effects';
  final count = int.parse(Platform.environment['QESTO_4F_COUNT'] ?? '1000');
  final effects = mode == 'effects';
  testWidgets(
    'matched $mode $count: two rendered hosts, native encryption, full financial server',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = effectsHarness(effects: effects),
          opened = <TransactionNoteBoundary>[];
      late dynamic wa, wb, server;
      late TransactionNoteBoundary a, b;
      late BudgetController ca, cb;
      var ready = false;
      final startup = Stopwatch()..start();
      await tester.runAsync(() async {
        try {
          await h.start(count: count);
          server = await h.server();
          wa = await h.open(server, 0, create: true);
          a = effects ? EffectsNoteBoundary(wa) : Measured(wa);
          opened.add(a);
          wb = await h.open(server, 1, create: true);
          b = effects ? EffectsNoteBoundary(wb) : Measured(wb);
          opened.add(b);
          final initial = (await wa.load()).data;
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
            for (final o in opened) {
              await o.close();
            }
            await h.close();
          }
        }
      });
      if (!ready) return;
      final startupUs = startup.elapsedMicroseconds;
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
        for (var trial = 0; trial < 3; trial++) {
          late Map<String, Object> local, send, receive;
          late SynchronizedTransactionNotes sent, received;
          late Map<String, dynamic> da, db;
          late int cpu, publication, handoff, localPayload;
          late Map<String, Object?> heap;
          Map<String, int>? phases;
          await tester.runAsync(() async {
            final cpuStart = cpuMicros();
            local = await heartbeat(
              () => ca.setTransactionNote(
                'container-tx-${[0, 1, 3][trial]}',
                'Synthetic measured $trial',
                commandId: 'bench-$trial',
              ),
            );
            publication = ca.lastNotePublicationMicros;
            handoff = wa.lastReplyHandoffMicros as int;
            if (effects) {
              final delta = a as EffectsNoteBoundary;
              phases = delta.lastTimings;
              localPayload = delta.lastDeltaBytes;
              expect(ca.lastNotePublicationWasDelta, isTrue);
              expect(delta.fullReloads, 0);
            } else {
              final full = (a as Measured).note!;
              phases = {
                'preparation': full.preparationMicros,
                'commit': full.commitMicros,
              };
              localPayload = utf8
                  .encode(const UserFinancialDataCodec().encode(full.data))
                  .length;
            }
            send = await heartbeat(() async {
              sent = await ca.syncTransactionNotes();
            });
            receive = await heartbeat(() async {
              received = await cb.syncTransactionNotes();
            });
            cpu = cpuMicros() - cpuStart;
            da = await wa.inspectForTest() as Map<String, dynamic>;
            db = await wb.inspectForTest() as Map<String, dynamic>;
            heap = await heaps().timeout(
              const Duration(seconds: 10),
              onTimeout: () => {'available': false, 'reason': 'timeout'},
            );
            // Full oracle OUTSIDE measured intervals, no weakened equality.
            final xa = const UserFinancialDataCodec().encode(
              ca.mergeInto((await wa.load()).data),
            );
            final xb = const UserFinancialDataCodec().encode(
              cb.mergeInto((await wb.load()).data),
            );
            expect(jsonDecode(xa), jsonDecode(xb));
            expect(jsonDecode(xa), (await h.serverState())['state']);
            expect(await wb.pending(), isEmpty);
          });
          final frame = Stopwatch()..start();
          await tester.pump();
          final frameUs = frame.elapsedMicroseconds;
          expect(tester.takeException(), isNull);
          final metrics = File('${server.control.path}.metrics.json');
          samples.add({
            'trial': trial + 1,
            'local': local,
            'sender': send,
            'receiver': receive,
            'host_cpu_us': cpu,
            'local_phases_us': phases,
            'delta_publication_us': publication,
            'send_receive_handoff_us': handoff,
            'local_payload_json_equivalent_bytes': localPayload,
            'outbound_worker_us': sent.timingsMicros,
            'incoming_worker_us': received.timingsMicros,
            'receiver_publication_us': cb.lastNotePublicationMicros,
            'two_widgets_pump_us': frameUs,
            'rss_bytes': ProcessInfo.currentRss,
            'peak_rss_bytes': ProcessInfo.maxRss,
            'heap': heap,
            'files_a': sizes('${h.profiles[0].directory}/container-1.db'),
            'files_b': sizes('${h.profiles[1].directory}/container-1.db'),
            'storage_a': da['storage_metrics'],
            'storage_b': db['storage_metrics'],
            'http_a': da['transport_metrics'],
            'http_b': db['transport_metrics'],
            'server': metrics.existsSync()
                ? jsonDecode(metrics.readAsStringSync())
                : null,
            'full_v7_parity': true,
          });
          File('../results/benchmark-$mode-$count.json').writeAsStringSync(
            jsonEncode({
              'mode': mode,
              'count': count,
              'runtime':
                  'Flutter test debug VM + same AOT full server, two rendered Qesto details/controllers',
              'startup_us': startupUs,
              'samples': samples,
              'complete': samples.length == 3,
              'caveats': [
                'CPU covers host and worker isolates, excludes PostgreSQL/AOT server',
                'Handoff includes serialization/queue/scheduling; wall-clock timestamp',
                'Payload is JSON-equivalent; full response also contains preparedCore not included in byte estimate',
                'RSS peak covers full parity checks too; not release app or raster frame metrics',
              ],
            }),
          );
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        ca.dispose();
        cb.dispose();
        await tester.runAsync(() async {
          for (final o in opened) {
            await o.close(cancelPending: true);
          }
          await h.close();
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
