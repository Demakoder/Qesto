import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/windows_key_probe.dart';
import 'package:sqlite3/sqlite3.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Map<String, Object?> nativeInfo(SpikeStore store) {
  final result = <String, Object?>{
    'sqlite': sqlite3.version.libVersion,
    'sqliteNumber': sqlite3.version.versionNumber,
    'sourceId': sqlite3.version.sourceId,
    'cipherPragma': store.raw
        .select('PRAGMA cipher')
        .map((r) => r.values.toList())
        .toList(),
    'journal': store.raw.select('PRAGMA journal_mode').single.values.single,
    'synchronous': store.raw.select('PRAGMA synchronous').single.values.single,
    'tempStore': store.raw.select('PRAGMA temp_store').single.values.single,
    'compileOptions': store.raw
        .select('PRAGMA compile_options')
        .map((r) => r.values.single)
        .toList(),
    'walResetFixed': walResetFixed(sqlite3.version.versionNumber),
  };
  if (store.candidate != Candidate.payloadGcm) {
    for (final expr in [
      'sqlite3mc_version()',
      'sqlite3mc_config(\'sqlcipher\',\'hmac_use\')',
      'sqlite3mc_config(\'hmac_check\')',
    ]) {
      try {
        result[expr] = store.raw.select('SELECT $expr').single.values.single;
      } catch (_) {
        result[expr] = 'not exposed';
      }
    }
  }
  return result;
}

Future<void> mustReject(Future<Object?> Function() action, String label) async {
  var rejected = false;
  try {
    await action();
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'Unsafe acceptance: $label');
}

Future<Map<String, Object?>> releaseSafety(Candidate candidate) async {
  final dir = createSpikeDirectory();
  final key = randomKey();
  final path = '${dir.path}/release.db';
  var store = await SpikeStore.open(path, candidate, key);
  final native = nativeInfo(store);
  final value = syntheticSnapshot(60);
  await store.apply(id: 'release-command', expected: 0, snapshot: value);
  await mustReject(() => SpikeStore.open(path, candidate, null), 'missing key');
  await mustReject(
    () => SpikeStore.open(path, candidate, randomKey()),
    'wrong key',
  );
  for (final fault in [
    Fault.beforeTransaction,
    Fault.afterSnapshot,
    Fault.afterOutbox,
  ]) {
    await mustReject(
      () => store.apply(
        id: 'fail-${fault.name}',
        expected: 1,
        snapshot: value,
        fault: (stage) {
          if (stage == fault) throw StateError('injected');
        },
      ),
      'rollback',
    );
    check(await store.revision() == 1, 'Rollback changed durable revision');
  }
  await mustReject(
    () => store.apply(
      id: 'lost-ack',
      expected: 1,
      snapshot: value,
      fault: (stage) {
        if (stage == Fault.afterCommit) throw StateError('lost ACK');
      },
    ),
    'lost ACK',
  );
  check(
    await store.apply(id: 'lost-ack', expected: 1, snapshot: value) == 2,
    'Durable retry failed',
  );
  final other = await SpikeStore.open(path, candidate, key);
  try {
    await mustReject(
      () => other.apply(id: 'stale', expected: 0, snapshot: value),
      'stale writer',
    );
    // A WAL reader retains its snapshot while the separate writer commits.
    other.raw.execute('BEGIN');
    check(
      other.raw.select('SELECT revision FROM state').single['revision'] == 2,
      'Reader revision',
    );
    await store.apply(id: 'concurrent', expected: 2, snapshot: value);
    check(
      other.raw.select('SELECT revision FROM state').single['revision'] == 2,
      'Read snapshot changed',
    );
    other.raw.execute('COMMIT');
    check(await other.revision() == 3, 'Reader did not see new commit');
  } finally {
    await other.close();
  }
  final backup = '${dir.path}/online.db';
  await store.backup(backup);
  final scan = <String, int>{};
  for (final file in dir.listSync().whereType<File>()) {
    final bytes = file.readAsBytesSync();
    check(
      !latin1.decode(bytes).contains(marker),
      'Plaintext financial payload found',
    );
    scan[file.uri.pathSegments.last] = bytes.length;
  }
  await store.verify();
  final nextKey = randomKey();
  await store.rotateKey(nextKey);
  await store.close();
  await mustReject(
    () => SpikeStore.open(path, candidate, key),
    'old key after rotation',
  );
  store = await SpikeStore.open(path, candidate, nextKey);
  await store.verify();
  await store.close();
  final restore = await SpikeStore.open(backup, candidate, key);
  await restore.verify();
  await restore.close();
  final result = <String, Object?>{
    'candidate': candidate.name,
    'native': native,
    'releaseChecks': 'pass',
    'encryptionScan': scan,
    'rotation': 'DB-only pass; vault cutover not proven',
    'readDuringWrite': 'WAL snapshot isolation pass',
    'backup': 'online backup reopened with retained key',
  };
  requireOwnedPath(path);
  dir.deleteSync(recursive: true);
  return result;
}

