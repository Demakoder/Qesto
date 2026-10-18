import 'dart:convert';
import 'dart:io';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';
import '../../incremental_sync_performance/lib/measure.dart';
import '../../windows_synthetic_ui_sync/bin/server.dart' as existing;

/// Instrumentation only: exactly the previous full executor, no cache/rule change.
class MeasuredFullExecutor extends QestoNoteExecutor {
  final measurements = Measurements();
  final observations = <String, List<Map<String, int>>>{};
  @override
  T phase<T>(String name, T Function() work, {int bytes = 0}) =>
      measurements.run(name, work, bytes: bytes);
  @override
  void observe(String phase, int micros, {int bytes = 0, int entities = 0}) =>
      observations.putIfAbsent(phase, () => []).add({
        'wall_us': micros,
        'bytes': bytes,
        'entities': entities,
      });
}

Future<void> main(List<String> args) {
  final executor = MeasuredFullExecutor();
  return existing.run(
    args,
    executor: executor,
    afterCommit: () {
      File('${args[1]}.metrics.json').writeAsStringSync(
        jsonEncode({
          'phases': executor.measurements.values,
          'server': executor.observations,
          'rss_bytes': ProcessInfo.currentRss,
          'peak_rss_bytes': ProcessInfo.maxRss,
        }),
      );
    },
  );
}
