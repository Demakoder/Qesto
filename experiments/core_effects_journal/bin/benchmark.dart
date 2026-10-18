import 'dart:convert';
import 'dart:io';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_incremental_domain_experiment/effects.dart';
import 'package:qesto_incremental_sync_experiment/measure.dart';
import '../lib/app_probe.dart';
import '../lib/oracle.dart';
import '../lib/vm_probe.dart';

// Separate process per mode and size. Timing: warmup + 3 trials, no forced GC.
// Allocation is a separate run, GC/reset before command, profile before oracle.
Future<void> main(List<String> args) async {
  final mode = args[0],
      count = int.parse(args[1]),
      allocation = args.contains('--allocation');
  if (!['journal', 'full-diff', 'domain-only'].contains(mode))
    throw ArgumentError('mode');
  const codec = UserFinancialDataCodec();
  final time = DateTime.utc(2026, 10, 16), load = Stopwatch()..start();
  var data = syntheticFixture(count: count);
  final fingerprint = w.digest(data.classification.toJson());
  CoreEffectsBinding bind(String id, int rev) => CoreEffectsBinding(
    commandId: id,
    workspace: 'synthetic-4e',
    lineage: 'lineage-4e',
    target: 'container-tx-0',
    kind: 'transaction.set_note',
    baseRevision: rev,
    generation: rev,
    policyFingerprint: fingerprint,
  );
  CoreJournalPreparation? prepared;
  SynoballCore? baseline;
  final admit = Stopwatch()..start();
  if (mode == 'journal') {
    prepared = CoreJournalPreparation.fromState(
      initialState: data.synoballState!,
      policy: data.classification.policy,
      binding: bind('load', 0),
      ids: CommandIds('load'),
      clock: () => time,
      execute: (_) => null,
    );
    data = project(data, prepared.state);
  } else {
    baseline = SynoballCore(
      initialState: data.synoballState!,
      categoryPolicy: data.classification.policy,
      ids: CommandIds('load'),
      clock: () => time,
    );
    data = project(data, baseline.state);
  }
  final admissionUs = admit.elapsedMicroseconds,
      loadUs = load.elapsedMicroseconds;
  VmProbe? vm;
  if (allocation) {
    vm = await VmProbe.connect();
    await vm.allocation(gc: true, reset: true);
  }
  final samples = <Map<String, Object?>>[];
  dynamic alloc;
  for (var trial = 0; trial < (allocation ? 1 : 4); trial++) {
    final id = 'measure-$trial', note = 'Synthetic $trial';
    final shown = data.transactions.firstWhere((t) => t.id == 'container-tx-0');
    final watch = Stopwatch()..start(), cpu = cpuMicros();
    if (mode == 'journal') {
      prepared = prepared!.prepareNext(
        binding: bind(id, trial + 1),
        ids: CommandIds(id),
        clock: () => time,
        execute: (core) {
          applyQestoTransactionEdit(
            core,
            shown.copyWith(comment: note),
            actorId: data.user.id,
            displayed: shown,
          );
          return null;
        },
      );
    } else {
      baseline = baseline!.forkForCommand(
        ids: CommandIds(id),
        clock: () => time,
      );
      applyQestoTransactionEdit(
        baseline,
        shown.copyWith(comment: note),
        actorId: data.user.id,
        displayed: shown,
      );
    }
    final executionUs = watch.elapsedMicroseconds;
    final executionCpu = cpuMicros() - cpu;
    // State export and app projections measured separately, not presented as journal cost.
    final projectionWatch = Stopwatch()..start();
    final state = mode == 'journal' ? prepared!.state : baseline!.state;
    final after = project(data, state);
    final projectionUs = projectionWatch.elapsedMicroseconds;
    final command = w.NoteCommand.parse({
      'protocol_version': 1,
      'domain_version': 1,
      'workspace_id': 'synthetic-4e',
      'device_id': 'synthetic-4a-a',
      'workspace_epoch': 'lineage-4e',
      'change_id': id,
      'kind': 'transaction.set_note',
      'transaction_id': 'container-tx-0',
      'base_revision': '0',
      'note': note,
    });
    final captureWatch = Stopwatch()..start(), captureCpu = cpuMicros();
    DomainEffectsV1? diff;
    if (mode == 'full-diff')
      diff = DomainEffectsV1.between(
        data,
        after,
        command,
        baseRevision: trial + 1,
      );
    final captureUs = mode == 'full-diff'
        ? captureWatch.elapsedMicroseconds
        : 0;
    final captureCpuUs = mode == 'full-diff' ? cpuMicros() - captureCpu : 0;
    final resultWatch = Stopwatch()..start();
    // Full-diff roots are real payload, not merely DomainEffectsV1's short summary.
    final payload = mode == 'journal'
        ? jsonEncode(prepared!.journal.toJson())
        : mode == 'full-diff'
        ? jsonEncode({
            'summary': diff!.toJson(),
            'rootValues': diff.roots,
            'coreValues': diff.coreCollections,
          })
        : '';
    final resultEncodeUs = resultWatch.elapsedMicroseconds;
    final peakBeforeOracle = ProcessInfo.maxRss;
    if (vm != null) {
      final a = await vm.allocation();
      final members = (a['members'] as List)
        ..sort(
          (x, y) => (y['accumulatedSize'] as int).compareTo(
            x['accumulatedSize'] as int,
          ),
        );
      alloc = {
        'memoryUsage': a['memoryUsage'],
        'top_classes': members.take(20).toList(),
        'scope':
            'domain + full app projection + mode-specific effects result encode, BEFORE oracle',
        'forced_gc': 'only before workload',
      };
    }
    final oracleWatch = Stopwatch()..start();
    final oracle = prepareTransactionNote(
      data,
      'container-tx-0',
      note,
      ids: CommandIds(id),
      clock: () => time,
    );
    if (codec.encode(after) != codec.encode(oracle.data))
      throw StateError('Full app parity');
    if (mode == 'journal')
      verifyJournal(data.synoballState!, state, prepared!.journal);
    if (diff != null &&
        codec.encode(diff.reconstruct(data)) != codec.encode(after))
      throw StateError('4d oracle replay');
    final changed = mode == 'journal'
        ? prepared!.journal.changedCanonicalIds.length
        : diff?.canonicalFields.length;
    samples.add({
      'trial': trial,
      'warmup': !allocation && trial == 0,
      'execution_us': executionUs,
      'execution_cpu_us': executionCpu,
      'journal_recording_us': mode == 'journal'
          ? prepared!.journal.recordingMicros
          : null,
      'projection_us': projectionUs,
      'full_diff_capture_us': captureUs,
      'full_diff_cpu_us': captureCpuUs,
      'result_encode_us': resultEncodeUs,
      'effect_bytes': utf8.encode(payload).length,
      'changed_canonical': changed,
      'oracle_verify_us': oracleWatch.elapsedMicroseconds,
      'peak_before_oracle_bytes': peakBeforeOracle,
      'peak_including_oracle_bytes': ProcessInfo.maxRss,
      'full_codec_parity': true,
    });
    data = after;
  }
  await vm?.close();
  Directory('results').createSync(recursive: true);
  File(
    'results/$mode-$count${allocation ? '-allocation' : ''}.json',
  ).writeAsStringSync(
    jsonEncode({
      'mode': mode,
      'count': count,
      'runtime': 'Windows Dart JIT standalone; no DB/server/UI',
      'synthetic_only': true,
      'admission_and_initial_projection_us': admissionUs,
      'fixture_and_admission_us': loadUs,
      'samples': samples,
      'allocation': alloc,
      'note':
          'Peaks after trial 0 can include previous oracle allocations. Allocation runs isolate pre-oracle measurement.',
    }),
  );
  stdout.writeln('$mode $count: parity passed');
}