Future<void> worker() async {
  final input = stdin.transform(utf8.decoder).transform(const LineSplitter());
  final iterator = StreamIterator(input);
  await iterator.moveNext();
  final job = jsonDecode(iterator.current) as Map<String, dynamic>;
  final candidate = Candidate.values.byName(job['candidate'] as String);
  final key = job.containsKey('wrappedKey')
      ? WindowsKeyProbe.unprotect(base64Decode(job['wrappedKey'] as String))
      : base64Decode(job['key'] as String);
  final store = await SpikeStore.open(
    job['path'] as String,
    candidate,
    key,
    journal: job['journal'] as String? ?? 'WAL',
  );
  final mode = job['mode'];
  if (mode == 'reopen') {
    await store.verify();
    exit(86);
  }
  if (mode == 'vault') {
    await store.verify();
    await store.close();
    stdout.writeln('VAULT_REOPEN_OK');
    await iterator.cancel();
    return;
  }
  if (mode == 'checkpoint') {
    // Parent may terminate during native checkpoint; exact phase is not guaranteed.
    stdout.writeln('READY');
    await stdout.flush();
    await iterator.moveNext();
    await store.checkpoint();
    stdout.writeln('DONE');
    await stdout.flush();
    await store.close();
    await iterator.cancel();
    return;
  }
  if (mode == 'backup') {
    await store.backup(
      job['target'] as String,
      progress: (fraction) {
        if (fraction > 0 && fraction < 1) exit(86);
      },
    );
    throw StateError('Backup was too small to inject a partial-copy crash');
  }
  final expected = await store.revision();
  final value = syntheticSnapshot(job['count'] as int? ?? 5);
  if (mode == 'writer') {
    stdout.writeln('READY');
    await stdout.flush();
    await iterator.moveNext();
  }
  try {
    await store.apply(
      id: job['id'] as String,
      expected: expected,
      snapshot: value,
      fault: (stage) {
        if (stage.name == job['fault']) exit(86);
        if (mode == 'commit-window' && stage == Fault.afterOutbox) {
          stdout.writeln('READY');
          // A bounded pause allows the parent to arm a kill near COMMIT.
          sleep(const Duration(milliseconds: 50));
        }
      },
    );
    await store.close();
    stdout.writeln('COMMITTED');
  } catch (e) {
    // Do not print SQL, payloads or keys, even on failure.
    stdout.writeln('REJECTED:${e.runtimeType}');
    await store.close();
  }
  await iterator.cancel();
}

