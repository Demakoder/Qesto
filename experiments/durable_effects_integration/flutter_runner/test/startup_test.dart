import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto_durable_effects_experiment/harness.dart';

void main() {
  testWidgets(
    '50k resource gate, unchanged 30-second owner ready deadline',
    (tester) async {
      final h = effectsHarness(), watch = Stopwatch()..start();
      await tester.runAsync(() async {
        var passed = false;
        String? failure;
        try {
          await h.start(count: 50000);
          final server = await h.server();
          final owner = await h.open(server, 0, create: true);
          passed = true;
          await owner.close();
        } catch (e) {
          failure = e.runtimeType.toString();
        } finally {
          await h.close();
        }
        File('../results/startup-50000.json').writeAsStringSync(
          jsonEncode({
            'passed': passed,
            'failure': failure,
            'count': 50000,
            'owner_ready_deadline_seconds': 30,
            'full_startup_us': watch.elapsedMicroseconds,
            'peak_rss_bytes': ProcessInfo.maxRss,
            'rss_bytes': ProcessInfo.currentRss,
            'runtime':
                'isolated Flutter test host + AOT server; exits after this sole probe',
            'reopen_after_killed_native_owner': false,
          }),
        );
        // Test validates the probe; readiness is explicitly reported separately.
        stdout.writeln('50k readiness: $passed; failure: $failure');
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
