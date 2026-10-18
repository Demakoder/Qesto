import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as wire;
import 'note_sync_binding.dart';

/// Additive worker-only opt-in. Normal WindowsNoteBoundary has no driver.
abstract interface class SyntheticNoteDriverFactory {
  Future<SyntheticNoteDriver> open(
    SqliteContainer store,
    NoteSyncBinding? sync,
  );
}

abstract interface class SyntheticNoteDriver {
  Future<CommandReceipt> commit(
    wire.NoteCommand command,
    VersionedSnapshot before,
    DateTime time,
    Future<void> Function()? beforeCommit,
  );
  CommittedTransactionNoteDelta? takeDelta(String commandId);
  void invalidate({bool outcomeUnknown = false});
  Future<void> reload();
}

/// Optional Stage 4g lifecycle. The worker still serializes all requests.
/// A failed remote operation must invalidate, never resume an unverified owner.
abstract interface class SyntheticRemoteLifetime {
  Future<void> beginRemote();
  Future<void> completeRemote();
  Map<String, int> get lifetimeMetrics;
}
