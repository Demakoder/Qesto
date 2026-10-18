part of 'prepared_commit.dart';

enum EffectsOwnerStatus {
  ready,
  prepared,
  committing,
  remoteValidation,
  invalidated,
  outcomeUnknown,
  closed,
}

final class EffectsOwnerFailure implements Exception {
  const EffectsOwnerFailure(this.code, {this.outcomeUnknown = false});
  final String code;
  final bool outcomeUnknown;
  @override
  String toString() => 'EffectsOwner: $code';
}

/// Publication data is immutable and does not contain the full profile/core.
/// This is a trusted in-process transport, NOT a client/server acceptance proof.
final class CommittedEffectsDelta {
  CommittedEffectsDelta._(
    PreparedFinancialCommit p,
    DurableEffectsReceipt r,
    Map<String, int> timings,
  ) : commandId = r.commandId,
      revision = r.revision,
      baseRevision = p.binding.baseRevision,
      identity = p.identity,
      userId = p.userId,
      workspace = p.binding.workspace,
      lineage = p.binding.lineage,
      coreWrites = List.unmodifiable(p.coreEffects.writes),
      appEffects = p.appEffects,
      timings = Map.unmodifiable(timings);
  final String commandId, identity, userId, workspace, lineage;
  final int baseRevision, revision;
  final List<CoreCollectionEffect> coreWrites;
  final AppProjectionEffects appEffects;
  final Map<String, int> timings;
  Map<String, Object?> toJson() => {
    'contract': 'qesto.committed-ui-delta.v1',
    'commandId': commandId,
    'identity': identity,
    'user': userId,
    'workspace': workspace,
    'lineage': lineage,
    'baseRevision': baseRevision,
    'revision': revision,
    'coreWrites': coreWrites.map((w) => w.toJson()).toList(),
    'app': appEffects.toJson(),
  };
}

/// Exclusive logical owner of one verified container. No production import.
/// The host must serialize remote apply with local commits and then reload.
final class DurableEffectsOwner {
  DurableEffectsOwner._(this._store, this._scope, this._generation,
      this._snapshotHash, this._storageGeneration);
  final SqliteContainer _store;
  NotePreparationScope? _scope;
  PreparedFinancialCommit? _candidate;
  EffectsCommitRequest? _unknownRequest;
  int _generation;
  String _snapshotHash;
  int _storageGeneration;
  EffectsOwnerStatus _status = EffectsOwnerStatus.ready;
  EffectsOwnerStatus get status => _status;
  int get revision => _scope?.revision ?? -1;
  int get generation => _generation;

  static Future<DurableEffectsOwner> load(
    SqliteContainer store, {
    int generation = 0,
  }) async {
    if (store.requiresReopen)
      throw const EffectsOwnerFailure('reopen-required');
    store.verify();
    final state = await store.readSnapshot();
    return DurableEffectsOwner._(
      store,
      SyntheticTrace.sync('owner.admit-total', () => NotePreparationScope.admit(
        state.value.json,
        workspace: store.partition.workspace,
        lineage: store.partition.lineage,
        revision: state.revision,
        generation: generation,
      )),
      generation,
      state.value.hash,
      store.generation,
    );
  }

  PreparedFinancialCommit prepare({
    required String commandId,
    required String target,
    required String note,
    required DateTime time,
  }) {
    if (_status != EffectsOwnerStatus.ready || _scope == null) {
      throw const EffectsOwnerFailure('owner-not-ready');
    }
    // A thrown preparation has no side effects and leaves the admitted state.
    final p = _scope!.prepare(
      commandId: commandId,
      target: target,
      note: note,
      time: time,
    );
    _candidate = p;
    _status = EffectsOwnerStatus.prepared;
    return p;
  }

  void _check(PreparedFinancialCommit p) {
    final scope = _scope;
    if (!identical(p, _candidate) ||
        scope == null ||
        !p.complete ||
        p.binding.generation != _generation ||
        p.binding.baseRevision != scope.revision ||
        p.binding.policyFingerprint != scope.policy ||
        p.binding.workspace != _store.partition.workspace ||
        p.binding.lineage != _store.partition.lineage) {
      throw const EffectsOwnerFailure('stale-or-foreign-candidate');
    }
  }

