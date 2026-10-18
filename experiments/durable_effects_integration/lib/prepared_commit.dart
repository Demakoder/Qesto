import 'dart:convert';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/synoball/analytics/qesto_read_model.dart';
import 'package:qesto/features/transaction_import/services/sber_transaction_projection.dart';
import 'package:qesto_core_effects_experiment/app_probe.dart' as app;
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/synthetic_trace.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';

part 'durable_owner.dart';

const _codec = UserFinancialDataCodec();
const invalidations = [
  'transaction-details',
  'budget',
  'cash-flow',
  'spending',
  'capital',
  'recurring',
  'audit',
  'analytics',
];

Object? freeze(Object? value) => switch (value) {
  Map m => Map<String, dynamic>.unmodifiable({
    for (final k in m.keys) k as String: freeze(m[k]),
  }),
  List l => List<Object?>.unmodifiable(l.map(freeze)),
  null || String() || bool() || int() => value,
  double n when n.isFinite => n,
  _ => throw StateError('Unsupported effect value'),
};

enum ProjectionCoverage { complete, requiresDerivedRebuild, unsupported }

final class ProjectionWrite {
  ProjectionWrite._(
    this.collection,
    this.index,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) : before = freeze(before) as Map<String, dynamic>,
      after = freeze(after) as Map<String, dynamic>;
  final String collection;
  final int index;
  final Map<String, dynamic> before, after;
  String get id => after['id'] as String;
  Map<String, Object?> toJson() => {
    'collection': collection,
    'index': index,
    'id': id,
    'before': before,
    'after': after,
  };
}

final class AppProjectionEffects {
  AppProjectionEffects._(Iterable<ProjectionWrite> writes)
    : writes = List.unmodifiable(writes);
  final List<ProjectionWrite> writes;
  // The persisted projection is complete, derived selectors must invalidate.
  ProjectionCoverage get coverage => ProjectionCoverage.requiresDerivedRebuild;
  Map<String, Object?> toJson() => {
    'contract': 'qesto.note-app-effects.v1',
    'coverage': coverage.name,
    'unknownDependencies': <String>[],
    'invalidations': invalidations,
    'writes': writes.map((w) => w.toJson()).toList(),
  };
}

/// A detached immutable candidate, not evidence of SQLite COMMIT.
/// The only mutable app models stay private to this library/owner.
final class PreparedFinancialCommit {
  PreparedFinancialCommit._(
    this._data,
    this._core,
    this.appEffects,
    this.snapshot,
    this.userId,
    Map<String, int> timings,
  ) : timings = Map.unmodifiable(timings);
  final UserFinancialData _data;
  final CoreJournalPreparation _core;
  final AppProjectionEffects appEffects;
  final FinancialSnapshot snapshot;
  final String userId;
  final Map<String, int> timings;
  CoreEffectsJournal get coreEffects => _core.journal;
  CoreEffectsBinding get binding => coreEffects.binding;
  bool get complete =>
      coreEffects.coreCollectionsComplete &&
      !coreEffects.policyChangedDuringExecution;
  late final String effectsJson = canonicalJson({
    'contract': 'qesto.prepared-financial-commit.v1',
    'user': userId,
    'core': coreEffects.toJson(),
    'app': appEffects.toJson(),
  });
  late final String effectsDigest = digest(effectsJson);
  late final String identity = digest(
    canonicalJson({'effects': effectsDigest, 'snapshot': snapshot.hash}),
  );
  Map<String, Object?> get bindingJson => Map.unmodifiable({
    ...binding.toJson(),
    'user': userId,
    'effectsDigest': effectsDigest,
    'preparedIdentity': identity,
    'snapshotDigest': snapshot.hash,
    'coverage': 'core-and-app-note-v1',
  });
}

/// Admission pays one full projection comparison. Subsequent preparations only
/// project journal-affected records. No global diff is used per command.
/// This class does NOT accept/publish candidates: durable ownership is Gate C.
final class NotePreparationScope {
  NotePreparationScope._(
    this._before,
    this.workspace,
    this.lineage,
    this.revision,
    this.generation,
    this._prior,
  ) {
    final state = _before.synoballState;
    if (!_before.user.id.startsWith('synthetic-4a-') ||
        state == null ||
        !workspace.startsWith('synthetic-') ||
        lineage.isEmpty) {
      throw StateError('Synthetic scope required');
    }
    policy = digest(canonicalJson(_before.classification.toJson()));
    _positions = {
      for (var i = 0; i < _before.transactions.length; i++)
        _before.transactions[i].id: i,
    };
    if (_positions.length != _before.transactions.length ||
        state.transactions.map((t) => t.id).toSet().length !=
            state.transactions.length) {
      throw StateError('Unsupported duplicate identity: full path required');
    }
    if (_prior == null) SyntheticTrace.sync('owner.admit-projections', _admitProjections);
  }

  /// Owns a codec-detached copy, never aliases the caller's mutable model lists.
  factory NotePreparationScope.admit(
    String json, {
    required String workspace,
    required String lineage,
    required int revision,
    required int generation,
  }) => NotePreparationScope._(
    SyntheticTrace.sync('owner.codec-decode', () => _codec.decode(json)),
    workspace,
    lineage,
    revision,
    generation,
    null,
  );

