/// Experiment-only bounded single-writer policy. All sizes are bytes.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'storage_spike.dart';

const mib = 1024 * 1024;

class StoragePressure implements Exception {
  StoragePressure(this.reason);
  final String reason;
}

int fileBytes(String path) =>
    File(path).existsSync() ? File(path).lengthSync() : 0;
Map<String, int> sizes(String path) => {
  'db': fileBytes(path),
  'wal': fileBytes('$path-wal'),
  'shm': fileBytes('$path-shm'),
};

int availableDiskBytes(String path) {
  final directory = File(path).absolute.parent.path.toNativeUtf16();
  final available = calloc<Uint64>();
  final total = calloc<Uint64>();
  final free = calloc<Uint64>();
  try {
    final ok = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          ),
          int Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >('GetDiskFreeSpaceExW')(directory, available, total, free);
    if (ok == 0) throw StateError('Disk capacity unknown; fail closed');
    return available.value;
  } finally {
    calloc.free(directory);
    calloc.free(available);
    calloc.free(total);
    calloc.free(free);
  }
}

class WalPolicy {
  WalPolicy(
    this.store, {
    this.softBytes = 32 * mib,
    this.hardBytes = 256 * mib,
    this.diskFloor = 256 * mib,
    int Function()? available,
  }) : available = available ?? (() => availableDiskBytes(store.path)) {
    store.raw.execute('PRAGMA wal_autocheckpoint = 1000');
    store.raw.execute('PRAGMA busy_timeout = 100');
    // This limits retained WAL after a successful reset, not growth under a reader.
    store.raw.execute('PRAGMA journal_size_limit = ${8 * mib}');
  }
  final CheckpointStore store;
  final int softBytes, hardBytes, diskFloor;
  final int Function() available;
  final List<Map<String, Object?>> maintenance = [];
  bool poisoned = false;
  int get walBytes => fileBytes('${store.path}-wal');

  Future<CheckpointResult> maintain({bool idle = false}) async {
    final CheckpointResult cp;
    try {
      cp = await store.checkpoint(mode: idle ? 'TRUNCATE' : 'PASSIVE');
    } catch (_) {
      // Includes preflight maintenance, before apply enters its transaction.
      poisoned = true;
      rethrow;
    }
    maintenance.add({
      'mode': idle ? 'TRUNCATE' : 'PASSIVE',
      ...cp.toJson(),
      'walBytes': walBytes,
    });
    return cp;
  }

  Future<int> apply(
    String id,
    int expected,
    String snapshot, {
    void Function(Fault)? fault,
  }) => write(
    payloadBytes: utf8.encode(snapshot).length,
    commit: () => (store as SpikeStore).apply(
      id: id,
      expected: expected,
      snapshot: snapshot,
      fault: fault,
    ),
  );

  /// Shared storage-only envelope; the container supplies its own transaction.
  /// No financial semantics or schema assumptions beyond the measured budget.
  Future<T> write<T>({
    required int payloadBytes,
    required Future<T> Function() commit,
    bool Function(Object)? expectedRejection,
  }) async {
    if (poisoned) throw StateError('Reopen required after write error');
    // Conservative envelope for this prototype schema. Not a generic SQLite
    // upper bound: validate observed write amplification before production.
    final projected = payloadBytes * 3 + 2 * mib;
    final oldDb = fileBytes(store.path);
    if (available() < diskFloor + projected + min(oldDb, projected)) {
      throw StoragePressure('disk-headroom');
    }
    if (walBytes > softBytes || walBytes + projected > hardBytes) {
      await maintain(idle: true); // BUSY is returned, never assumed successful.
    }
    if (walBytes + projected > hardBytes)
      throw StoragePressure('wal-backpressure');
    final T result;
    try {
      result = await commit();
    } on StaleRevision {
      rethrow;
    } on CommandCollision {
      rethrow;
    } catch (error) {
      if (expectedRejection?.call(error) ?? false) rethrow;
      poisoned =
          true; // Commit outcome may be unknown: reopen + query command ID.
      rethrow;
    }
    // Maintenance is separate from the committed receipt. A failed checkpoint
    // cannot revoke a durable ACK or trigger a second logical command.
    try {
      await maintain(idle: walBytes > softBytes);
    } catch (e) {
      poisoned = true;
      maintenance.add({
        'deferred': true,
        'errorType': '${e.runtimeType}',
        'revisionAlreadyCommitted': result is int ? result : null,
      });
    }
    return result;
  }
}
