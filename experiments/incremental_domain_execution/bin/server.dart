import 'dart:convert';
import 'dart:io';
import '../../windows_synthetic_ui_sync/bin/server.dart' as existing;
import '../lib/bounded_executor.dart';

Future<void> main(List<String> args) {
  final executor = BoundedNoteExecutor();
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
          'cache_estimate_bytes': executor.retainedEstimate,
          'cache_hits': executor.hits,
          'cache_misses': executor.misses,
          'cache_rejected': executor.rejected,
        }),
      );
    },
  );
}
