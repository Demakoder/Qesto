import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

Iterable<File> sources(Directory dir) sync* {
  for (final entry in dir.listSync(followLinks: false)) {
    final name = entry.path.replaceAll('\\', '/').split('/').last;
    if (entry is Directory) {
      if (name.startsWith('.') ||
          ['build', 'owner_lifetime'].contains(name))
        continue;
      yield* sources(entry);
    } else if (entry is File) {
      yield entry;
    }
  }
}

void main(List<String> args) {
  final root = Directory('../..').absolute;
  final hashes = <String, String>{};
  for (final path in [
    'apps/qesto_app/lib',
    'apps/qesto_app/test',
    'packages/qesto_synoball_core/lib',
    'packages/qesto_synoball_core/test',
    'experiments',
  ]) {
    for (final f in sources(Directory('${root.path}/$path'))) {
      final p = f.path.substring(root.path.length + 1).replaceAll('\\', '/');
      if (p.contains('/.runtime/') ||
          p.contains('/.dart_tool/') ||
          p.contains('/build/') ||
          p.contains('/owner_lifetime/') ||
          !(p.endsWith('.dart') ||
              p.contains('/goldens/') ||
              p.contains('/results/') || p.endsWith('.md') ||
              p.endsWith('pubspec.yaml') || p.endsWith('pubspec.lock')))
        continue;
      hashes[p] = sha256.convert(f.readAsBytesSync()).toString();
    }
  }
  Directory('results').createSync(recursive: true);
  final baseline = File('results/source_baseline.json');
  if (args.contains('--verify')) {
    final old = jsonDecode(baseline.readAsStringSync()) as Map;
    final changes = [
      for (final p in old.keys)
        if (hashes[p] != old[p]) p,
    ];
    File('results/source_verification.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'changed': changes,
        'checked': old.length,
        'newOutsideExperiment': [
          for (final p in hashes.keys)
            if (!old.containsKey(p)) p,
        ],
      }),
    );
    print('Changed from Stage 4g baseline: $changes');
  } else {
    if (baseline.existsSync()) throw StateError('Do not overwrite baseline');
    baseline.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(hashes),
    );
    print('Captured ${hashes.length} source/golden/result hashes');
  }
}
