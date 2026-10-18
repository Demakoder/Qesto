/// Experiment-only owner: no SQLite object crosses an isolate boundary.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'storage_spike.dart';
import 'native_faults.dart';
import 'wal_policy.dart';

class WriterOwner {
  WriterOwner._(this._isolate, this._send);
  final Isolate _isolate;
  final SendPort _send;
  bool _closing = false;
  static Future<WriterOwner> start(
    String path,
    List<int> key,
    String metricsDll,
  ) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_run, [
      ready.sendPort,
      path,
      key,
      metricsDll,
    ]);
    final result = await ready.first;
    ready.close();
    if (result is! SendPort) {
      isolate.kill();
      throw StateError('Writer initialization failed');
    }
    return WriterOwner._(isolate, result);
  }

  Future<Map<String, Object?>> _request(Map<String, Object?> command) async {
    if (_closing) throw StateError('Owner is closing; new work rejected');
    final reply = ReceivePort();
    _send.send({...command, 'reply': reply.sendPort});
    try {
      final result = Map<String, Object?>.from(await reply.first as Map);
      if (result.containsKey('error'))
        throw StateError('Writer: ${result['error']}');
      return result;
    } finally {
      reply.close();
    }
  }

  Future<Map<String, Object?>> apply(
    String id,
    int expected,
    int count,
    int edit,
  ) => _request({
    'op': 'apply',
    'id': id,
    'expected': expected,
    'count': count,
    'edit': edit,
  });
  Future<Map<String, Object?>> verify() => _request({'op': 'verify'});
  Future<Map<String, Object?>> close() async {
    final pending = _request({'op': 'close'});
    _closing =
        true; // Queue already accepted requests; do not kill a transaction.
    return pending;
  }

  // Emergency kill exposed only for test harness cleanup, not normal shutdown.
  void abortForTest() => _isolate.kill(priority: Isolate.immediate);
}

Future<void> _run(List<Object> arguments) async {
  final ready = arguments[0] as SendPort;
  SpikeStore? store;
  try {
    store = await SpikeStore.open(
      arguments[1] as String,
      Candidate.directMc,
      arguments[2] as List<int>,
      autoCheckpointPages: 1000,
    );
  } catch (e) {
    ready.send({'error': '${e.runtimeType}'});
    return;
  }
  final db = store, policy = WalPolicy(db);
  final metrics = NativeFaults(arguments[3] as String, install: false);
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  // ReceivePort.listen(async...) alone overlaps at awaits. Serialize explicitly.
  Future<void> tail = Future.value();
  inbox.listen((dynamic incoming) {
    final command = incoming as Map, reply = command['reply'] as SendPort;
    tail = tail.then((_) async {
      try {
        switch (command['op']) {
          case 'apply':
            final cpu = metrics.cpuMs,
                total = Stopwatch()..start(),
                serial = Stopwatch()..start();
            final snapshot = syntheticSnapshot(
              command['count'] as int,
              editVersion: command['edit'] as int,
            );
            serial.stop();
            final commit = Stopwatch()..start();
            final revision = await policy.apply(
              command['id'] as String,
              command['expected'] as int,
              snapshot,
            );
            commit.stop();
            total.stop();
            reply.send({
              'revision': revision,
              'snapshotBytes': snapshot.length,
              'serializeAndConstructMs': serial.elapsedMicroseconds / 1000,
              'commitAndCheckpointMs': commit.elapsedMicroseconds / 1000,
              'totalMs': total.elapsedMicroseconds / 1000,
              'processCpuMs': metrics.cpuMs - cpu,
              'currentRss': ProcessInfo.currentRss,
              'peakRss': ProcessInfo.maxRss,
              'files': sizes(db.path),
              'lastMaintenance': policy.maintenance.last,
            });
          case 'verify':
            await db.verify();
            reply.send({
              'revision': await db.revision(),
              'files': sizes(db.path),
            });
          case 'close':
            Map<String, Object?> status;
            try {
              status = {
                'checkpoint': (await policy.maintain(idle: true)).toJson(),
              };
            } catch (e) {
              status = {'maintenanceDeferred': '${e.runtimeType}'};
            }
            await db.close();
            inbox.close();
            reply.send({'closed': true, ...status});
          default:
            throw StateError('Unknown owner request');
        }
      } catch (e) {
        reply.send({'error': '${e.runtimeType}'});
      }
    });
  });
}
