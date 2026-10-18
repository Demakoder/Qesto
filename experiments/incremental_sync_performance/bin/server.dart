import 'dart:convert';
import 'dart:io';
import '../../windows_synthetic_ui_sync/bin/server.dart' as existing;
import 'package:qesto_incremental_sync_experiment/cached_executor.dart';

Future<void> main(List<String> args) {
  final executor = CachedNoteExecutor();
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
