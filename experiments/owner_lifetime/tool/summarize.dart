import 'dart:convert';
import 'dart:io';

void main() {
  dynamic read(String path) => jsonDecode(File(path).readAsStringSync());
  Map<String, dynamic> measurement(String path) {
    final d = read(path), runs = (d['samples'] as List).cast<Map>();
    double median(String field) {
      final values = [for (final r in runs) ((r[field] as Map)['total_ms'] as num).toDouble()]..sort();
      return values[values.length ~/ 2];
    }
    return {'complete': d['complete'], 'trials': runs.length,
      'localMedianMs': median('local'), 'senderMedianMs': median('sender'),
      'receiverMedianMs': median('receiver'),
      'peakRssBytes': [for (final r in runs) r['peak_rss_bytes'] as int].reduce((a,b) => a>b?a:b),
      'receiverMainGapMaxMs': [for (final r in runs) ((r['receiver'] as Map)['max_primary_isolate_timer_gap_ms'] as num).toDouble()].reduce((a,b) => a>b?a:b),
      'fullFinancialParity': runs.every((r) => r['full_v7_parity'] == true)};
  }
  const root = 'results/';
  final freshFull = measurement('${root}baseline/benchmark-full-10000.json');
  final current = measurement('${root}bounded-matched-10k/benchmark-effects-10000.json');
  final cycles = (read('${root}bounded-cycles/cycles.json') as List).cast<Map>();
  final gc = (read('${root}bounded-cycles/cycles-gc.json') as List).cast<Map>();
  final result = {
    'runtime': 'Windows x64 Flutter debug test VM, two controllers, real AOT synthetic server',
    'matched': {
      'full_1000': measurement('${root}baseline/benchmark-full-1000.json'),
      'effects_1000': measurement('${root}baseline/benchmark-effects-1000.json'),
      'bounded_1000': measurement('${root}bounded-matched/benchmark-effects-1000.json'),
      'full_10000': freshFull,
      'effects_10000': measurement('${root}baseline/benchmark-effects-10000.json'),
      'bounded_10000': current,
    },
    'resourceGates': {
      'localAtMost3000Ms': (current['localMedianMs'] as double) <= 3000,
      'receiverAtMost6000Ms': (current['receiverMedianMs'] as double) <= 6000,
      'senderNoSlowerFreshFull': (current['senderMedianMs'] as double) <= (freshFull['senderMedianMs'] as double),
      'rssAtMost110PercentFreshFull': (current['peakRssBytes'] as int) <= (freshFull['peakRssBytes'] as int) * 1.1,
      'startup50000Ready30s': read('${root}phases-startup-before/startup-50000.json')['passed'],
    },
    'cycles': {'completed': cycles.length, 'allFullParity': cycles.every((c) => c['fullParity'] == true),
      'last': cycles.last, 'gcMiB': [for (final g in gc) {'phase': g['phase'],
        'heap': ((g['groups'] as List).first['memory']['heapUsage'] as int) / 1048576}]},
  };
  File('${root}summary.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln(jsonEncode(result['resourceGates']));
}
