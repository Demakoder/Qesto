import 'dart:convert';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/synthetic_trace.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as wire;
import 'package:qesto_windows_boundary_experiment/note_sync_binding.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_note_driver.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_coordinator_domain.dart';
import 'prepared_commit.dart';

final class EffectsDriverFactory implements SyntheticNoteDriverFactory {
  const EffectsDriverFactory({this.boundedLifetime = false});
  final bool boundedLifetime;
  @override
  Future<SyntheticNoteDriver> open(
    SqliteContainer store,
    NoteSyncBinding? sync,
  ) async {
    if (boundedLifetime) store.setReadCacheBudgetForExperiment(64 * 1024 * 1024);
    final snapshot = await store.readSnapshot();
    final user = SyntheticTrace.sync('driver.identity-decode', () => const UserFinancialDataCodec().decode(snapshot.value.json).user.id);
    // Existing domain admission validates synthetic entity/source ownership.
    final policy = SyntheticTrace.sync('driver.policy-binding', () => const QestoNoteExecutor().policyDigest(
      snapshot.value.json,
      user,
    ));
    if (sync != null &&
        (sync.domain is! QestoCoordinatorDomain ||
            (sync.domain as QestoCoordinatorDomain).policyDigest != policy ||
            sync.principal.user != user)) {
      throw const NoteBoundaryFailure('effects-domain-binding');
    }
    return _Driver(store, await DurableEffectsOwner.load(store), policy,
        boundedLifetime ? sync : null);
  }
}

final class _Driver implements SyntheticNoteDriver, SyntheticRemoteLifetime {
  _Driver(this.store, this.owner, this.policy, this.lifetimeBinding);
  final SqliteContainer store;
  final DurableEffectsOwner owner;
  final String policy;
  final NoteSyncBinding? lifetimeBinding;
  String? _remoteGuard;
  @override
  final Map<String, int> lifetimeMetrics = {'reused': 0, 'readmitted': 0};

  Future<String> _guard() async {
    final binding = lifetimeBinding!;
    store.verify(); // Includes chunks, receipts, command bodies and recovery floor.
    final state = await store.readSnapshot(), context = await store.readRemoteContext();
    if (context == null) throw const NoteBoundaryFailure('missing-sync-context');
    final m = wire.object(jsonDecode(context.json));
    binding.domain.validateHeader(m);
    if (m['device'] != binding.principal.device ||
        m['owner'] != binding.principal.user || m['format'] != 1 ||
        m['workspace'] != store.partition.workspace ||
        binding.principal.workspace != store.partition.workspace ||
        m['epoch'] != store.partition.lineage) {
      throw const NoteBoundaryFailure('lifetime-identity-mismatch');
    }
    // Hash-only guard. Never retain a second profile or reuse by cursor alone.
    // Include delivery/receipt/coverage and all recovery metadata, even for
    // acknowledged commands no longer returned by readPendingCommands().
    return digest(canonicalJson({
      'partition': store.partition.key, 'device': binding.principal.device,
      'user': binding.principal.user, 'ownerGeneration': owner.generation,
      'storageGeneration': store.generation, 'policy': policy,
      'profile': QestoNoteExecutor.profile, 'context': context.json,
      'revision': state.revision, 'snapshot': state.value.hash,
      'shadow': context.shadow.hash,
      for (final table in ['journal', 'commands', 'delivery', 'receipts',
        'checkpoint', 'aliases', 'conflicts', 'bundles', 'migration'])
        table: [for (final row in store.raw.select('SELECT * FROM $table ORDER BY 1'))
          Map<String, Object?>.from(row)],
    }));
  }

  @override
  Future<void> beginRemote() async {
    _delta = null;
    if (_unknown) throw const NoteBoundaryFailure('effects-owner-recovery-required', outcomeUnknown: true);
    if (lifetimeBinding == null) { invalidate(); return; }
    if (owner.status == EffectsOwnerStatus.invalidated) await owner.reloadAfterRemote();
    owner.suspendForRemote();
    try { _remoteGuard = await _guard(); }
    catch (_) { invalidate(); rethrow; }
  }

