import 'dart:io';

Future<void> main() async {
  // Sequential separate Flutter processes. Never run other tests/builds during
  // this sequence. Same freshly built full server in both arms.
  for (final count in ['1000', '10000']) {
    for (final mode in ['full', 'effects']) {
      stdout.writeln('Starting $mode / $count');
      final r = await Process.run(Platform.resolvedExecutable, [
        'tool/flutter_checks.dart',
        'benchmark',
        mode,
        count,
      ]);
      stdout.write(r.stdout);
      stderr.write(r.stderr);
      if (r.exitCode != 0) {
        exitCode = r.exitCode;
        return;
      }
    }
  }
}
