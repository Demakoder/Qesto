import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/writer_owner.dart';
import 'package:qesto_storage_spike/wal_policy.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<Map<String, Object?>> trial(int count) async {
  final dir = createSpikeDirectory(), key = randomKey();
  final path = '${dir.path}/owner.db';
  final shim = File('build/hardening/qesto_fault_shim.dll').absolute.path;
  final owner = await WriterOwner.start(path, key, shim);
  var ticks = 0, maxDelay = 0;
  final time = Stopwatch()..start();
  var last = time.elapsedMilliseconds;
  final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
    final now = time.elapsedMilliseconds;
    maxDelay = max(maxDelay, now - last);
    last = now;
    ticks++;
  });
  try {
    final rows = <Map<String, Object?>>[];
    rows.add(await owner.apply('initial', 0, count, 0));
    // Separate connection can hold a consistent read while writer is off-isolate.
    final reader = openNative(path, Candidate.directMc, key);
    try {
      reader.execute('BEGIN');
      final seed = reader
          .select('SELECT revision FROM state')
          .single['revision'];
      final updating = owner.apply('edit-1', 1, count, 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      check(
        reader.select('SELECT revision FROM state').single['revision'] == seed,
        'reader isolation',
      );
      reader.execute('ROLLBACK');
      rows.add(await updating);
    } finally {
      reader.close();
    }
    rows.add(await owner.apply('edit-2', 2, count, 2));
    rows.add(await owner.apply('edit-3', 3, count, 3));
    check((await owner.verify())['revision'] == 4, 'four durable commands');
    final shutdown = await owner.close();
    final reopened = await SpikeStore.open(path, Candidate.directMc, key);
    try {
      await reopened.verify();
      check(await reopened.revision() == 4, 'clean restart');
    } finally {
      await reopened.close();
    }
    return {
      'count': count,
      'samples': rows,
      'shutdown': shutdown,
      'afterClose': sizes(path),
      'mainIsolateTimerTicks': ticks,
      'maxTimerIntervalMs': maxDelay,
      'notFlutterFrameTiming': true,
    };
  } finally {
    timer.cancel();
  }
}

Future<Map<String, Object?>> queueTest() async {
  final dir = createSpikeDirectory(),
      key = randomKey(),
      path = '${dir.path}/queue.db';
  final owner = await WriterOwner.start(
    path,
    key,
    File('build/hardening/qesto_fault_shim.dll').absolute.path,
  );
  final pending = [for (var i = 0; i < 10; i++) owner.apply('q-$i', i, 100, i)];
  final closing = owner.close();
  var rejected = false;
  try {
    await owner.apply('late', 10, 100, 11);
  } catch (_) {
    rejected = true;
  }
  final rows = await Future.wait(pending);
  await closing;
  check(
    rejected && rows.last['revision'] == 10,
    'FIFO queue drains before close and rejects late work',
  );
  final db = await SpikeStore.open(path, Candidate.directMc, key);
  try {
    await db.verify();
    check(await db.revision() == 10, 'all accepted work durable');
  } finally {
    await db.close();
  }
  return {
    'pass': true,
    'queued': 10,
    'completedBeforeClose': 10,
    'lateRejected': true,
  };
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stdout.writeln(jsonEncode(await trial(int.parse(args[0]))));
    return;
  }
  final queue = await queueTest(), runs = <Object?>[];
  for (final count in [1000, 10000, 50000]) {
    for (var i = 0; i < 3; i++) {
      final result = await Process.run(Platform.resolvedExecutable, ['$count']);
      check(
        result.exitCode == 0,
        'fresh AOT benchmark child failed: ${result.stderr}',
      );
      runs.add(jsonDecode(result.stdout as String));
      stdout.writeln('PASS benchmark $count trial ${i + 1}');
    }
  }
  File('results/hardening_benchmarks.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'date': DateTime.now().toUtc().toIso8601String(),
      'syntheticOnly': true,
      'queueTest': queue,
      'policy': {
        'autoCheckpointPages': 1000,
        'softWalBytes': 32 * mib,
        'hardWalBytes': 256 * mib,
        'diskFloorBytes': 256 * mib,
        'synchronous': 'FULL',
        'busyTimeoutMs': 100,
      },
      'method':
          'AOT; fresh process per trial; canonical construction+JSON included; process-wide CPU/RSS; 4 full rewrites; native checkpoint enabled',
      'runs': runs,
    }),
  );
}
