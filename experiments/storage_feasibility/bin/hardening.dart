import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/native_faults.dart';
import 'package:qesto_storage_spike/wal_policy.dart';
import 'package:qesto_storage_spike/windows_key_probe.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

String snapshot(int version, {int bytes = 100000}) => jsonEncode({
  'synthetic': marker,
  'version': version,
  'padding': List.filled(bytes, 'x').join(),
});
Future<SpikeStore> open(String path, List<int> key) =>
    SpikeStore.open(path, Candidate.directMc, key);
final records = <Map<String, Object?>>[];
late NativeFaults faults;
late String shim;
Future<void> record(
  String name,
  Future<Map<String, Object?>> Function() body,
) async {
  final watch = Stopwatch()..start();
  try {
    final details = await body();
    records.add({
      'test': name,
      'pass': true,
      'ms': watch.elapsedMilliseconds,
      ...details,
    });
    stdout.writeln('PASS $name');
  } catch (e, st) {
    records.add({
      'test': name,
      'pass': false,
      'errorType': '${e.runtimeType}',
      'reason': e is StateError ? e.message.toString() : 'see error type',
      'stack': st.toString().split('\n').take(5).join('\n'),
    });
    stderr.writeln('FAIL $name (${e.runtimeType})');
  } finally {
    faults.disarm();
  }
}

Future<Map<String, Object?>> walSuite() async {
  final dir = createSpikeDirectory(), key = randomKey();
  final path = '${dir.path}/wal.db';
  final store = await open(path, key);
  final policy = WalPolicy(store, softBytes: 4 * mib, hardBytes: 20 * mib);
  try {
    check(
      store.raw.select('PRAGMA wal_autocheckpoint').single.values.single ==
          1000,
      'auto threshold',
    );
    await policy.apply('seed', 0, snapshot(0, bytes: mib));
    final reader = openNative(path, Candidate.directMc, key);
    var blocked = false, committed = 1, peak = 0;
    final series = <Map<String, Object?>>[];
    try {
      reader.execute('BEGIN');
      check(
        reader.select('SELECT revision FROM state').single['revision'] == 1,
        'reader seed',
      );
      for (var i = 1; i <= 40; i++) {
        try {
          await policy.apply('pinned-$i', committed, snapshot(i, bytes: mib));
          committed++;
        } on StoragePressure {
          blocked = true;
          break;
        }
        peak = max(peak, policy.walBytes);
        series.add({'revision': committed, ...sizes(path)});
      }
      check(blocked, 'pinned reader must exert bounded backpressure');
      check(policy.walBytes < policy.hardBytes, 'measured WAL bound');
      final cp = await policy.maintain(idle: true);
      check(
        cp.busy == 1 && cp.pending > 0,
        'TRUNCATE must report blocked reader',
      );
      check(
        reader.select('SELECT revision FROM state').single['revision'] == 1,
        'reader stable snapshot',
      );
      reader.execute('ROLLBACK');
    } finally {
      reader.close();
    }
    final freed = await policy.maintain(idle: true);
    check(
      freed.busy == 0 && policy.walBytes == 0,
      'WAL resets after lease release',
    );
    // Long sequence under the real auto+explicit policy, with full snapshot rewrites.
    for (var i = 0; i < 80; i++) {
      await policy.apply('steady-$i', committed++, snapshot(i, bytes: mib));
      peak = max(peak, policy.walBytes);
      if (i % 10 == 0) series.add({'revision': committed, ...sizes(path)});
    }
    await store.verify();
    final end = sizes(path);
    await policy.maintain(idle: true);
    return {
      'readerBackpressure': blocked,
      'commits': committed,
      'peakWal': peak,
      'series': series,
      'beforeFinalCheckpoint': end,
      'afterFinalCheckpoint': sizes(path),
      'checkpoints': policy.maintenance,
    };
  } finally {
    await store.close();
  }
}

Future<Map<String, Object?>> pressureSuite() async {
  final dir = createSpikeDirectory(), key = randomKey();
  final path = '${dir.path}/pressure.db';
  final store = await open(path, key);
  try {
    await store.apply(id: 'seed', expected: 0, snapshot: snapshot(0));
    final policy = WalPolicy(store, available: () => 100);
    var rejected = false;
    try {
      await policy.apply('low-space', 1, snapshot(1));
    } on StoragePressure catch (e) {
      rejected = e.reason == 'disk-headroom';
    }
    check(rejected && await store.revision() == 1, 'preflight must not mutate');
    final pages =
        store.raw.select('PRAGMA page_count').single.values.single as int;
    store.raw.execute('PRAGMA max_page_count = $pages');
    int? code;
    try {
      await store.apply(
        id: 'full',
        expected: 1,
        snapshot: snapshot(2, bytes: 2 * mib),
      );
    } on sql.SqliteException catch (e) {
      code = e.resultCode;
    }
    check(
      code == 13,
      'native SQLITE_FULL preserved (not replaced by ROLLBACK error)',
    );
    await store.verify();
    check(await store.revision() == 1, 'FULL atomic rollback');
    return {
      'simulatedFreeBytes': 100,
      'nativeMaxPageCount': pages,
      'nativeResultCode': code,
      'actualDiskFree': availableDiskBytes(path),
      'physicalDiskFullTest': false,
    };
  } finally {
    await store.close();
  }
}