Future<({Process process, StreamIterator<String> lines})> startWorker(
  Map<String, Object?> job,
) async {
  final process = await Process.start(Platform.resolvedExecutable, ['worker']);
  // Secret travels only through the child's stdin, never argv or log.
  process.stdin.writeln(jsonEncode(job));
  await process.stdin.flush();
  if (job['mode'] != 'writer' && job['mode'] != 'checkpoint')
    await process.stdin.close();
  unawaited(process.stderr.drain<void>());
  return (
    process: process,
    lines: StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    ),
  );
}

Future<Map<String, Object?>> crashSuite(
  Candidate candidate,
  String journal,
) async {
  final result = <String, Object?>{
    'candidate': candidate.name,
    'journal': journal,
  };
  for (final fault in Fault.values) {
    final dir = createSpikeDirectory();
    final path = '${dir.path}/crash.db';
    final key = randomKey();
    var store = await SpikeStore.open(path, candidate, key, journal: journal);
    await store.close();
    final child = await startWorker({
      'candidate': candidate.name,
      'path': path,
      'key': base64Encode(key),
      'mode': 'fault',
      'fault': fault.name,
      'id': 'crash',
    });
    check(await child.process.exitCode == 86, 'Expected unclean process exit');
    await child.lines.cancel();
    store = await SpikeStore.open(path, candidate, key, journal: journal);
    await store.verify();
    final committed = fault == Fault.afterCommit;
    check(
      await store.revision() == (committed ? 1 : 0),
      'Crash durable revision',
    );
    if (committed)
      check(
        await store.apply(
              id: 'crash',
              expected: 0,
              snapshot: syntheticSnapshot(5),
            ) ==
            1,
        'Retry lost ACK',
      );
    result[fault.name] = 'pass';
    await store.close();
    requireOwnedPath(path);
    dir.deleteSync(recursive: true);
  }
  final dir = createSpikeDirectory();
  final path = '${dir.path}/writers.db';
  final key = randomKey();
  var store = await SpikeStore.open(path, candidate, key, journal: journal);
  await store.close();
  final children = await Future.wait([
    for (var i = 0; i < 2; i++)
      startWorker({
        'candidate': candidate.name,
        'path': path,
        'key': base64Encode(key),
        'mode': 'writer',
        'id': 'writer-$i',
        'journal': journal,
      }),
  ]);
  for (final child in children) {
    check(
      await child.lines.moveNext() && child.lines.current == 'READY',
      'Writer barrier',
    );
  }
  for (final child in children) {
    child.process.stdin.writeln('GO');
    await child.process.stdin.close();
  }
  final states = <String>[];
  for (final child in children) {
    while (await child.lines.moveNext()) {
      states.add(child.lines.current);
    }
    check(await child.process.exitCode == 0, 'Writer process failed');
  }
  check(
    states.where((s) => s == 'COMMITTED').length == 1,
    'Lost update: two stale writers accepted',
  );
  check(
    states.where((s) => s.startsWith('REJECTED:')).length == 1,
    'Stale writer was not rejected',
  );
  store = await SpikeStore.open(path, candidate, key, journal: journal);
  await store.verify();
  check(await store.revision() == 1, 'Concurrent revision');
  result['twoProcesses'] = states;
  await store.close();
  requireOwnedPath(path);
  dir.deleteSync(recursive: true);
  return result;
}

