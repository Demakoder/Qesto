/// Synthetic Windows recovery experiment. NOT the production secure-storage vault.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'storage_spike.dart';
import 'windows_key_probe.dart';

class RecoveryRequired implements Exception {
  RecoveryRequired(this.reason);
  final String reason;
}

class GenerationVault {
  GenerationVault(this.directory) {
    requireOwnedPath('$directory/control.bin');
  }
  final String directory;
  String get control => '$directory/control.bin';
  String get recovery => '$directory/recovery.bin';
  String database(int generation) => '$directory/generation-$generation.db';

  /// Flush a same-directory temporary file, then native rename/replace. No
  /// deletion of the last known good file, even when serialization fails.
  static void atomicReplace(String target, List<int> data) {
    requireOwnedPath(target);
    final temporary = '$target.next';
    File(temporary).writeAsBytesSync(data, flush: true);
    final from = temporary.toNativeUtf16(), to = target.toNativeUtf16();
    try {
      final ok = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
            int Function(Pointer<Utf16>, Pointer<Utf16>, int)
          >('MoveFileExW')(from, to, 9);
      if (ok == 0) throw RecoveryRequired('manifest replacement failed');
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
  }

  Map<String, dynamic> read({bool backup = false}) {
    final file = File(backup ? recovery : control);
    if (!file.existsSync())
      throw RecoveryRequired('vault missing; never provision over database');
    try {
      final decoded = jsonDecode(
        utf8.decode(WindowsKeyProbe.unprotect(file.readAsBytesSync())),
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'qesto.synthetic.generations.v1' ||
          decoded['active'] is! int ||
          decoded['generations'] is! Map) {
        throw const FormatException('vault format');
      }
      final active = decoded['active'] as int;
      if (active < 1 ||
          !(decoded['generations'] as Map).containsKey('$active')) {
        throw const FormatException('active generation');
      }
      for (final entry in (decoded['generations'] as Map).entries) {
        if (int.tryParse(entry.key as String) == null ||
            entry.value is! Map ||
            base64Decode(entry.value['key'] as String).length != 32 ||
            entry.value['minimumRevision'] is! int)
          throw const FormatException('key descriptor');
      }
      return decoded;
    } catch (_) {
      throw RecoveryRequired('vault corrupt/unreadable; bytes retained');
    }
  }

  void _publish(Map<String, dynamic> state, {bool initial = false}) {
    final encrypted = WindowsKeyProbe.protect(utf8.encode(jsonEncode(state)));
    if (!initial) {
      read(); // Validate before replacing the recovery copy. Never archive corruption.
      atomicReplace(recovery, File(control).readAsBytesSync());
    }
    atomicReplace(control, encrypted);
  }

  Future<SpikeStore> _open(Map<String, dynamic> state) async {
    final generation = state['active'] as int;
    final descriptor = (state['generations'] as Map)['$generation'] as Map;
    final path = database(generation);
    if (!File(path).existsSync())
      throw RecoveryRequired('active database missing');
    final store = await SpikeStore.open(
      path,
      Candidate.directMc,
      base64Decode(descriptor['key'] as String),
    );
    try {
      await store.verify();
      final revision = await store.revision();
      if (revision < (descriptor['minimumRevision'] as int))
        throw RecoveryRequired('rollback or incomplete database');
      if (revision == descriptor['minimumRevision'] &&
          descriptor['digest'] != null &&
          sha256.convert(utf8.encode((await store.snapshot())!)).toString() !=
              descriptor['digest']) {
        throw RecoveryRequired('generation digest mismatch');
      }
      return store;
    } catch (_) {
      await store.close();
      rethrow;
    }
  }

  Future<SpikeStore> open() => _open(read());

  Future<void> provision(String snapshot) async {
    if (Directory(directory).listSync().any(
      (f) =>
          f.path.endsWith('.db') ||
          f.path.endsWith('.bin') ||
          f.path.endsWith('.next'),
    )) {
      throw RecoveryRequired(
        'existing artifacts require recovery, not empty provisioning',
      );
    }
    final key = randomKey();
    // Save key before DB creation. Interrupted provisioning is recoverable but
    // never automatically interpreted as an empty financial profile.
    final descriptor = {
      'key': base64Encode(key),
      'minimumRevision': 1,
      'digest': sha256.convert(utf8.encode(snapshot)).toString(),
    };
    _publish({
      'format': 'qesto.synthetic.generations.v1',
      'active': 1,
      'generations': {'1': descriptor},
    }, initial: true);
    final store = await SpikeStore.open(database(1), Candidate.directMc, key);
    try {
      await store.apply(id: 'seed', expected: 0, snapshot: snapshot);
    } finally {
      await store.close();
    }
  }

  /// Caller must have stopped/drained the sole writer and released readers.
  /// Shadow-copy rotation avoids assuming in-place PRAGMA rekey is crash atomic.
  Future<void> rotate({void Function(String)? fault}) async {
    final state = read(), source = await open();
    try {
      final generations = state['generations'] as Map;
      if (generations.length != 1) {
        throw RecoveryRequired(
          'Previous generation requires explicit recovery/retirement before another rotation',
        );
      }
      final next =
          generations.keys
              .map((s) => int.parse(s as String))
              .reduce((a, b) => a > b ? a : b) +
          1;
      final path = database(next);
      if (File(path).existsSync())
        throw RecoveryRequired('orphan generation requires inspection');
      final key = randomKey(), revision = await source.revision();
      final digest = sha256
          .convert(utf8.encode((await source.snapshot())!))
          .toString();
      generations['$next'] = {
        'key': base64Encode(key),
        'minimumRevision': revision,
        'digest': digest,
      };
      fault?.call('before-dual-key');
      _publish(
        state,
      ); // old generation is still authoritative; both keys durable.
      fault?.call('after-dual-key');
      final target = openNative(path, Candidate.directMc, key);
      try {
        await for (final _ in source.raw.backup(target, nPage: 8)) {
          fault?.call('during-copy');
        }
      } finally {
        target.close();
      }
      final candidate = Map<String, dynamic>.from(state)..['active'] = next;
      final verified = await _open(candidate);
      try {
        if (await verified.revision() != revision ||
            await source.revision() != revision) {
          throw RecoveryRequired(
            'writer changed during rotation; do not promote',
          );
        }
      } finally {
        await verified.close();
      }
      fault?.call('after-verified-copy');
      // Old DB and both key generations remain available for explicit recovery.
      _publish(candidate);
      fault?.call('after-manifest-promotion');
    } finally {
      await source.close();
    }
  }

  /// Explicit operator action. Returns recovery point, not a claim of latest data.
  /// Never automatically called when normal open fails.
  Future<int> recoverFromBackup() async {
    final state = read(backup: true), verified = await _open(state);
    final revision = await verified.revision();
    await verified.close();
    atomicReplace(control, File(recovery).readAsBytesSync());
    return revision;
  }
}
