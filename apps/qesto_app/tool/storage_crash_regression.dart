// Run with dart tool/storage_crash_regression.dart. Uses only synthetic data.
import 'dart:io';

import 'package:qesto/data/persistence/recoverable_json_file.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == '--child') {
    final file = File(args[1]);
    final stage = args[2];
    final wipe = args[3] == 'wipe';
    await RecoverableJsonFile(
      file,
      checkpoint: (step) async {
        if (step == stage) exit(91); // No Dart finally/cleanup runs.
      },
    ).update((_) => wipe ? {} : {'generation': 3}, retainPrevious: !wipe);
    exit(0);
  }

  var passed = 0;
  for (final wipe in [false, true]) {
    for (final stage in [
      'staged',
      'backup_staged',
      'backup_committed',
      'committed',
    ]) {
      final temp = await Directory.systemTemp.createTemp('qesto-crash-test-');
      try {
        final file = File('${temp.path}/store.json');
        final store = RecoverableJsonFile(file);
        await store.write({'generation': 1});
        await store.write({'generation': 2});
        final child = await Process.run(Platform.resolvedExecutable, [
          Platform.script.toFilePath(),
          '--child',
          file.path,
          stage,
          wipe ? 'wipe' : 'write',
        ]);
        if (child.exitCode != 91) {
          throw StateError(
            'Worker did not reach the injected crash: ${child.stderr}',
          );
        }
        final recovered = await store.read();
        final expected = stage == 'committed' ? (wipe ? null : 3) : 2;
        if (recovered == null ||
            recovered['generation'] != expected ||
            (wipe && stage == 'committed' && recovered.isNotEmpty)) {
          throw StateError('Unexpected recovery at $stage (wipe=$wipe)');
        }
        if (wipe && stage == 'committed') {
          await file.writeAsString('{synthetic corruption');
          if ((await store.read())?.isEmpty != true) {
            throw StateError('A completed wipe resurrected deleted data');
          }
        }
        await store.write({
          'generation': 4,
        }); // OS lock released on process exit.
        if ((await store.read())?['generation'] != 4) {
          throw StateError('Storage cannot resume after a crashed process');
        }
        passed++;
      } finally {
        await temp.delete(recursive: true);
      }
    }
  }
  stdout.writeln('$passed subprocess crash/recovery cases passed.');
}