Future<Map<String, Object?>> maintenanceCrashes(Candidate candidate) async {
  final dir = createSpikeDirectory();
  final path = '${dir.path}/maintenance.db';
  final key = randomKey();
  var store = await SpikeStore.open(path, candidate, key);
  await store.apply(
    id: 'seed',
    expected: 0,
    snapshot: syntheticSnapshot(10000),
  );
  // Keep original connection open, preserving a live WAL during worker crashes.
  final result = <String, Object?>{'candidate': candidate.name};
  if (Platform.isWindows) {
    final protected = WindowsKeyProbe.protect(key);
    File(
      '${dir.path}/synthetic.vault',
    ).writeAsBytesSync(protected, flush: true);
    final recovered = WindowsKeyProbe.unprotect(protected);
    check(base64Encode(recovered) == base64Encode(key), 'DPAPI round trip');
    final vault = await startWorker({
      'candidate': candidate.name,
      'path': path,
      'wrappedKey': base64Encode(
        File('${dir.path}/synthetic.vault').readAsBytesSync(),
      ),
      'mode': 'vault',
    });
    check(
      await vault.lines.moveNext() && vault.lines.current == 'VAULT_REOPEN_OK',
      'DPAPI fresh-process reopen',
    );
    check(await vault.process.exitCode == 0, 'DPAPI child failed');
    await vault.lines.cancel();
    final altered = List<int>.of(protected);
    altered[altered.length - 1] ^= 1;
    await mustReject(
      () => Future.value(WindowsKeyProbe.unprotect(altered)),
      'Corrupt protected key',
    );
    result['windowsKey'] =
        'DPAPI current-user round trip + new-process keyed DB reopen + corrupt blob rejected';
  }
  final commitTrials = <Object>[];
  for (final delay in [45, 50, 55, 65]) {
    final killPath = '${dir.path}/commit-$delay.db';
    final seed = await SpikeStore.open(killPath, candidate, key);
    await seed.close();
    final commit = await startWorker({
      'candidate': candidate.name,
      'path': killPath,
      'key': base64Encode(key),
      'mode': 'commit-window',
      'id': 'commit-kill',
      'count': 10000,
    });
    check(
      await commit.lines.moveNext() && commit.lines.current == 'READY',
      'Commit window barrier',
    );
    await Future<void>.delayed(Duration(milliseconds: delay));
    commit.process.kill();
    final status = await commit.process.exitCode;
    await commit.lines.cancel();
    final recovered = await SpikeStore.open(killPath, candidate, key);
    await recovered.verify();
    commitTrials.add({
      'delayMs': delay,
      'exitCode': status,
      'durableRevision': await recovered.revision(),
    });
    await recovered.close();
  }
  result['commitWindowKills'] = {
    'trials': commitTrials,
    'exactNativePhase': 'unverified timing injection, not power-loss proof',
  };
  final backup = '${dir.path}/interrupted.db';
  final child = await startWorker({
    'candidate': candidate.name,
    'path': path,
    'key': base64Encode(key),
    'mode': 'backup',
    'target': backup,
  });
  check(
    await child.process.exitCode == 86,
    'Backup interruption did not occur',
  );
  await child.lines.cancel();
  await store.verify();
  await mustReject(
    () => SpikeStore.open(backup, candidate, key),
    'Incomplete backup accepted',
  );
  result['duringBackup'] =
      'partial page-copy interrupted; incomplete target rejected; source intact';
  final reopen = await startWorker({
    'candidate': candidate.name,
    'path': path,
    'key': base64Encode(key),
    'mode': 'reopen',
  });
  check(await reopen.process.exitCode == 86, 'Restore/reopen crash missing');
  await reopen.lines.cancel();
  await store.verify();
  result['afterReopen'] = 'pass';
  final cp = await startWorker({
    'candidate': candidate.name,
    'path': path,
    'key': base64Encode(key),
    'mode': 'checkpoint',
  });
  check(
    await cp.lines.moveNext() && cp.lines.current == 'READY',
    'Checkpoint barrier',
  );
  cp.process.stdin.writeln('GO');
  await cp.process.stdin.close();
  await Future<void>.delayed(const Duration(milliseconds: 1));
  cp.process.kill();
  final code = await cp.process.exitCode;
  await cp.lines.cancel();
  await store.close();
  store = await SpikeStore.open(path, candidate, key);
  await store.verify();
  result['checkpointKill'] = {
    'exitCode': code,
    'integrity': 'pass',
    'exactNativePhase': 'unverified',
  };
  await store.close();
  requireOwnedPath(path);
  dir.deleteSync(recursive: true);
  return result;
}

