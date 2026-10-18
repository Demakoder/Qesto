/// Opt-in phase evidence for synthetic Stage 4g, never production telemetry.
library;
import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

final class SyntheticTrace {
  static final String? _directory = _target();
  static String? _target() {
    final raw = Platform.environment['QESTO_4G_TRACE_DIR'];
    if (raw == null) return null;
    final dir = Directory(raw).absolute;
    final path = dir.path.replaceAll('\\', '/');
    if (!path.contains('/experiments/owner_lifetime/results/') || !dir.existsSync()) {
      throw StateError('Synthetic trace requires an existing Stage 4g evidence directory');
    }
    return dir.path;
  }
  static bool get enabled => _directory != null;
  static void record(String phase, int micros, {bool failed = false}) {
    if (!enabled) return;
    File('$_directory/trace-$pid-${Isolate.current.hashCode}.jsonl').writeAsStringSync(
      '${jsonEncode({'phase': phase, 'elapsedUs': micros, 'failed': failed,
        'endedUtcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
        'pid': pid, 'isolate': Isolate.current.debugName,
        'rss': ProcessInfo.currentRss, 'peakRss': ProcessInfo.maxRss})}\n',
      mode: FileMode.append,
    );
  }
  static T sync<T>(String phase, T Function() work) {
    if (!enabled) return work();
    final watch = Stopwatch()..start();
    var failed = true;
    try { final result = work(); failed = false; return result; }
    finally { record(phase, watch.elapsedMicroseconds, failed: failed); }
  }
  static Future<T> async<T>(String phase, Future<T> Function() work) async {
    if (!enabled) return work();
    final watch = Stopwatch()..start();
    var failed = true;
    try { final result = await work(); failed = false; return result; }
    finally { record(phase, watch.elapsedMicroseconds, failed: failed); }
  }
}
