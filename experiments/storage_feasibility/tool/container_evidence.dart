// Repository sources only. Never reads installed profiles or vaults.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final root = Directory.current.parent.parent;
  final file = File('results/container_baseline.json');
  final files = <String, String>{};
  for (final path in [
    'apps/qesto_app/lib',
    'apps/qesto_app/test',
    'packages/qesto_synoball_core/lib',
    'packages/qesto_synoball_core/test',
  ]) {
    for (final entity in Directory(
      '${root.path}/$path',
    ).listSync(recursive: true)) {
      if (entity is File) {
        files[entity.path
            .substring(root.path.length + 1)
            .replaceAll('\\', '/')] = sha256
            .convert(entity.readAsBytesSync())
            .toString();
      }
    }
  }
  if (args.single == 'baseline') {
    if (file.existsSync()) throw StateError('Do not replace baseline');
    file.writeAsStringSync(jsonEncode({'files': files}), flush: true);
    print('Captured ${files.length} repository source hashes');
  } else {
    final old = (jsonDecode(file.readAsStringSync()) as Map)['files'] as Map;
    final changes = {
      ...old,
      ...files,
    }.keys.where((k) => old[k] != files[k]).toList();
    final result = {
      'checked': files.length,
      'changes': changes,
      'passed': changes.isEmpty,
    };
    File(
      'results/container_source_check.json',
    ).writeAsStringSync(jsonEncode(result));
    print(jsonEncode(result));
    if (changes.isNotEmpty) exitCode = 1;
  }
}
