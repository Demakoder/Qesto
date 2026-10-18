import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final run = args.isEmpty ? 'baseline' : args[0];
  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(run)) throw ArgumentError('run');
  final counts = args.length > 1 ? [args[1]] : ['1000', '10000'];
  final modes = args.length > 2 ? [args[2]] : ['full', 'effects'];
  final suite = args.length > 3 ? args[3] : 'benchmark';
  Directory('results/$run').createSync(recursive: true);
  final traceDirectory = Directory('results/$run/trace-$suite');
  if (run.startsWith('phases-')) traceDirectory.createSync(recursive: true);
  final flutter = '${File(Platform.resolvedExecutable).parent.parent.parent.path}/flutter_tools.snapshot';
  for (final count in counts) {
    for (final mode in modes) {
      final prefix = 'results/$run/$suite-$mode-$count';
      if (File('$prefix.jsonl').existsSync() || File('$prefix.json').existsSync()) {
        throw StateError('Evidence already exists: $prefix');
      }
      stdout.writeln('Starting $run $mode / $count');
      final result = await Process.run(Platform.resolvedExecutable, [
        flutter, 'test', 'test/${suite}_test.dart', '--enable-vmservice',
        '--no-pub', '--concurrency=1', '--reporter=json',
      ], workingDirectory: 'flutter_runner', environment: {
        'QESTO_4G_MODE': mode, 'QESTO_4G_COUNT': count, 'QESTO_4G_RUN': run,
        if (run.startsWith('phases-')) 'QESTO_4G_TRACE_DIR': traceDirectory.absolute.path,
      });
      File('$prefix.jsonl').writeAsStringSync(result.stdout as String);
      File('$prefix.stderr.txt').writeAsStringSync(result.stderr as String);
      final events = (result.stdout as String).split('\n')
          .where((s) => s.startsWith('{')).map(jsonDecode).toList();
      stdout.writeln(jsonEncode({
        'run': run, 'mode': mode, 'count': count, 'exit': result.exitCode,
        'errors': events.where((e) => e['type'] == 'error').map((e) => e['error']).toList(),
        'done': events.where((e) => e['type'] == 'done').toList(),
      }));
      if (result.exitCode != 0) { exitCode = result.exitCode; return; }
    }
  }
}
