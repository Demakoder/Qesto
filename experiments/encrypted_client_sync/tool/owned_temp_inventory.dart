// Read-only inventory. Only containers whose encrypted manifest names a
// workspace created by THIS experiment's retained harness configs are listed.
import 'dart:convert';
import 'dart:io';
import 'package:qesto_storage_spike/windows_key_probe.dart';

void main() {
  final workspaces = <String>{};
  for (final file in Directory(
    '.runtime',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('config.json')) continue;
    final config = jsonDecode(file.readAsStringSync()) as Map;
    for (final p in config['principals'] as List) {
      if ((p['workspace'] as String).startsWith('enc3b-'))
        workspaces.add(p['workspace'] as String);
    }
  }
  final result = <Object>[];
  final temp = Directory.systemTemp.resolveSymbolicLinksSync();
  for (final directory in Directory(
    temp,
  ).listSync(followLinks: false).whereType<Directory>()) {
    if (!directory.path
        .split(Platform.pathSeparator)
        .last
        .startsWith('qesto-storage-spike-'))
      continue;
    if (!File('${directory.path}/.qesto-storage-spike').existsSync()) continue;
    try {
      final manifest =
          jsonDecode(
                utf8.decode(
                  WindowsKeyProbe.unprotect(
                    File(
                      '${directory.path}/container-vault.bin',
                    ).readAsBytesSync(),
                  ),
                ),
              )
              as Map;
      final migration = jsonDecode(manifest['migration'] as String) as Map;
      final partition = jsonDecode(migration['partition'] as String) as Map;
      if (!(migration['id'] as String).startsWith('synthetic-3b-') ||
          !workspaces.contains(partition['workspace']))
        continue;
      if (directory.resolveSymbolicLinksSync() != directory.absolute.path)
        continue;
      final lock = File(
        '${directory.path}/container.lock',
      ).openSync(mode: FileMode.append);
      try {
        lock.lockSync(FileLock.exclusive);
        lock.unlockSync();
      } finally {
        lock.closeSync();
      }
      final bytes = directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .fold<int>(0, (n, f) => n + f.lengthSync());
      result.add({'path': directory.absolute.path, 'bytes': bytes});
    } catch (_) {
      /* corrupt, busy or unrelated folders are never cleanup targets */
    }
  }
  print(jsonEncode(result));
}
