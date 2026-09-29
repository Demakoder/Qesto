import 'dart:io';

import 'package:flutter/services.dart';

import 'recoverable_json_file.dart';

/// Resolves app-private storage without depending on Android's HOME or cwd.
/// Legacy snapshots are copied, never moved/deleted. An existing destination,
/// including an empty snapshot after a wipe, always wins.
Future<File> resolveAndroidStore({
  MethodChannel channel = const MethodChannel('ru.qesto.qesto/storage'),
  String? legacyRoot,
}) async {
  final paths = await channel.invokeMapMethod<String, String>('privatePaths');
  final filesPath = paths?['filesDir'];
  final dataPath = paths?['dataDir'];
  if (filesPath == null || dataPath == null) {
    throw StateError('Android private storage is unavailable');
  }
  final sandbox = await Directory(dataPath).resolveSymbolicLinks();
  final files = await Directory(filesPath).resolveSymbolicLinks();
  if (!_within(files, sandbox)) {
    throw StateError('Android storage is outside the app sandbox');
  }
  final folder = Directory('$files/Qesto');
  await folder.create(recursive: true);
  if (!_within(await folder.resolveSymbolicLinks(), sandbox)) {
    throw StateError('Android storage is outside the app sandbox');
  }
  final destination = File('${folder.path}/store.json');
  await _checkSnapshotPaths(destination, sandbox);
  final store = RecoverableJsonFile(destination);
  if (await store.read() != null) return destination;

  final legacy = File(
    '${legacyRoot ?? Platform.environment['HOME'] ?? Directory.current.path}'
    '/.local/share/Qesto/store.json',
  );
  if (await legacy.exists() || await File('${legacy.path}.backup').exists()) {
    // A legacy file outside the sandbox must not silently become a fresh profile.
    await _checkSnapshotPaths(legacy, sandbox);
    final snapshot = await RecoverableJsonFile(legacy).read();
    if (snapshot != null) {
      await store.update((current) => current ?? snapshot);
    }
  }
  return destination;
}

bool _within(String path, String root) =>
    path == root || path.startsWith('$root${Platform.pathSeparator}');

Future<void> _checkSnapshotPaths(File file, String sandbox) async {
  final parent = await file.parent.resolveSymbolicLinks();
  if (!_within(parent, sandbox)) {
    throw StateError('Financial snapshot is outside the app sandbox');
  }
  for (final suffix in ['', '.backup', '.lock', '.temporary', '.backup.next']) {
    final candidate = File('${file.path}$suffix');
    if (await FileSystemEntity.type(candidate.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Financial snapshot cannot be a symbolic link');
    }
  }
}
