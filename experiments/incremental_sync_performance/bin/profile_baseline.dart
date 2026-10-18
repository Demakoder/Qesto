import 'dart:convert';
import 'dart:io';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto/features/transaction_import/services/sber_transaction_projection.dart';
import 'package:qesto/synoball/analytics/qesto_read_model.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/wal_policy.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_incremental_sync_experiment/measure.dart';

Future<void> main(List<String> args) async {
  final counts = args.isEmpty
      ? [1000, 10000, 50000]
      : args.map(int.parse).toList();
  final runs = <Object>[];
  for (final count in counts) {
    const codec = UserFinancialDataCodec();
    final source = encodeSynthetic(
      count: count,
      fixturePath:
          '../storage_feasibility/test/fixtures/container_profile_v7.json',
    );
    final bytes = utf8.encode(source).length, m = Measurements();
    final before = m.run(
      'codec_decode',
      () => codec.decode(source),
      bytes: bytes,
    );
    final time = DateTime.utc(2026, 10, 13);
    // Profiling decomposition ONLY: the same public production operations, then
    // full parity against prepareTransactionNote. Never used by sync/storage.
    final core = m.run(
      'core_initialize_configured_policy',
      () => SynoballCore(
        initialState: before.synoballState!,
        categoryPolicy: before.classification.policy,
        ids: CommandIds('profile-baseline'),
        clock: () => time,
      ),
    );
    final displayed = before.transactions.firstWhere(
      (t) => t.id == 'container-tx-0',
    );
    m.run(
      'core_update',
      () => applyQestoTransactionEdit(
        core,
        displayed.copyWith(comment: 'synthetic performance'),
        actorId: before.user.id,
        displayed: displayed,
      ),
    );
    final projection = m.run(
      'legacy_projection',
      () => const QestoReadModelService().build(core.state),
    );
    final projected = m.run(
      'sber_projection_policy',
      () => projectSberTransactions(
        projection.transactions,
        before.classification.policy,
      ).toList(),
    );
    final after = before.copyWith(
      accounts: projection.accounts,
      transactions: projected,
      synoballState: core.state,
    );
    final encoded = m.run('codec_encode', () => codec.encode(after));
    final oracle = prepareTransactionNote(
      before,
      'container-tx-0',
      'synthetic performance',
      ids: CommandIds('profile-baseline'),
      clock: () => time,
    );
    if (codec.encode(oracle.data) != encoded)
      throw StateError('Profiling decomposition parity');
    final prev = {for (final t in before.synoballState!.transactions) t.id: t};
    final changed = m.run(
      'canonical_entities_diff',
      () => [
        for (final t in core.state.transactions)
          if (canonicalJson(prev[t.id]!.toJson()) != canonicalJson(t.toJson()))
            t.id,
      ],
    );
    m.run(
      'core_hash_before',
      () => digest(canonicalJson(before.synoballState!.toJson())),
    );
    m.run('core_hash_after', () => digest(canonicalJson(core.state.toJson())));
    final dir = createSpikeDirectory();
    const partition = Partition(
      'synthetic-profile-stage4c',
      'synthetic-epoch-stage4c',
    );
    final snapshot = FinancialSnapshot(source);
    final store = await SqliteContainer.migrate(
      dir.path,
      MigrationManifest('baseline', partition, snapshot.hash),
      snapshot,
    );
    try {
      final watch = Stopwatch()..start(), cpu = cpuMicros();
      await store.commitMutation(
        Mutation(
          id: 'profile-baseline',
          partition: partition,
          expectedRevision: 0,
          snapshot: FinancialSnapshot(encoded),
          intentJson: '{"kind":"synthetic-profile"}',
        ),
      );
      runs.add({
        'count': count,
        'input_bytes': bytes,
        'changed_canonical_ids': changed,
        'phases': m.values,
        'sqlite_commit_wall_us': watch.elapsedMicroseconds,
        'sqlite_commit_cpu_us': cpuMicros() - cpu,
        'db_bytes': File(store.path).lengthSync(),
        'wal_bytes': fileBytes('${store.path}-wal'),
        'peak_rss_bytes': ProcessInfo.maxRss,
        'decomposition_full_parity': true,
      });
    } finally {
      await store.close();
    }
    File('results/profile-baseline.json').writeAsStringSync(
      jsonEncode({
        'mode': 'Dart JIT native harness; NOT Flutter baseline comparison',
        'runs': runs,
      }),
    );
    stdout.writeln(
      'Profiled $count; ${bytes ~/ 1024} KiB; ${changed.length} changed entities',
    );
  }
}