Future<Map<String, Object?>> bench(
  Candidate candidate,
  int count,
  String journal,
) async {
  final samples = <Map<String, Object?>>[];
  for (var trial = 0; trial < 3; trial++) {
    final serializationWatch = Stopwatch()..start();
    final value = syntheticSnapshot(count);
    final serializeMs = serializationWatch.elapsedMicroseconds / 1000;
    final dir = createSpikeDirectory();
    final path = '${dir.path}/bench.db';
    final key = randomKey();
    var store = await SpikeStore.open(path, candidate, key, journal: journal);
    final watch = Stopwatch()..start();
    await store.apply(id: 'seed', expected: 0, snapshot: value);
    final writeMs = watch.elapsedMicroseconds / 1000;
    watch
      ..reset()
      ..start();
    check(await store.snapshot() == value, 'Read mismatch');
    final readMs = watch.elapsedMicroseconds / 1000;
    watch
      ..reset()
      ..start();
    // Three real batches of 100 note edits; each rewrites the whole snapshot.
    var latest = value;
    for (var i = 0; i < 3; i++) {
      latest = syntheticSnapshot(count, editVersion: i + 1);
      await store.apply(
        id: 'batch-$i',
        expected: i + 1,
        snapshot: latest,
        intent: 'batch 100 synthetic edits',
      );
    }
    final batchMs = watch.elapsedMicroseconds / 1000;
    final fileSizes = <String, int>{};
    for (final file in dir.listSync().whereType<File>()) {
      fileSizes[file.uri.pathSegments.last] = file.lengthSync();
    }
    await store.close();
    watch
      ..reset()
      ..start();
    store = await SpikeStore.open(path, candidate, key, journal: journal);
    await store.verify();
    check(await store.snapshot() == latest, 'Recovery mismatch');
    final recoveryMs = watch.elapsedMicroseconds / 1000;
    samples.add({
      'trial': trial + 1,
      'writeMs': writeMs,
      'serializeMs': serializeMs,
      'loadMs': readMs,
      'batch3Ms': batchMs,
      'reopenVerifyMs': recoveryMs,
      'fileSizes': fileSizes,
      'rssBytes': ProcessInfo.currentRss,
      'processMaxRssBytes': ProcessInfo.maxRss,
      'snapshotBytes': utf8.encode(value).length,
    });
    await store.close();
    requireOwnedPath(path);
    dir.deleteSync(recursive: true);
  }
  return {
    'candidate': candidate.name,
    'operations': count,
    'journal': journal,
    'samples': samples,
  };
}

Future<void> probeMain(List<String> args, List<Candidate> candidates) async {
  if (args.isNotEmpty && args.first == 'worker') {
    await worker();
    return;
  }
  final results = <String, Object?>{
    'platform': Platform.operatingSystem,
    'dart': Platform.version,
    'syntheticOnly': true,
  };
  if (args.isNotEmpty && args.first == 'bench') {
    final c = Candidate.values.byName(args[1]);
    results['benchmark'] = await bench(
      c,
      int.parse(args[2]),
      args.length > 3 ? args[3] : 'WAL',
    );
  } else {
    final safety = <Object>[];
    final crashes = <Object>[];
    final maintenance = <Object>[];
    for (final c in candidates) {
      safety.add(await releaseSafety(c));
      for (final journal in ['WAL', 'DELETE']) {
        crashes.add(await crashSuite(c, journal));
      }
      maintenance.add(await maintenanceCrashes(c));
    }
    results['safety'] = safety;
    results['crashes'] = crashes;
    results['maintenance'] = maintenance;
  }
  stdout.writeln(jsonEncode(results));
}

Future<void> main(List<String> args) async {
  try {
    await probeMain(args, [Candidate.driftMc, Candidate.directMc]);
  } catch (e) {
    stderr.writeln(
      'Probe failed (${e.runtimeType}); no SQL/key/payload logged',
    );
    exitCode = 1;
  }
}
