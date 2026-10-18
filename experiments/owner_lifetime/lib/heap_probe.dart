import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

/// Synthetic profiling only. Raw class/retaining evidence stays on disk, not
/// in the measured controller. No GC RPC is used inside latency intervals.
Future<Map<String, Object?>> captureHeap(String file, String phase, {bool sampleRetainers = false}) async {
  final uri = (await developer.Service.getInfo()).serverUri;
  if (uri == null || !['localhost', '127.0.0.1'].contains(uri.host)) {
    throw StateError('Loopback VM service required for retained-state gate');
  }
  return Isolate.run(() => _capture(uri, file, phase, sampleRetainers));
}

Future<Map<String, Object?>> _capture(Uri uri, String file, String phase, bool sampleRetainers) async {
  final client = HttpClient();
  Future<Map<String, dynamic>> rpc(String method, [Map<String, String>? query]) async {
    final request = await client.getUrl(uri.resolve(method).replace(queryParameters: query));
    final envelope = jsonDecode(await (await request.close()).transform(utf8.decoder).join()) as Map<String, dynamic>;
    if (envelope['error'] != null) throw StateError('$method: ${envelope['error']}');
    return envelope['result'] as Map<String, dynamic>;
  }
  try {
    final started = DateTime.now().toUtc().toIso8601String();
    final beforeRss = ProcessInfo.currentRss;
    final vm = await rpc('getVM');
    final groups = <Object>[];
    final summaries = <Object>[];
    for (final ref in vm['isolateGroups'] as List) {
      if (ref['isSystemIsolateGroup'] == true) continue;
      final group = await rpc('getIsolateGroup', {'isolateGroupId': ref['id'] as String});
      final isolates = group['isolates'] as List;
      if (isolates.isEmpty) continue;
      final id = isolates.first['id'] as String;
      final allocation = await rpc('getAllocationProfile', {'isolateId': id, 'gc': 'true'});
      if (allocation['dateLastServiceGC'] == null) throw StateError('GC was not confirmed');
      final classes = (allocation['members'] as List).cast<Map>();
      final retained = <Object>[];
      const names = {
        'SqliteContainer', 'NotePreparationScope', 'SynoballCore',
        'UserFinancialData', 'CoreJournalPreparation', 'PreparedFinancialCommit',
        'FinancialSnapshot', 'BudgetController', 'CommittedTransactionNote',
        'SynchronizedTransactionNotes', 'EffectsCommitRequest',
      };
      // VM object-ID rings may retain sampled objects. Only sample at the FINAL
      // observation; earlier points must not create service roots for models.
      for (final cls in classes.where((c) => sampleRetainers && {'SqliteContainer', 'NotePreparationScope', 'CoreJournalPreparation'}.contains(c['class']['name']))) {
        final instances = await rpc('getInstances', {
          'isolateId': id, 'objectId': cls['class']['id'] as String, 'limit': '2',
        });
        for (final object in instances['instances'] as List) {
          final objectId = object['id'] as String;
          retained.add({
            'class': cls['class'], 'object': object,
            'retainingPath': await rpc('getRetainingPath', {'isolateId': id, 'targetId': objectId, 'limit': '16'}),
            // Private VM RPC, verified against vm_service 15.3.0's own
            // private_rpcs/get_retained_size_rpc_test.dart. Profiling only.
            'retainedSize': await rpc('_getRetainedSize', {'isolateId': id, 'targetId': objectId}),
            'fields': await rpc('getObject', {'isolateId': id, 'objectId': objectId, 'offset': '0', 'count': '25'}),
          });
        }
      }
      final sorted = [...classes]..sort((a, b) => (b['bytesCurrent'] as int).compareTo(a['bytesCurrent'] as int));
      groups.add({'group': group, 'measuredIsolate': id, 'allocationAfterGC': allocation, 'sampledRetainers': retained});
      summaries.add({
        'group': ref['id'], 'memory': allocation['memoryUsage'],
        'topClasses': [for (final c in sorted.take(12)) {'name': c['class']['name'], 'bytes': c['bytesCurrent'], 'count': c['instancesCurrent']}],
        'domainClasses': [for (final c in classes.where((c) => names.contains(c['class']['name']))) {'name': c['class']['name'], 'count': c['instancesCurrent'], 'shallowBytes': c['bytesCurrent']}],
      });
    }
    final result = {
      'phase': phase, 'pid': pid, 'startedUtc': started,
      'runtime': Platform.version, 'mode': 'Flutter test debug VM, allocation/GC instrumentation',
      'rssBeforeGC': beforeRss, 'rssAfterGCAndProbe': ProcessInfo.currentRss,
      'peakRss': ProcessInfo.maxRss, 'vm': vm, 'groups': groups,
      'sampleRetainers': sampleRetainers,
      'caveats': ['One allocation profile per isolate group; no heap summation across isolates.', 'Retained sizes overlap and are NOT additive.', 'GC/probe timing is excluded from latency benchmark. Object references are bounded samples, not an exhaustive dominator tree.'],
    };
    File(file).parent.createSync(recursive: true);
    File(file).writeAsStringSync(jsonEncode(result));
    return {'file': file, 'phase': phase, 'groups': summaries, 'rss': ProcessInfo.currentRss};
  } finally {
    client.close(force: true);
  }
}
