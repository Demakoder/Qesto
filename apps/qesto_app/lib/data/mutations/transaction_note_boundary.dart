import '../models/qesto_models.dart';
import '../../synoball/core/synoball_core.dart';

/// Explicit injection seam. The normal app has no implementation attached.
/// IDs/revisions belong to the caller's durable command, not UI wall-clock time.
class TransactionNoteIntent {
  const TransactionNoteIntent({
    required this.commandId,
    required this.transactionId,
    required this.note,
    required this.expectedRevision,
  });
  final String commandId, transactionId, note;
  final int expectedRevision;
}

class NoteCancellation {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void Function() listen(void Function() listener) {
    if (_cancelled) listener();
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

class CommittedTransactionNote {
  const CommittedTransactionNote({
    required this.commandId,
    required this.revision,
    required this.data,
    required this.preparedCore,
    this.preparationMicros = 0,
    this.commitMicros = 0,
  });
  final String commandId;
  final int revision;
  final UserFinancialData data;
  // Prepared outside UI isolate; publication must not rerun heavy enrichment.
  final SynoballCore preparedCore;
  final int preparationMicros, commitMicros;
}

class NoteBoundaryFailure implements Exception {
  const NoteBoundaryFailure(this.code, {this.outcomeUnknown = false});
  final String code;
  final bool outcomeUnknown;
  @override
  String toString() => 'NoteBoundary: $code';
}

abstract interface class TransactionNoteBoundary {
  Future<CommittedTransactionNote> commitNote(
    TransactionNoteIntent intent, {
    NoteCancellation? cancellation,
  });
  Future<void> close({bool cancelPending = false});
}

enum NoteSyncStatus { localOnly, synchronized, requiresAttention, unavailable }

class SynchronizedTransactionNotes {
  const SynchronizedTransactionNotes(
    this.state,
    this.status,
    this.checkpoint,
    this.pendingCount,
    this.timingsMicros,
  );
  final CommittedTransactionNote state;
  final NoteSyncStatus status;
  final int checkpoint, pendingCount;
  final Map<String, int> timingsMicros;
}

abstract interface class TransactionNoteSyncBoundary
    implements TransactionNoteBoundary {
  Future<SynchronizedTransactionNotes> synchronize({bool pushPending = true});
}

/// Opt-in synthetic local publication. No production repository implements it.
/// JSON strings are immutable codec-v7 record values, not network patches.
class NoteProjectionChange {
  const NoteProjectionChange(
    this.collection,
    this.index,
    this.beforeJson,
    this.afterJson,
  );
  final String collection, beforeJson, afterJson;
  final int index;
}

class CommittedTransactionNoteDelta {
  CommittedTransactionNoteDelta({
    required this.commandId,
    required this.userId,
    required this.baseRevision,
    required this.revision,
    required this.identity,
    required List<CoreCollectionEffect> coreWrites,
    required List<NoteProjectionChange> projections,
    Map<String, int> timings = const {},
  }) : coreWrites = List.unmodifiable(coreWrites),
       projections = List.unmodifiable(projections),
       timings = Map.unmodifiable(timings);
  final String commandId, userId, identity;
  final int baseRevision, revision;
  final List<CoreCollectionEffect> coreWrites;
  final List<NoteProjectionChange> projections;
  final Map<String, int> timings;
}

abstract interface class TransactionNoteDeltaBoundary
    implements TransactionNoteBoundary {
  Future<CommittedTransactionNoteDelta?> commitDelta(
    TransactionNoteIntent intent, {
    NoteCancellation? cancellation,
  });
  // A null delta or mismatching presentation baseline requires this safe result.
  Future<CommittedTransactionNote> loadCommittedState();
}
