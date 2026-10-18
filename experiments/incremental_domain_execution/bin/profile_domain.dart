import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto_synthetic_sync/domain.dart' show CommandIds;
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_incremental_sync_experiment/measure.dart';
import '../lib/prepared_owner.dart';
import '../lib/effects.dart';

// Separate process per mode/count. Allocation profiling is a SEPARATE run with
// --enable-vm-service=0; forced GC must not contaminate timed runs.
Future<void> main(List<String> args) async {
  final mode = args[0], count = int.parse(args[1]);
  final allocation = args.contains('--allocation');
  const codec = UserFinancialDataCodec();
  final load = Stopwatch()..start();
  var data = syntheticFixture(count: count);
  final o = PreparedDomainOwner('synthetic-4d', 'lineage-4d', syntheticUser);
  if (mode == 'prepared') o.loadVerified(data, 0);
  final loadUs = load.elapsedMicroseconds;
  WebSocket? socket;
  final pending = <int, void Function(dynamic)>{};
  var rpcId = 0;
  Future<dynamic> rpc(String method, Map<String, Object?> params) async {
    final port = ReceivePort(), id = ++rpcId;
    pending[id] = port.sendPort.send;
    socket!.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    final result = await port.first;
    port.close();
    if (result['error'] != null) throw StateError('${result['error']}');
    return result['result'];
  }

  final isolateId = Service.getIsolateId(Isolate.current)!;
  if (allocation) {
    final info = await Service.getInfo();
    if (info.serverUri == null)
      throw StateError('VM service required for allocation run');
    socket = await WebSocket.connect(
      info.serverUri!
          .replace(scheme: 'ws', path: '${info.serverUri!.path}ws')
          .toString(),
    );
    socket.listen((e) {
      final v = jsonDecode(e as String);
      pending.remove(v['id'])?.call(v);
    });
    await rpc('getAllocationProfile', {
      'isolateId': isolateId,
      'gc': true,
      'reset': true,
    });
  }
  final samples = <Object>[];
  dynamic alloc;
  for (var trial = 0; trial < (allocation ? 1 : 4); trial++) {
    final c = w.NoteCommand.parse({
      'protocol_version': 1,
      'domain_version': 1,
      'workspace_id': 'synthetic-4d',
      'device_id': 'synthetic-4a-a',
      'workspace_epoch': 'lineage-4d',
      'change_id': 'profile-$trial',
      'kind': 'transaction.set_note',
      'transaction_id': 'container-tx-${[0, 1, 3, 0][trial]}',
      'base_revision': '0',
      'note': 'Synthetic measured $trial',
    });
    final time = DateTime.utc(2026, 10, 14, 0, 0, trial);
    final sw = Stopwatch()..start(), cpu = cpuMicros();
    PreparedDomainCommand? prepared;
    final after = mode == 'prepared'
        ? (prepared = o.prepare(
            c,
            trial,
            time,
            w.digest(data.classification.toJson()),
          )).after
        : prepareTransactionNote(
            data,
            c.target,
            c.note,
            ids: CommandIds(c.changeId),
            clock: () => time,
          ).data;
    final domainUs = sw.elapsedMicroseconds;
    final encoded = codec.encode(after);
    final encodeUs = sw.elapsedMicroseconds - domainUs;
    if (prepared != null)
      o.acceptDurable(
        prepared,
        revision: trial + 1,
        durableJson: encoded,
        commandId: c.changeId,
      );
    // Receipt validation only: no SQLite commit in this decomposition benchmark.
    final wallUs = sw.elapsedMicroseconds, cpuUs = cpuMicros() - cpu;
    if (allocation) {
      alloc = await rpc('getAllocationProfile', {'isolateId': isolateId});
      final members = (alloc['members'] as List)
        ..sort(
          (a, b) => (b['accumulatedSize'] as int).compareTo(
            a['accumulatedSize'] as int,
          ),
        );
      alloc = {
        'memoryUsage': alloc['memoryUsage'],
        'top_classes': members.take(30).toList(),
        'includes_oracle_and_effect_capture': false,
        'forced_gc_only_before_workload': true,
        'scope':
            'first command after fixture; domain + encode + receipt check, RPC overhead included',
      };
      await socket!.close();
    }
    // Full oracle + effect capture OUTSIDE timing, separately reported memory.
    final peakBeforeOracle = ProcessInfo.maxRss;
    final oracle = prepareTransactionNote(
      data,
      c.target,
      c.note,
      ids: CommandIds(c.changeId),
      clock: () => time,
    );
    if (codec.encode(oracle.data) != encoded)
      throw StateError('full v7 parity failure');
    final effectWatch = Stopwatch()..start();
    final effects = DomainEffectsV1.between(
      data,
      after,
      c,
      baseRevision: trial,
    );
    final effectUs = effectWatch.elapsedMicroseconds;
    if (codec.encode(effects.reconstruct(data)) != encoded)
      throw StateError('effect reconstruction');
    samples.add({
      'trial': trial,
      'warmup': trial == 0,
      'domain_us': domainUs,
      'encode_us': encodeUs,
      'domain_encode_receipt_us': wallUs,
      'cpu_us': cpuUs,
      'effect_capture_us': effectUs,
      'changed_canonical_entities': effects.canonicalFields.length,
      'full_json_bytes': utf8.encode(encoded).length,
      'peak_before_oracle_bytes': peakBeforeOracle,
      'peak_including_oracle_bytes': ProcessInfo.maxRss,
      'full_codec_parity': true,
    });
    data = after;
  }
  Directory('results').createSync(recursive: true);
  File(
    'results/domain-$mode-$count${allocation ? '-allocation' : ''}.json',
  ).writeAsStringSync(
    jsonEncode({
      'mode': mode,
      'runtime': 'Dart JIT standalone; NOT end-to-end UI/storage latency',
      'count': count,
      'fixture_load_owner_init_us': loadUs,
      'samples': samples,
      'allocation': alloc,
      'no_storage_commit': true,
      'synthetic_only': true,
    }),
  );
  stdout.writeln(
    '$mode $count complete; full parity; peak ${ProcessInfo.maxRss}',
  );
}
