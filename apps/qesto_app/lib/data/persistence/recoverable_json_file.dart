import 'dart:convert';
import 'dart:io';

/// A small recoverable snapshot protocol. The backup is retained after commit;
/// recovery never removes the only validated copy before replacing the primary.
class RecoverableJsonFile {
  RecoverableJsonFile(this.file, {this.checkpoint});

  final File file;
  final Future<void> Function(String step)? checkpoint;
  static final Map<String, Future<void>> _queues = {};

  Future<Map<String, dynamic>?> read() => _locked(_read);

  Future<void> write(Map<String, dynamic> value) => update((_) => value);

  Future<void> update(
    Map<String, dynamic> Function(Map<String, dynamic>? current) transform, {
    bool retainPrevious = true,
  }) => _locked(() async {
    final current = await _read();
    final next = transform(current);
    final temporary = File('${file.path}.temporary');
    final backup = File('${file.path}.backup');
    await temporary.writeAsString(jsonEncode(next), flush: true);
    await checkpoint?.call('staged');
    if (current != null) {
      // Write the validated recovered value, never a corrupt primary.
      final backupNext = File('${file.path}.backup.next');
      await backupNext.writeAsString(
        jsonEncode(retainPrevious ? current : next),
        flush: true,
      );
      await checkpoint?.call('backup_staged');
      await backupNext.rename(backup.path);
      await checkpoint?.call('backup_committed');
    }
    await temporary.rename(file.path);
    await checkpoint?.call('committed');
  });

  Future<Map<String, dynamic>?> _read() async {
    Object? error;
    for (final candidate in [file, File('${file.path}.backup')]) {
      if (!await candidate.exists()) continue;
      try {
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid storage root');
        }
        return decoded;
      } on Object catch (failure) {
        error = failure;
      }
    }
    if (error != null) {
      throw const FormatException(
        'No valid financial snapshot; recovery required',
      );
    }
    return null;
  }

  Future<T> _locked<T>(Future<T> Function() operation) {
    final path = file.absolute.path;
    final previous = _queues[path] ?? Future<void>.value();
    final result = () async {
      await previous;
      await file.parent.create(recursive: true);
      final lock = await File('$path.lock').open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.blockingExclusive);
        return await operation();
      } finally {
        await lock.close();
      }
    }();
    _queues[path] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
