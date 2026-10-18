import 'dart:convert';
import 'dart:io';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import '../lib/vm_probe.dart';

List<WeakReference<SynoballCore>> aborted(SynoballState state) {
  final refs = <WeakReference<SynoballCore>>[];
  for (var i = 0; i < 40; i++) {
    try {
      CoreJournalPreparation.fromState(
        initialState: state,
        policy: const CategoryPolicy(),
        binding: CoreEffectsBinding(
          commandId: 'abort-$i',
          workspace: 'synthetic-4e',
          lineage: 'lineage',
          target: 'container-tx-0',
          kind: 'transaction.set_note',
          baseRevision: 0,
          generation: 0,
          policyFingerprint: 'synthetic',
        ),
        ids: CommandIds('abort-$i'),
        clock: () => DateTime.utc(2026, 10, 16),
        execute: (core) {
          refs.add(WeakReference(core));
          core.deleteTransaction('container-tx-0', actorId: 'synthetic');
          throw StateError('synthetic prepare failure');
        },
      );
    } on StateError {
      /* expected: no prepared result */
    }
  }
  return refs;
}

Future<void> main() async {
  final vm = await VmProbe.connect();
  final state = syntheticFixture(count: 1000).synoballState!;
  final original = jsonEncode(state.toJson());
  final before = await vm.allocation(gc: true, reset: true);
  final refs = aborted(state);
  await vm.allocation(gc: true);
  final after = await vm.allocation(gc: true);
  final retained = refs.where((ref) => ref.target != null).length;
  if (retained != 0 ||
      jsonEncode(state.toJson()) != original ||
      refs.length != 40) {
    throw StateError('Aborted preparation retained or mutated base');
  }
  File('results/abort-retention.json').writeAsStringSync(
    jsonEncode({
      'synthetic_only': true,
      'attempts': refs.length,
      'retained_cores_after_forced_gc': retained,
      'base_unchanged': true,
      'before': before['memoryUsage'],
      'after': after['memoryUsage'],
      'scope':
          'explicit failed preparation + VM GC, NOT real OOM or power loss',
    }),
  );
  await vm.close();
  stdout.writeln('40 aborted preparations collected; base unchanged');
}
