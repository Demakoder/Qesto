import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

Iterable<File> files(Directory directory) sync* {
  for (final entry in directory.listSync(followLinks: false)) {
    final name = entry.path.replaceAll('\\', '/').split('/').last;
    if (entry is Directory) {
      if (name.startsWith('.') || name == 'build') continue;
      yield* files(entry);
    } else if (entry is File && name != 'artifact_manifest.json') {
      yield entry;
    }
  }
}

void main() {
  final result = <String, Object>{};
  for (final file in files(Directory('.'))) {
    final name = file.path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^\./'), '');
    result[name] = {
      'bytes': file.lengthSync(),
      'sha256': sha256.convert(file.readAsBytesSync()).toString(),
    };
  }
  File(
    'results/artifact_manifest.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln(
    'Indexed ${result.length} synthetic source/evidence artifacts; no build/runtime/vault files.',
  );
}