  @override
  Future<void> completeRemote() async {
    if (lifetimeBinding == null) {
      await reload();
      lifetimeMetrics['readmitted'] = lifetimeMetrics['readmitted']! + 1;
      return;
    }
    final before = _remoteGuard;
    _remoteGuard = null;
    try {
      if (before != null && before == await _guard() &&
          owner.resumeUnchangedAfterRemote(await store.readSnapshot())) {
        lifetimeMetrics['reused'] = lifetimeMetrics['reused']! + 1;
        return;
      }
      invalidate();
      await reload();
      lifetimeMetrics['readmitted'] = lifetimeMetrics['readmitted']! + 1;
    } catch (_) { invalidate(); rethrow; }
  }
  CommittedTransactionNoteDelta? _delta;
  bool _unknown = false;
  @override
  Future<CommandReceipt> commit(
    wire.NoteCommand command,
    VersionedSnapshot before,
    DateTime time,
    Future<void> Function()? beforeCommit,
  ) async {
    if (_unknown)
      throw const NoteBoundaryFailure(
        'effects-owner-recovery-required',
        outcomeUnknown: true,
      );
    if (owner.status == EffectsOwnerStatus.invalidated)
      await owner.reloadAfterRemote();
    if (owner.revision != before.revision ||
        command.workspace != store.partition.workspace ||
        command.epoch != store.partition.lineage)
      throw const NoteBoundaryFailure('effects-stale-owner');
    try {
      final prepared = owner.prepare(
        commandId: command.changeId,
        target: command.target,
        note: command.note,
        time: time.toUtc(),
      );
      final committed = await owner.commit(
        prepared,
        beforeCommit: beforeCommit,
        intentJson: jsonEncode({
          'wire': command.body,
          'financial_profile': QestoNoteExecutor.profile,
          'policy_digest': policy,
          'executed_at': time.toUtc().toIso8601String(),
        }),
      );
      _delta = CommittedTransactionNoteDelta(
        commandId: committed.commandId,
        userId: committed.userId,
        baseRevision: committed.baseRevision,
        revision: committed.revision,
        identity: committed.identity,
        coreWrites: committed.coreWrites,
        projections: [
          for (final w in committed.appEffects.writes)
            NoteProjectionChange(
              w.collection,
              w.index,
              jsonEncode(w.before),
              jsonEncode(w.after),
            ),
        ],
        timings: committed.timings,
      );
      return (await store.lookupCommandReceipt(command.changeId))!;
    } on EffectsOwnerFailure catch (e) {
      _unknown = e.outcomeUnknown;
      throw NoteBoundaryFailure(e.code, outcomeUnknown: e.outcomeUnknown);
    }
  }

  @override
  CommittedTransactionNoteDelta? takeDelta(String commandId) {
    final value = _delta;
    _delta = null;
    return value?.commandId == commandId ? value : null;
  }

  @override
  void invalidate({bool outcomeUnknown = false}) {
    _unknown |= outcomeUnknown;
    _remoteGuard = null;
    _delta = null;
    owner.invalidate('host-lifecycle');
  }

  @override
  Future<void> reload() async {
    if (_unknown)
      throw const NoteBoundaryFailure(
        'effects-owner-recovery-required',
        outcomeUnknown: true,
      );
    await owner.reloadAfterRemote();
  }
}

/// Only this explicit wrapper enables BudgetController's delta branch.
/// Existing WindowsNoteBoundary and production controller defaults stay full.
final class EffectsNoteBoundary
    implements TransactionNoteDeltaBoundary, TransactionNoteSyncBoundary {
  EffectsNoteBoundary(this.inner);
  final WindowsNoteBoundary inner;
  int lastDeltaBytes = 0,
      lastRoundTripMicros = 0,
      fullReloads = 0,
      lastHandoffMicros = 0;
  Map<String, int> lastTimings = const {};
  @override
  Future<CommittedTransactionNoteDelta?> commitDelta(
    TransactionNoteIntent intent, {
    NoteCancellation? cancellation,
  }) async {
    final watch = Stopwatch()..start();
    final value = await inner.commitDeltaForExperiment(
      intent,
      cancellation: cancellation,
    );
    lastRoundTripMicros = watch.elapsedMicroseconds;
    lastHandoffMicros = inner.lastReplyHandoffMicros;
    if (value != null) {
      lastTimings = value.timings;
      lastDeltaBytes = utf8
          .encode(
            jsonEncode({
              'command': value.commandId,
              'revision': value.revision,
              'base': value.baseRevision,
              'identity': value.identity,
              'user': value.userId,
              'core': value.coreWrites.map((w) => w.toJson()).toList(),
              'app': [
                for (final w in value.projections)
                  {
                    'collection': w.collection,
                    'index': w.index,
                    'before': w.beforeJson,
                    'after': w.afterJson,
                  },
              ],
            }),
          )
          .length;
    }
    return value;
  }

  @override
  Future<CommittedTransactionNote> loadCommittedState() {
    fullReloads++;
    return inner.load();
  }

  @override
  Future<CommittedTransactionNote> commitNote(
    TransactionNoteIntent intent, {
    NoteCancellation? cancellation,
  }) => inner.commitNote(intent, cancellation: cancellation);
  @override
  Future<SynchronizedTransactionNotes> synchronize({bool pushPending = true}) =>
      inner.synchronize(pushPending: pushPending);
  @override
  Future<void> close({bool cancelPending = false}) =>
      inner.close(cancelPending: cancelPending);
}