Future<Map<String, Object?>> busySuite() async {
  final dir = createSpikeDirectory(), key = randomKey();
  final path = '${dir.path}/busy.db';
  final store = await open(path, key), contender = await open(path, key);
  try {
    await store.apply(id: 'seed', expected: 0, snapshot: snapshot(0));
    contender.raw.execute('PRAGMA busy_timeout=25');
    store.raw.execute('BEGIN IMMEDIATE');
    int? code;
    try {
      await contender.apply(id: 'blocked', expected: 1, snapshot: snapshot(1));
    } on sql.SqliteException catch (e) {
      code = e.resultCode;
    }
    store.raw.execute('ROLLBACK');
    check(code == 5, 'writer conflict returns BUSY');
    await contender.apply(id: 'blocked', expected: 1, snapshot: snapshot(1));
    await contender.verify();
    return {
      'nativeResultCode': code,
      'retryRevision': await contender.revision(),
    };
  } finally {
    await contender.close();
    await store.close();
  }
}

Future<Map<String, Object?>> autoCheckpointSuite() async {
  final dir = createSpikeDirectory(),
      key = randomKey(),
      path = '${dir.path}/auto.db';
  final store = await SpikeStore.open(
    path,
    Candidate.directMc,
    key,
    autoCheckpointPages: 1000,
  );
  final series = <Map<String, int>>[];
  try {
    for (var i = 0; i < 12; i++) {
      await store.apply(
        id: 'auto-$i',
        expected: i,
        snapshot: snapshot(i, bytes: mib),
      );
      series.add(sizes(path));
    }
    check(
      series.last['db']! > mib,
      'native auto checkpoint writes DB while connection remains open',
    );
    check(
      series.map((r) => r['wal']!).reduce(max) < 8 * mib,
      'native auto checkpoint reuses WAL',
    );
    await store.verify();
    return {
      'manualCheckpoints': 0,
      'autoCheckpointPages': 1000,
      'series': series,
    };
  } finally {
    await store.close();
  }
}

Future<Map<String, Object?>> maintenanceAckSuite() async {
  final dir = createSpikeDirectory(),
      key = randomKey(),
      path = '${dir.path}/ack.db';
  var store = await open(path, key);
  try {
    await store.apply(id: 'seed', expected: 0, snapshot: snapshot(0));
    await store.checkpoint();
    faults.attach(store.raw);
    final policy = WalPolicy(store);
    final revision = await policy.apply(
      'saved',
      1,
      snapshot(1),
      fault: (phase) {
        if (phase == Fault.afterCommit) faults.arm(scope: 1, op: 1, code: 778);
      },
    );
    check(
      faults.metric(0) == 1 && policy.poisoned,
      'maintenance error observed',
    );
    faults.disarm();
    check(
      revision == 2 && policy.maintenance.last['revisionAlreadyCommitted'] == 2,
      'maintenance error must not revoke durable receipt',
    );
    var blocked = false;
    try {
      await policy.apply('unsafe-retry', 2, snapshot(2));
    } on StateError {
      blocked = true;
    }
    check(blocked, 'I/O-poisoned owner requires reopen');
    await store.close();
    store = await open(path, key);
    await store.verify();
    check(await store.revision() == 2, 'ack survives recovery');
    return {
      'ack': 2,
      'checkpointError': 778,
      'nextWriteBlockedUntilReopen': true,
      'recoveredRevision': 2,
    };
  } finally {
    faults.disarm();
    await store.close();
  }
}

