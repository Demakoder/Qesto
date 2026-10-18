import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final root = Directory.current.parent.parent;
  final baseline = File('results/source_baseline.json');
  final hashes = <String, String>{};
  for (final path in [
    'apps/qesto_app/lib',
    'apps/qesto_app/test',
    'packages/qesto_synoball_core/lib',
    'packages/qesto_synoball_core/test',
  ]) {
    for (final f in Directory('${root.path}/$path').listSync(recursive: true)) {
      if (f is File)
        hashes[f.path.substring(root.path.length + 1).replaceAll('\\', '/')] =
            sha256.convert(f.readAsBytesSync()).toString();
    }
  }
  if (args.single == 'baseline') {
    if (baseline.existsSync()) throw StateError('Baseline already exists');
    baseline.writeAsStringSync(jsonEncode(hashes), flush: true);
    print('Captured ${hashes.length} source hashes');
  } else {
    final old = jsonDecode(baseline.readAsStringSync()) as Map;
    final changed = {
      ...old.keys,
      ...hashes.keys,
    }.where((k) => old[k] != hashes[k]).toList();
    final result = {
      'checked': hashes.length,
      'changed': changed,
      'passed': changed.isEmpty,
    };
    File('results/source_check.json').writeAsStringSync(jsonEncode(result));
    print(jsonEncode(result));
    if (changed.isNotEmpty) exitCode = 1;
  }
}
