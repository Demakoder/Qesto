import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:test/test.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_incremental_sync_experiment/measure.dart';

void echo(SendPort ready) {
  final port = ReceivePort();
  ready.send(port.sendPort);
  port.listen((value) {
    if (value == null) {
      port.close();
      return;
    }
    ready.send(value);
  });
}

void main() {
  test(
    'isolate handoff cost for actual committed-state envelope, no financial work',
    () async {
      final port = ReceivePort(), stream = StreamIterator<Object?>(port);
      final worker = await Isolate.spawn(echo, port.sendPort);
      await stream.moveNext();
      final target = stream.current as SendPort;
      final runs = <Object>[];
      try {
        for (final n in [1000, 10000, 50000]) {
          final data = syntheticFixture(
            count: n,
            fixturePath:
                '../storage_feasibility/test/fixtures/container_profile_v7.json',
          );
          final payload = CommittedTransactionNote(
            commandId: 'handoff',
            revision: 1,
            data: data,
            preparedCore: SynoballCore(
              initialState: data.synoballState!,
              categoryPolicy: data.classification.policy,
            ),
          );
          final samples = <Object>[];
          for (var i = 0; i < 3; i++) {
            final cpu = cpuMicros(), watch = Stopwatch()..start();
            target.send(payload);
            expect(await stream.moveNext(), isTrue);
            final returned = stream.current as CommittedTransactionNote;
            samples.add({
              'roundtrip_us': watch.elapsedMicroseconds,
              'cpu_us': cpuMicros() - cpu,
            });
            expect(returned.data.synoballState!.transactions.length, n);
          }
          runs.add({
            'count': n,
            'samples': samples,
            'logical_codec_bytes': utf8
                .encode(const UserFinancialDataCodec().encode(data))
                .length,
            'rss_bytes': ProcessInfo.currentRss,
          });
        }
        File('results/isolate-handoff.json').writeAsStringSync(
          jsonEncode({
            'runs': runs,
            'metric':
                'two-way same envelope SendPort copy + scheduling; not one-way or allocator wire bytes',
            'mode': 'Dart JIT',
          }),
        );
      } finally {
        target.send(null);
        await stream.cancel();
        port.close();
        worker.kill();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
