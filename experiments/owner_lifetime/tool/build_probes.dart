import 'dart:io';

Future<void> main() async {
  for (final name in ['receipt_probe', 'native_effects_probe', 'client_probe']) {
    final result = await Process.run(Platform.resolvedExecutable,
      ['build', 'cli', '-t', 'bin/$name.dart', '-o', 'build/$name']);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) throw StateError('$name build failed');
  }
}