  Future<CommittedEffectsDelta> commit(
    PreparedFinancialCommit p, {
    String intentJson = '{}',
    Future<void> Function()? beforeCommit,
    Future<void> Function()? afterCommit,
  }) async {
    if (_status != EffectsOwnerStatus.prepared)
      throw const EffectsOwnerFailure('owner-not-prepared');
    _check(p);
    _status = EffectsOwnerStatus.committing;
    var attempted = false;
    final timings = Map<String, int>.of(p.timings);
    try {
      final request = EffectsCommitRequest(
        mutation: Mutation(
          id: p.binding.commandId,
          partition: _store.partition,
          expectedRevision: p.binding.baseRevision,
          snapshot: p.snapshot,
          intentJson: intentJson,
        ),
        effectsJson: p.effectsJson,
        binding: p.bindingJson,
        storageGeneration: _store.generation,
      );
      await beforeCommit?.call();
      _check(p);
      final watch = Stopwatch()..start();
      attempted = true;
      _unknownRequest = request;
      final receipt = await _store.commitEffects(request);
      timings['commit'] = watch.elapsedMicroseconds;
      await afterCommit?.call();
      _check(p);
      watch.reset();
      await _store.verifyEffectsReceipt(receipt, request);
      _check(p); // an invalidation can arrive while verification awaits
      timings['receiptVerification'] = watch.elapsedMicroseconds;
      watch.reset();
      _scope = NotePreparationScope._(
        p._data,
        p.binding.workspace,
        p.binding.lineage,
        receipt.revision,
        ++_generation,
        p._core,
      );
      _candidate = null;
      _unknownRequest = null;
      _snapshotHash = p.snapshot.hash;
      _storageGeneration = _store.generation;
      _status = EffectsOwnerStatus.ready;
      timings['promotion'] = watch.elapsedMicroseconds;
      return CommittedEffectsDelta._(p, receipt, timings);
    } catch (_) {
      _candidate = null;
      _scope = null;
      _generation++;
      _status = attempted
          ? EffectsOwnerStatus.outcomeUnknown
          : EffectsOwnerStatus.invalidated;
      throw EffectsOwnerFailure(
        attempted
            ? 'resolve-same-command-after-safe-reopen'
            : 'candidate-invalidated',
        outcomeUnknown: attempted,
      );
    }
  }

  /// Called BEFORE policy change, restore or authoritative remote apply.
  /// No later candidate result from this generation can be published.
  void invalidate(String reason) {
    if (_status == EffectsOwnerStatus.closed) return;
    _scope = null;
    _candidate = null;
    _generation++;
    if (_status != EffectsOwnerStatus.outcomeUnknown)
      _status = EffectsOwnerStatus.invalidated;
  }

  /// Retains one committed model but makes it unavailable to local preparation.
  /// Only a separately verified, identical complete sync binding may resume it.
  void suspendForRemote() {
    if (_status != EffectsOwnerStatus.ready || _candidate != null ||
        _unknownRequest != null || _scope == null) {
      throw const EffectsOwnerFailure('unsafe-remote-suspension');
    }
    _status = EffectsOwnerStatus.remoteValidation;
  }

  bool resumeUnchangedAfterRemote(VersionedSnapshot verifiedState) {
    if (_status != EffectsOwnerStatus.remoteValidation || _scope == null ||
        _candidate != null || _unknownRequest != null || _store.requiresReopen ||
        _store.generation != _storageGeneration ||
        verifiedState.revision != _scope!.revision ||
        verifiedState.value.hash != _snapshotHash) return false;
    _status = EffectsOwnerStatus.ready;
    return true;
  }

  Future<void> reloadAfterRemote() async {
    if (_status != EffectsOwnerStatus.invalidated || _unknownRequest != null) {
      throw const EffectsOwnerFailure('unsafe-reload');
    }
    final loaded = await load(_store, generation: _generation);
    _scope = loaded._scope;
    _snapshotHash = loaded._snapshotHash;
    _storageGeneration = loaded._storageGeneration;
    _status = EffectsOwnerStatus.ready;
  }

  /// Only after graceful close or full process restart has released native
  /// handles. Never opens another writer itself. A missing command replays the
  /// SAME immutable request (including generation/time), never a newly prepared
  /// body under that ID. Then admission is rebuilt from verified durable state.
  Future<DurableEffectsOwner> resolveAfterSafeReopen(
    SqliteContainer reopened,
  ) async {
    final request = _unknownRequest;
    if (_status != EffectsOwnerStatus.outcomeUnknown ||
        request == null ||
        identical(reopened, _store) ||
        reopened.partition.key != _store.partition.key) {
      throw const EffectsOwnerFailure('safe-reopen-required');
    }
    reopened.verify();
    final found = await reopened.lookupCommandReceipt(request.commandId);
    if (found != null) {
      final receipt = await reopened.resolveEffects(request);
      await reopened.verifyEffectsReceipt(receipt, request);
    } else {
      final snapshot = await reopened.readSnapshot();
      if (snapshot.revision !=
          (jsonDecode(request.bindingJson) as Map)['baseRevision']) {
        throw const EffectsOwnerFailure('unknown-command-state-mismatch');
      }
      final receipt = await reopened.commitEffects(request);
      await reopened.verifyEffectsReceipt(receipt, request);
    }
    final next = await load(reopened, generation: _generation + 1);
    _status = EffectsOwnerStatus.closed;
    _unknownRequest = null;
    return next;
  }
}
