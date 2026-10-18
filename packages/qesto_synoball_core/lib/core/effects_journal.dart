part of 'synoball_core.dart';

/// Experimental local binding, NOT a storage receipt or a network protocol.
/// Revision/policy authority is checked by the domain owner, not the core.
class CoreEffectsBinding {
  CoreEffectsBinding({
    required this.commandId,
    required this.workspace,
    required this.lineage,
    required this.target,
    required this.kind,
    required this.baseRevision,
    required this.generation,
    required this.policyFingerprint,
    this.domainVersion = SynoballState.currentModelVersion,
  }) {
    if ([
          commandId,
          workspace,
          lineage,
          kind,
          policyFingerprint,
        ].any((s) => s.isEmpty) ||
        baseRevision < 0 ||
        generation < 0 ||
        domainVersion != SynoballState.currentModelVersion) {
      throw ArgumentError('Invalid experimental core effects binding');
    }
  }
  final String commandId, workspace, lineage, target, kind;
  final String policyFingerprint, domainVersion;
  final int baseRevision, generation;
  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'workspace': workspace,
    'lineage': lineage,
    'target': target,
    'kind': kind,
    'baseRevision': baseRevision,
    'revision': baseRevision + 1,
    'generation': generation,
    'policyFingerprint': policyFingerprint,
    'domainVersion': domainVersion,
  };
}

/// One ordered collection write. Values are detached, deeply read-only JSON.
/// Index + expected value preserve exact list order (including duplicate IDs).
/// A deleted transaction is an update carrying its tombstone, not a row delete.
class CoreCollectionEffect {
  CoreCollectionEffect._(this.collection, this.index, this.before, this.after);
  final String collection;
  final int index;
  final Map<String, dynamic>? before, after;
  String get kind => before == null
      ? 'created'
      : after == null
      ? 'deleted'
      : 'updated';
  String get id => (after ?? before)!['id'] as String;
  List<String> get changedFields => List.unmodifiable(
    {
      ...?before?.keys,
      ...?after?.keys,
    }.where((k) => !_jsonEqual(before?[k], after?[k])),
  );
  Map<String, Object?> toJson() => {
    'collection': collection,
    'index': index,
    'kind': kind,
    'id': id,
    'before': before,
    'after': after,
    'changedFields': changedFields,
  };
}

class CoreEffectsJournal {
  CoreEffectsJournal._(
    this.binding,
    List<CoreCollectionEffect> writes,
    this.configuredPolicy,
    this.policyChangedDuringExecution,
    this.recordingMicros,
  ) : writes = List.unmodifiable(writes);
  static const version = 1;
  final CoreEffectsBinding binding;
  final List<CoreCollectionEffect> writes;
  final Map<String, dynamic> configuredPolicy;
  final bool policyChangedDuringExecution;
  final int recordingMicros;
  // Completeness is limited to the 15 persisted core collections and policy
  // supplied to this experimental execution. Never covers app/DB/UI effects.
  bool get coreCollectionsComplete => true;
  Set<String> get changedCanonicalIds => Set.unmodifiable(
    writes.where((e) => e.collection == 'transactions').map((e) => e.id),
  );
  Set<String> get changedCollections =>
      Set.unmodifiable(writes.map((e) => e.collection));
  Map<String, Object?> toJson() => {
    'contract': 'qesto.experimental-core-effects.v1',
    'version': version,
    'binding': binding.toJson(),
    'coverage': 'core-collections-only',
    'coreCollectionsComplete': coreCollectionsComplete,
    'configuredPolicy': configuredPolicy,
    'policyChangedDuringExecution': policyChangedDuringExecution,
    'writes': writes.map((e) => e.toJson()).toList(growable: false),
    'invalidations': writes.isNotEmpty || policyChangedDuringExecution
        ? [
            'core-read-model',
            'recurring',
            'app-projections-require-full-fallback',
          ]
        : <String>[],
  };
}

/// An isolated synchronous preparation using the existing core methods.
/// Not durable and not connected to the Sync Coordinator. The callback is local
/// trusted code, not a command parser: command authorization stays upstream.
class CoreJournalPreparation {
  CoreJournalPreparation._(this._core, this.journal);
  final SynoballCore _core;
  final CoreEffectsJournal journal;
  SynoballState get state => _core.state;

  static CoreJournalPreparation fromState({
    required SynoballState initialState,
    required CategoryPolicy policy,
    required CoreEffectsBinding binding,
    required SynoballIdFactory ids,
    required DateTime Function() clock,
    required Object? Function(SynoballCore core) execute,
  }) {
    if (initialState.schemaVersion != SynoballState.currentSchemaVersion ||
        initialState.modelVersion != SynoballState.currentModelVersion) {
      throw StateError('Unsupported core journal version; use full path');
    }
    final recorder = _JournalRecorder(binding);
    try {
      final core = SynoballCore._(
        initialState: initialState,
        categoryPolicy: _ownPolicy(policy),
        ids: ids,
        clock: clock,
        recorder: recorder,
      );
      return _run(core, recorder, execute);
    } catch (_) {
      recorder.abort();
      rethrow;
    }
  }

