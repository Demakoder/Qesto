import 'dart:convert';
import 'dart:io';
import 'package:qesto_storage_spike/container/writer.dart';
import 'package:qesto_storage_spike/native_faults.dart';
import 'package:qesto_encrypted_sync_experiment/coordinator.dart';
import 'package:qesto_encrypted_sync_experiment/transport.dart';
import '../test/harness.dart';

Future<void> main(List<String> args) async {
  final h = Harness(), count = int.parse(args.single);
  final metrics = NativeFaults(
    File(
      '../storage_feasibility/build/hardening/qesto_fault_shim.dll',
    ).absolute.path,
    install: false,
  );
  await h.start(count: count);
  try {
    final server = await h.server();
    await h.bootstrapBoth(server);
    final owner = await ContainerWriter.open(h.clients[0].path, h.partition);
    final peer = await ContainerWriter.open(h.clients[1].path, h.partition);
    final c = Coordinator(
      owner,
      h.partition,
      h.config.principals[0],
      LoopbackTransport(server.base, h.config.principals[0]).request,
    );
    final other = Coordinator(
      peer,
      h.partition,
      h.config.principals[1],
      LoopbackTransport(server.base, h.config.principals[1]).request,
    );
    final samples = <Map<String, Object?>>[];
    try {
      for (var trial = 0; trial < 3; trial++) {
        final cpu = metrics.cpuMs, watch = Stopwatch()..start();
        await c.edit(
          'bench-$trial',
          'container-tx-0',
          'Synthetic measured note $trial',
        );
        final localMs = watch.elapsedMicroseconds / 1000,
            localCpu = metrics.cpuMs - cpu;
        watch.reset();
        await c.sync();
        final senderMs = watch.elapsedMicroseconds / 1000;
        watch.reset();
        await other.pull();
        final receiverMs = watch.elapsedMicroseconds / 1000;
        final a = await owner.readSnapshot(), b = await peer.readSnapshot();
        final aa = jsonDecode(a.value.json)['synoball']['transactions'];
        final bb = jsonDecode(b.value.json)['synoball']['transactions'];
        if (jsonEncode(aa) != jsonEncode(bb) ||
            await owner.readCheckpoint() != trial + 1 ||
            await peer.readCheckpoint() != trial + 1)
          throw StateError('benchmark correctness');
        samples.add({
          'trial': trial + 1,
          'local_core_serialization_commit_ms': localMs,
          'local_cpu_ms': localCpu,
          'sender_push_ack_pull_ms': senderMs,
          'receiver_pull_apply_ms': receiverMs,
          'snapshot_bytes': utf8.encode(a.value.json).length,
          'rss_bytes': ProcessInfo.currentRss,
          'peak_rss_bytes': ProcessInfo.maxRss,
          'wal_bytes_while_open': File(
            '${h.clients[0].path}/container-1.db-wal',
          ).lengthSync(),
        });
      }
    } finally {
      await owner.close();
      await peer.close();
    }
    print(
      jsonEncode({
        'count': count,
        'checkpoint_policy': 'FULL, auto=1000, soft=32MiB, hard=256MiB',
        'aot': true,
        'samples': samples,
        'db_bytes_after_close': File(
          '${h.clients[0].path}/container-1.db',
        ).lengthSync(),
        'convergence_verified': true,
      }),
    );
  } finally {
    await h.close();
  }
}