Future<Map<String, Object?>> errorCase(
  String name,
  int scope,
  int op,
  int code,
  int mode,
  bool checkpoint, {
  int nth = 1,
}) async {
  final dir = createSpikeDirectory(), key = randomKey();
  final path = '${dir.path}/fault.db';
  var store = await open(path, key);
  try {
    await store.apply(id: 'seed', expected: 0, snapshot: snapshot(0));
    await store.checkpoint();
    faults.attach(store.raw);
    // Cache deliberately holds transaction pages so the selected fault is in COMMIT.
    store.raw.execute('PRAGMA cache_size=-16384');
    if (checkpoint)
      await store.apply(id: 'new', expected: 1, snapshot: snapshot(1));
    int? actualCode;
    CheckpointResult? checkpointResult;
    var ack = false;
    try {
      if (checkpoint) {
        faults.arm(scope: scope, op: op, code: code, mode: mode, nth: nth);
        checkpointResult = await store.checkpoint();
      } else {
        await store.apply(
          id: 'new',
          expected: 1,
          snapshot: snapshot(1),
          fault: (phase) {
            if (phase == Fault.afterOutbox)
              faults.arm(
                scope: scope,
                op: op,
                code: code,
                mode: mode,
                nth: nth,
              );
          },
        );
        ack = true;
      }
    } on sql.SqliteException catch (e) {
      actualCode = e.extendedResultCode;
    }
    final hits = faults.metric(0);
    faults.disarm();
    check(
      hits == 1,
      '$name must hit precise native I/O; code=$actualCode cp=${checkpointResult?.toJson()} sizes=${sizes(path)} writes=${faults.metric(1)}',
    );
    check(
      actualCode == code,
      '$name native code preserved ($actualCode expected $code)',
    );
    check(!ack, 'error must not acknowledge command');
    await store.close();
    store = await open(path, key);
    await store.verify();
    final revision = await store.revision();
    check(revision == 1 || revision == 2, 'atomic old/new recovery');
    if (checkpoint)
      check(revision == 2, 'checkpoint failure cannot lose committed snapshot');
    // Lost/error ACK is resolved by exactly the same immutable ID+payload.
    await store.apply(id: 'new', expected: 1, snapshot: snapshot(1));
    await store.verify();
    check(await store.revision() == 2, 'retry no duplicate');
    return {
      'scope': scope,
      'op': op,
      'injectedCode': code,
      'actualCode': actualCode,
      'nativeHits': hits,
      'mode': mode,
      'nthNativeCall': nth,
      'ack': ack,
      'recoveredRevision': revision,
      'retryRevision': 2,
      'physicalDeviceFault': false,
    };
  } finally {
    faults.disarm();
    await store.close();
  }
}

Future<ProcessResult> child(List<String> args) => Process.run(
  Platform.script.path.endsWith('.dart')
      ? '${File(Platform.resolvedExecutable).parent.path}/dart.exe'
      : Platform.resolvedExecutable,
  [
    if (Platform.script.path.endsWith('.dart')) ...[
      'run',
      Platform.script.toFilePath(),
    ],
    ...args,
  ],
  workingDirectory: Directory.current.path,
);

Future<void> crashWorker(List<String> args) async {
  final path = args[1],
      key = WindowsKeyProbe.unprotect(File(args[2]).readAsBytesSync());
  final store = await open(path, key);
  faults.attach(store.raw);
  store.raw.execute('PRAGMA cache_size=-16384');
  final cp = args[3] == 'checkpoint',
      scope = int.parse(args[4]),
      op = int.parse(args[5]),
      mode = int.parse(args[6]),
      nth = int.parse(args[7]);
  if (cp) {
    await store.apply(id: 'new', expected: 1, snapshot: snapshot(1));
    faults.arm(scope: scope, op: op, mode: mode, nth: nth);
    await store.checkpoint();
  } else {
    await store.apply(
      id: 'new',
      expected: 1,
      snapshot: snapshot(1),
      fault: (phase) {
        if (phase == Fault.afterOutbox)
          faults.arm(scope: scope, op: op, mode: mode, nth: nth);
      },
    );
  }
  throw StateError('Native crash hook missed');
}

Future<Map<String, Object?>> crashCase(
  bool checkpoint,
  int scope,
  int op,
  int mode, {
  int nth = 1,
}) async {
  final dir = createSpikeDirectory(), key = randomKey();
  final path = '${dir.path}/crash.db',
      vault = '${dir.path}/synthetic-vault.bin';
  File(vault).writeAsBytesSync(WindowsKeyProbe.protect(key), flush: true);
  var store = await open(path, key);
  await store.apply(id: 'seed', expected: 0, snapshot: snapshot(0));
  await store.close();
  final result = await child([
    'crash-worker',
    path,
    vault,
    checkpoint ? 'checkpoint' : 'commit',
    '$scope',
    '$op',
    '$mode',
    '$nth',
    shim,
  ]);
  check(
    result.exitCode == 86,
    'Exact native crash hook must exit 86 (got ${result.exitCode}): ${result.stderr}',
  );
  store = await open(path, key);
  try {
    await store.verify();
    final recovered = await store.revision();
    if (checkpoint)
      check(recovered == 2, 'checkpoint crash preserves acknowledged commit');
    await store.apply(id: 'new', expected: 1, snapshot: snapshot(1));
    await store.verify();
    return {
      'exitCode': 86,
      'scope': scope,
      'op': op,
      'mode': mode,
      'nthNativeCall': nth,
      'recoveredRevision': recovered,
      'retryRevision': await store.revision(),
      'exactNativePhase': checkpoint ? 'checkpoint' : 'commit',
      'powerLossTest': false,
    };
  } finally {
    await store.close();
  }
}