  /// Reuses deeply immutable records; list/index containers are still copied.
  /// The caller must establish durable revision/generation/policy authority.
  /// This API does not assert that this preparation has ever been committed.
  CoreJournalPreparation prepareNext({
    required CoreEffectsBinding binding,
    required SynoballIdFactory ids,
    required DateTime Function() clock,
    required Object? Function(SynoballCore core) execute,
  }) {
    final old = journal.binding;
    if (journal.policyChangedDuringExecution ||
        binding.workspace != old.workspace ||
        binding.lineage != old.lineage ||
        binding.policyFingerprint != old.policyFingerprint ||
        binding.domainVersion != old.domainVersion ||
        binding.baseRevision != old.baseRevision + 1 ||
        binding.generation != old.generation + 1 ||
        binding.commandId == old.commandId) {
      throw StateError('Stale/foreign prepared binding; reload verified state');
    }
    final recorder = _JournalRecorder(binding);
    try {
      final core = SynoballCore._preparedFork(_core, ids, clock, recorder);
      return _run(core, recorder, execute);
    } catch (_) {
      recorder.abort();
      rethrow;
    }
  }

  static CoreJournalPreparation _run(
    SynoballCore core,
    _JournalRecorder recorder,
    Object? Function(SynoballCore) execute,
  ) {
    final beforePolicy = _policyJson(core._enrichment.categoryPolicy);
    final result = execute(core);
    // Async callbacks can retain the core. Sealing below makes late writes fail.
    if (result is Future)
      throw StateError('Journal preparation must be synchronous');
    return CoreJournalPreparation._(
      core,
      recorder.finish(
        beforePolicy,
        _policyJson(core._enrichment.categoryPolicy),
      ),
    );
  }
}

/// Presentation-only opt-in seam for an already verified local durable delta.
/// NOT a financial command executor, remote patch endpoint or receipt verifier.
/// Host must check its revision/lifecycle and the durable owner before calling.
/// A differing UI baseline fails closed and requires the existing full reload.
extension VerifiedNotePresentation on SynoballCore {
  SynoballCore forkForVerifiedNotePresentation(
    List<CoreCollectionEffect> writes,
  ) {
    if (_recorder != null)
      throw StateError('Sealed preparation is not a UI owner');
    final next = SynoballCore._preparedFork(this, _ids, _clock);
    void apply<T extends Object>(
      List<T> values,
      CoreCollectionEffect w,
      T Function(Map<String, dynamic>) parse,
    ) {
      if (w.before == null) {
        if (w.index != values.length || w.after == null)
          throw StateError('UI append mismatch');
        values.add(_ownRecord(parse(w.after!)));
      } else {
        if (w.index < 0 ||
            w.index >= values.length ||
            !_jsonEqual(_recordJson(values[w.index]), w.before)) {
          throw StateError(
            'UI baseline differs; full verified reload required',
          );
        }
        if (w.after == null) {
          values.removeAt(w.index);
        } else {
          values[w.index] = _ownRecord(parse(w.after!));
        }
      }
    }

    for (final w in writes) {
      switch (w.collection) {
        case 'transactions':
          if (w.before == null ||
              w.after == null ||
              w.before!['id'] != w.after!['id']) {
            throw StateError('Unsupported structural note projection');
          }
          apply(next._transactions, w, CanonicalTransaction.fromJson);
        case 'recurringStreams':
          apply(next._recurringStreams, w, RecurringStream.fromJson);
        case 'events':
          apply(next._events, w, SynoballEvent.fromJson);
        case 'auditEntries':
          apply(next._auditEntries, w, SynoballAuditEntry.fromJson);
        default:
          throw StateError('Unsupported note projection collection');
      }
    }
    return next;
  }
}

class _JournalRecorder {
  _JournalRecorder(this.binding);
  final CoreEffectsBinding binding;
  final _writes = <CoreCollectionEffect>[];
  final _slots = <(String, int), int>{};
  bool _open = true;
  int _micros = 0;
  void requireOpen() {
    if (!_open) throw StateError('Prepared scope is sealed or aborted');
  }

