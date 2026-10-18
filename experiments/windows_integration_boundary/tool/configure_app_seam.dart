// Add a read-only mapping to actual pure application code. No Flutter SDK or
// production pubspec/dependency changes are needed for the native CLI runner.
import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('.dart_tool/package_config.json');
  final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final packages = config['packages'] as List;
  packages.removeWhere((p) => p['name'] == 'qesto');
  packages.add({
    'name': 'qesto',
    'rootUri': Directory('../../apps/qesto_app').absolute.uri.toString(),
    'packageUri': 'lib/',
    'languageVersion': '3.12',
  });
  file.writeAsStringSync(jsonEncode(config), flush: true);
  print('Mapped actual pure app seam; no production pubspec changes');
}