  /// Test sequencing only. Production promotion must be owned by Gate C.
  /// Not a receipt and never wired to controller or storage.
  factory NotePreparationScope.oracleSequence(PreparedFinancialCommit prior) =>
      NotePreparationScope._(
        prior._data,
        prior.binding.workspace,
        prior.binding.lineage,
        prior.binding.baseRevision + 1,
        prior.binding.generation + 1,
        prior._core,
      );

  final UserFinancialData _before;
  final String workspace, lineage;
  final int revision, generation;
  final CoreJournalPreparation? _prior;
  late final String policy;
  late final Map<String, int> _positions;
  final _admissionWrites = <(String, int), ProjectionWrite>{};

  void _admitProjections() {
    final read = const QestoReadModelService().build(_before.synoballState!);
    final tx = projectSberTransactions(
      read.transactions,
      _before.classification.policy,
    ).toList();
    void compare(
      String name,
      List<Map<String, dynamic>> a,
      List<Map<String, dynamic>> b,
    ) {
      if (a.length != b.length)
        throw StateError(
          'Unsupported projection membership: full path required',
        );
      for (var i = 0; i < a.length; i++) {
        if (a[i]['id'] != b[i]['id'])
          throw StateError('Unsupported projection order: full path required');
        if (canonicalJson(a[i]) != canonicalJson(b[i])) {
          _admissionWrites[(name, i)] = ProjectionWrite._(name, i, a[i], b[i]);
        }
      }
    }

    compare(
      'transactions',
      _before.transactions.map(_codec.transactionToJson).toList(),
      tx.map(_codec.transactionToJson).toList(),
    );
    compare(
      'accounts',
      _before.accounts.map(_codec.accountToJson).toList(),
      read.accounts.map(_codec.accountToJson).toList(),
    );
  }

  PreparedFinancialCommit prepare({
    required String commandId,
    required String target,
    required String note,
    required DateTime time,
    String kind = 'transaction.set_note',
  }) {
    if (kind != 'transaction.set_note')
      throw StateError('Unsupported command: full path required');
    final watch = Stopwatch()..start();
    final binding = CoreEffectsBinding(
      commandId: commandId,
      workspace: workspace,
      lineage: lineage,
      target: target,
      kind: kind,
      baseRevision: revision,
      generation: generation,
      policyFingerprint: policy,
    );
    final core = app.prepareNote(
      _before,
      target,
      note,
      binding,
      time,
      prior: _prior,
    );
    final prepareMicros = watch.elapsedMicroseconds;
    if (!core.journal.coreCollectionsComplete ||
        core.journal.policyChangedDuringExecution ||
        core.journal.changedCollections.difference({
          'transactions',
          'events',
          'auditEntries',
          'recurringStreams',
        }).isNotEmpty) {
      throw StateError('Unknown projection dependency: full path required');
    }
    final touched = <CanonicalTransaction>[];
    for (final e in core.journal.writes.where(
      (e) => e.collection == 'transactions',
    )) {
      if (e.before == null ||
          e.after == null ||
          e.before!['id'] != e.after!['id']) {
        throw StateError(
          'Unsupported note structural effect: full path required',
        );
      }
      touched.add(core.state.transactions[e.index]);
    }
    final subset = SynoballState(
      accounts: core.state.accounts,
      receipts: core.state.receipts,
      transactions: touched,
    );
    final projected = projectSberTransactions(
      const QestoReadModelService().build(subset).transactions,
      _before.classification.policy,
    );
    final writes = Map<(String, int), ProjectionWrite>.of(_admissionWrites);
    for (final t in projected) {
      final index = _positions[t.id];
      if (index == null)
        throw StateError(
          'Unsupported projection membership: full path required',
        );
      final before = _codec.transactionToJson(_before.transactions[index]);
      final after = _codec.transactionToJson(t);
      final key = ('transactions', index);
      if (canonicalJson(before) == canonicalJson(after)) {
        writes.remove(key);
      } else {
        writes[key] = ProjectionWrite._('transactions', index, before, after);
      }
    }
    final transactions = List<BudgetTransaction>.of(_before.transactions);
    final accounts = List<QestoAccount>.of(_before.accounts);
    for (final w in writes.values) {
      if (w.collection == 'transactions') {
        transactions[w.index] = _codec.transactionFromJson(w.after);
      } else {
        accounts[w.index] = _codec.accountFromJson(w.after);
      }
    }
    final next = _before.copyWith(
      synoballState: core.state,
      transactions: List.unmodifiable(transactions),
      accounts: List.unmodifiable(accounts),
    );
    final projectionMicros = watch.elapsedMicroseconds - prepareMicros;
    final json = _codec.encode(next);
    final codecMicros =
        watch.elapsedMicroseconds - prepareMicros - projectionMicros;
    return PreparedFinancialCommit._(
      next,
      core,
      AppProjectionEffects._(writes.values),
      FinancialSnapshot(json),
      _before.user.id,
      {
        'domain': prepareMicros,
        'journal': core.journal.recordingMicros,
        'projections': projectionMicros,
        'codec': codecMicros,
      },
    );
  }
}