  void write(String collection, int index, Object? before, Object? after) {
    requireOpen();
    if (identical(before, after)) return;
    final watch = Stopwatch()..start();
    final a = before == null ? null : _recordJson(before);
    final b = after == null ? null : _recordJson(after);
    if (!_jsonEqual(a, b)) {
      // Collapse repeated writes to the same slot. No scan of unchanged records.
      // Structural removals invalidate slots because subsequent indexes shift.
      if (after == null) _slots.removeWhere((key, _) => key.$1 == collection);
      final prior = after == null ? null : _slots[(collection, index)];
      final effect = CoreCollectionEffect._(
        collection,
        index,
        a == null ? null : _freezeJson(a) as Map<String, dynamic>,
        b == null ? null : _freezeJson(b) as Map<String, dynamic>,
      );
      if (prior != null) {
        final first = _writes[prior];
        _writes[prior] = CoreCollectionEffect._(
          collection,
          index,
          first.before,
          effect.after,
        );
      } else {
        if (after != null) _slots[(collection, index)] = _writes.length;
        _writes.add(effect);
      }
    }
    _micros += watch.elapsedMicroseconds;
  }

  CoreEffectsJournal finish(
    Map<String, dynamic> beforePolicy,
    Map<String, dynamic> policy,
  ) {
    requireOpen();
    _open = false;
    final result = CoreEffectsJournal._(
      binding,
      _writes.where((e) => !_jsonEqual(e.before, e.after)).toList(),
      _freezeJson(policy) as Map<String, dynamic>,
      !_jsonEqual(beforePolicy, policy),
      _micros,
    );
    _writes.clear();
    _slots.clear();
    return result;
  }

  void abort() {
    _open = false;
    _writes.clear();
    _slots.clear();
  }
}

List<T> _ownedList<T>(
  String name,
  Iterable<T> values,
  _JournalRecorder? recorder, {
  bool trusted = false,
}) => recorder == null
    ? List.of(values)
    : _JournalList(name, values, recorder, trusted: trusted);

/// All list mutations funnel through these primitives, including upsert helpers.
/// No full-profile comparison here. In-place nested writes are forbidden by the
/// opt-in ownership boundary; default production models are not modified.
class _JournalList<T> extends ListBase<T> {
  _JournalList(
    this.name,
    Iterable<T> values,
    this.recorder, {
    required bool trusted,
  }) : _values = trusted ? List.of(values) : values.map(_ownRecord<T>).toList();
  final String name;
  final _JournalRecorder recorder;
  final List<T> _values;
  @override
  int get length => _values.length;
  @override
  set length(int size) {
    recorder.requireOpen();
    if (size < 0 || size > length)
      throw UnsupportedError('Journal list cannot grow with nulls');
    while (length > size) {
      removeAt(length - 1);
    }
  }

  @override
  T operator [](int index) => _values[index];
  @override
  void operator []=(int index, T value) {
    recorder.requireOpen();
    final owned = _ownRecord(value);
    recorder.write(name, index, _values[index], owned);
    _values[index] = owned;
  }

  @override
  void add(T value) {
    recorder.requireOpen();
    final owned = _ownRecord(value);
    recorder.write(name, length, null, owned);
    _values.add(owned);
  }

  @override
  void addAll(Iterable<T> values) {
    for (final value in values) {
      add(value);
    }
  }

  @override
  T removeAt(int index) {
    recorder.requireOpen();
    final value = _values[index];
    recorder.write(name, index, value, null);
    return _values.removeAt(index);
  }

  @override
  void clear() {
    length = 0;
  }

  void replaceContents(List<T> incoming) {
    final common = length < incoming.length ? length : incoming.length;
    for (var i = 0; i < common; i++) {
      this[i] = incoming[i];
    }
    if (length > incoming.length) length = incoming.length;
    for (var i = common; i < incoming.length; i++) {
      add(incoming[i]);
    }
  }

  @override
  void removeWhere(bool Function(T) test) {
    // Keep predicate evaluation order identical to the standard list.
    final indexes = <int>[];
    for (var i = 0; i < length; i++) {
      if (test(this[i])) indexes.add(i);
    }
    for (final i in indexes.reversed) {
      removeAt(i);
    }
  }
}

bool _jsonEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  // JSON 1 and 1.0 are distinct serialized payloads even though Dart == agrees.
  if (a is num && b is num) return a.runtimeType == b.runtimeType && a == b;
  if (a is Map && b is Map)
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _jsonEqual(a[k], b[k]));
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Object? _freezeJson(Object? value) {
  if (value is num && !value.isFinite) {
    throw StateError('Non-finite JSON value at journal boundary');
  }
  if (value is Map)
    return Map<String, dynamic>.unmodifiable({
      for (final e in value.entries) e.key as String: _freezeJson(e.value),
    });
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeJson));
  if (value == null || value is String || value is num || value is bool)
    return value;
  throw StateError('Unsupported non-JSON journal value');
}