Future<Map<String, Object?>> corruptionCase(String kind) async {
  final dir = createSpikeDirectory(), key = randomKey();
  final path = '${dir.path}/corrupt.db';
  final store = await open(path, key);
  await store.apply(id: 'seed', expected: 0, snapshot: snapshot(0));
  await store.close();
  final bytes = File(path).readAsBytesSync();
  if (kind == 'truncate') {
    File(path).writeAsBytesSync(bytes.take(200).toList(), flush: true);
  }
  if (kind == 'corrupt') {
    bytes[110] ^= 0x55;
    File(path).writeAsBytesSync(bytes, flush: true);
  }
  final before = File(path).readAsBytesSync();
  var rejected = false;
  try {
    final db = await SpikeStore.open(
      path,
      Candidate.directMc,
      kind == 'missing-key'
          ? null
          : kind == 'wrong-key'
          ? randomKey()
          : key,
    );
    try {
      await db.verify();
    } finally {
      await db.close();
    }
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'Invalid state must not open');
  check(
    base64Encode(before) == base64Encode(File(path).readAsBytesSync()),
    'Failure must not reset existing file',
  );
  return {'rejected': true, 'filePreserved': true, 'size': before.length};
}

Future<void> main(List<String> args) async {
  shim = File(
    args.isNotEmpty && args.first == 'crash-worker'
        ? args.last
        : 'build/hardening/qesto_fault_shim.dll',
  ).absolute.path;
  faults = NativeFaults(shim);
  if (args.isNotEmpty && args.first == 'crash-worker') {
    await crashWorker(args);
    return;
  }
  await record('wal-policy-pinned-reader-and-80-rewrites', walSuite);
  await record('disk-preflight-and-native-FULL', pressureSuite);
  await record('writer-BUSY-and-retry', busySuite);
  await record('standard-native-auto-checkpoint', autoCheckpointSuite);
  await record('checkpoint-error-does-not-revoke-ACK', maintenanceAckSuite);
  await record(
    'commit-final-fsync-error',
    () => errorCase('commit-final-fsync-error', 2, 2, 1034, 0, false, nth: 2),
  );
  await record(
    'commit-error-after-final-fsync',
    () => errorCase(
      'commit-error-after-final-fsync',
      2,
      2,
      1034,
      4,
      false,
      nth: 2,
    ),
  );
  await record(
    'native-crash-after-final-commit-fsync',
    () => crashCase(false, 2, 2, 3, nth: 2),
  );
  for (final spec in [
    ('commit-full', 2, 1, 13, 0, false),
    ('commit-ioerr', 2, 1, 10, 0, false),
    ('commit-write', 2, 1, 778, 0, false),
    ('commit-partial-write', 2, 1, 778, 1, false),
    ('commit-fsync', 2, 2, 1034, 0, false),
    ('commit-error-after-sync', 2, 2, 1034, 4, false),
    ('checkpoint-write', 1, 1, 778, 0, true),
    ('checkpoint-partial-write', 1, 1, 778, 1, true),
    ('checkpoint-fsync', 1, 2, 1034, 0, true),
    ('checkpoint-truncate', 2, 3, 1546, 0, true),
  ]) {
    await record(
      spec.$1,
      () => errorCase(spec.$1, spec.$2, spec.$3, spec.$4, spec.$5, spec.$6),
    );
  }
  for (final spec in [
    (false, 2, 1, 2),
    (false, 2, 1, 3),
    (false, 2, 2, 2),
    (false, 2, 2, 3),
    (true, 1, 1, 2),
    (true, 1, 1, 3),
    (true, 1, 2, 2),
    (true, 1, 2, 3),
    (true, 2, 3, 2),
  ]) {
    await record(
      'native-crash-${spec.$1}-${spec.$2}-${spec.$3}-${spec.$4}',
      () => crashCase(spec.$1, spec.$2, spec.$3, spec.$4),
    );
  }
  for (final kind in ['truncate', 'corrupt', 'missing-key', 'wrong-key']) {
    await record('fail-closed-$kind', () => corruptionCase(kind));
  }
  final output = {
    'date': DateTime.now().toUtc().toIso8601String(),
    'syntheticOnly': true,
    'sqlite': sql.sqlite3.version.libVersion,
    'runtime': Platform.version,
    'results': records,
    'passed': records.where((r) => r['pass'] == true).length,
    'failed': records.where((r) => r['pass'] == false).length,
  };
  File(
    'results/hardening_native.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
  if (records.any((r) => r['pass'] != true)) exitCode = 1;
}
