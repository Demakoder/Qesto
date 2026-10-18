import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/synthetic_trace.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as wire;
import 'package:qesto_encrypted_sync_experiment/coordinator.dart';
import 'package:qesto_encrypted_sync_experiment/transport.dart';
import 'package:qesto_encrypted_sync_experiment/bootstrap.dart'
    as sync_bootstrap;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto/synoball/core/synoball_core.dart';
import 'synthetic_fixture.dart' show SyntheticBookkeeping, SyntheticIds;
import 'note_sync_binding.dart';
import 'synthetic_note_driver.dart';

/// Explicit synthetic identity. No store discovery, repository or public API.
class SyntheticWindowsProfile {
  const SyntheticWindowsProfile(
    this.directory,
    this.workspace,
    this.device,
    this.epoch,
  );
  final String directory, workspace, device, epoch;
  Partition get partition => Partition(workspace, epoch);
  static SyntheticWindowsProfile create() {
    final dir = createSpikeDirectory();
    final id = DateTime.now().microsecondsSinceEpoch;
    final p = SyntheticWindowsProfile(
      dir.path,
      'synthetic-4a-$id',
      'synthetic-4a-device-$id',
      'synthetic-4a-epoch-$id',
    );
    File(
      '${dir.path}/.qesto-windows-boundary',
    ).writeAsStringSync(p.marker, flush: true);
    return p;
  }

  String get marker => canonicalJson({
    'format': 'synthetic-4a',
    'workspace': workspace,
    'device': device,
    'epoch': epoch,
  });
  void validate() {
    if (![
      workspace,
      device,
      epoch,
    ].every((s) => RegExp(r'^synthetic-4a-[a-zA-Z0-9-]+$').hasMatch(s))) {
      throw const NoteBoundaryFailure('synthetic-identity-required');
    }
    requireOwnedPath('$directory/container.lock');
    final dir = Directory(directory).absolute;
    if (dir.resolveSymbolicLinksSync().toLowerCase() !=
            dir.path.toLowerCase() ||
        File('${dir.path}/.qesto-windows-boundary').readAsStringSync() !=
            marker) {
      throw const NoteBoundaryFailure('synthetic-path-required');
    }
  }
}

enum BoundaryProbe {
  none,
  beforeCommitError,
  afterCommitError,
  beforeCommitGate,
  afterCommitGate,
  closeError,
}

/// One long-lived FIFO owner for core, codec and SQLite. Disabled test adapter.
class WindowsNoteBoundary implements TransactionNoteSyncBoundary {
  WindowsNoteBoundary._(
    this._port,
    this._isolate,
    this._messages,
    this._errors,
    this._exits,
    this._pending,
    this._stages,
  );
  final SendPort _port;
  final Isolate _isolate;
  final ReceivePort _messages, _errors, _exits;
  final Map<int, Completer<Object?>> _pending;
  final StreamController<String> _stages;
  Stream<String> get stages => _stages.stream;
  int _next = 0;
  bool _dead = false, _closing = false;
  // Synthetic diagnostics: wall-clock send -> receive (serialization + queue).
  // Not an isolated VM serialization benchmark or a durability proof.
  int lastReplyHandoffMicros = 0;
  static Future<WindowsNoteBoundary> open(
    SyntheticWindowsProfile profile, {
    String? initialSnapshot,
    BoundaryProbe probe = BoundaryProbe.none,
    SyntheticBookkeeping? bookkeeping,
    NoteSyncBinding? synchronization,
    bool incremental = false,
    SyntheticNoteDriverFactory? effectsDriver,
  }) async {
    profile.validate();
    final messages = ReceivePort(),
        errors = ReceivePort(),
        exits = ReceivePort();
    final ready = Completer<SendPort>(), pending = <int, Completer<Object?>>{};
    final stages = StreamController<String>.broadcast();
    WindowsNoteBoundary? owner;
    void lost() {
      owner?._dead = true;
      if (!ready.isCompleted)
        ready.completeError(
          const NoteBoundaryFailure(
            'worker-start-failed',
            outcomeUnknown: true,
          ),
        );
      for (final c in pending.values.toList()) {
        c.completeError(
          const NoteBoundaryFailure(
            'worker-lost-full-process-restart-required',
            outcomeUnknown: true,
          ),
        );
      }
      pending.clear();
    }

    errors.listen((_) => lost());
    exits.listen((_) {
      if (owner?._closing != true || pending.isNotEmpty) lost();
    });
    messages.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
        return;
      }
      final r = m as List;
      if (r[0] == 'startup-error') {
        if (!ready.isCompleted)
          ready.completeError(NoteBoundaryFailure(r[1] as String));
        return;
      }
      if (r[0] == 'stage') {
        stages.add(r[1] as String);
        return;
      }
      final c = pending.remove(r[0]);
      if (c == null) return;
      if (r[1] == true) {
        if (r.length > 3 && r[3] is int) {
          owner?.lastReplyHandoffMicros =
              DateTime.now().microsecondsSinceEpoch - (r[3] as int);
        }
        c.complete(r[2]);
      } else {
        c.completeError(
          NoteBoundaryFailure(r[2] as String, outcomeUnknown: r[3] as bool),
        );
      }
    });
    final isolate = await Isolate.spawn(
      _worker,
      [
        profile,
        initialSnapshot,
        probe,
        messages.sendPort,
        bookkeeping,
        synchronization,
        incremental,
        effectsDriver,
      ],
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true,
    );
    try {
      final port = await ready.future.timeout(const Duration(seconds: 30));
      return owner = WindowsNoteBoundary._(
        port,
        isolate,
        messages,
        errors,
        exits,
        pending,
        stages,
      );
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      messages.close();
      errors.close();
      exits.close();
      await stages.close();
      rethrow;
    }
  }

  Future<T> _request<T>(
    String op,
    Object? value, {
    NoteCancellation? cancellation,
    bool shutdown = false,
  }) {
    if (_dead || (_closing && !shutdown))
      return Future.error(const NoteBoundaryFailure('owner-closed'));
    if (cancellation?.isCancelled == true)
      return Future.error(const NoteBoundaryFailure('cancelled-before-commit'));
    if (!shutdown && _pending.length >= 16)
      return Future.error(const NoteBoundaryFailure('queue-full'));
    final id = ++_next, c = Completer<Object?>();
    _pending[id] = c;
    _port.send([id, op, value]);
    final unsubscribe = cancellation?.listen(() => _port.send(['cancel', id]));
    return c.future.then((v) => v as T).whenComplete(() => unsubscribe?.call());
  }

  @override
  Future<CommittedTransactionNote> commitNote(
    TransactionNoteIntent intent, {
    NoteCancellation? cancellation,
  }) => _request('note', intent, cancellation: cancellation);
  Future<CommittedTransactionNote> load() => _request('load', null);
  Future<CommittedTransactionNoteDelta?> commitDeltaForExperiment(
    TransactionNoteIntent intent, {
    NoteCancellation? cancellation,
  }) => _request('note-delta', intent, cancellation: cancellation);
  Future<List<PendingCommand>> pending() => _request('pending', null);
  @override
  Future<SynchronizedTransactionNotes> synchronize({bool pushPending = true}) =>
      _request('sync', pushPending);
  // Test diagnostics/actions still use the same sole writer owner.
  Future<void> pushForTest() => _request('push', null);
  Future<Map<String, dynamic>> pageForTest() => _request('page', null);
  Future<bool> applyPageForTest(Map<String, dynamic> page) =>
      _request('apply-page', page);
  Future<Map<String, dynamic>> inspectForTest() => _request('inspect', null);
  void releaseProbe() => _port.send(['release']);

  /// Only exercised inside a child test process. No hot recovery in this process.
  void killWorkerForTest() => _isolate.kill(priority: Isolate.immediate);
  @override
  Future<void> close({bool cancelPending = false}) async {
    if (_closing) throw const NoteBoundaryFailure('shutdown-already-started');
    _closing = true;
    try {
      if (!_dead) await _request<void>('close', cancelPending, shutdown: true);
    } finally {
      _dead = true;
      _port.send(['dispose']);
      _messages.close();
      _errors.close();
      _exits.close();
      await _stages.close();
    }
  }
}

class _Token {
  bool cancelled = false;
}

Future<void> _worker(List<Object?> args) async {
  final profile = args[0] as SyntheticWindowsProfile;
  final initial = args[1] as String?, probe = args[2] as BoundaryProbe;
  final replies = args[3] as SendPort;
  final bookkeeping = args[4] as SyntheticBookkeeping?;
  final synchronization = args[5] as NoteSyncBinding?;
  final incremental = args[6] as bool;
  final factory = args[7] as SyntheticNoteDriverFactory?;
  const codec = UserFinancialDataCodec();
  SqliteContainer store;
  void fault(String stage) {
    if (Platform.environment['QESTO_4A_PROCESS_FAULT'] == stage) exit(86);
    if (probe == BoundaryProbe.beforeCommitError &&
        stage == 'local-before-commit') {
      throw const ContractViolation('synthetic-before-commit');
    }
  }

  try {
    profile.validate();
    if (synchronization != null &&
        (synchronization.principal.workspace != profile.workspace ||
            synchronization.principal.device != profile.device)) {
      throw const NoteBoundaryFailure('sync-client-identity-mismatch');
    }
    if (initial != null) {
      final bootstrapWatch = Stopwatch()..start();
      final data = codec.decode(initial);
      SyntheticTrace.record('worker.bootstrap-decode', bootstrapWatch.elapsedMicroseconds);
      if (!data.user.id.startsWith('synthetic-4a-') ||
          data.synoballState == null) {
        throw const NoteBoundaryFailure('synthetic-canonical-profile-required');
      }
      bootstrapWatch.reset();
      final snapshot = FinancialSnapshot(codec.encode(data));
      SyntheticTrace.record('worker.bootstrap-encode-validate', bootstrapWatch.elapsedMicroseconds);
      if (synchronization != null) {
        if (synchronization.principal.workspace != profile.workspace ||
            synchronization.principal.device != profile.device) {
          throw const NoteBoundaryFailure('sync-client-identity-mismatch');
        }
        final response = synchronization.bootstrapResponse;
        if (response == null || response['workspace_epoch'] != profile.epoch)
          throw const NoteBoundaryFailure('explicit-sync-bootstrap-required');
        bootstrapWatch.reset();
        await sync_bootstrap.bootstrap(
          profile.directory,
          snapshot,
          synchronization.principal,
          response,
          domain: synchronization.domain,
          incremental: incremental,
        );
        SyntheticTrace.record('worker.synthetic-bootstrap', bootstrapWatch.elapsedMicroseconds);
        store = await SqliteContainer.open(
          profile.directory,
          profile.partition,
          fault: fault,
        );
      } else {
        store = await SqliteContainer.migrate(
          profile.directory,
          MigrationManifest(
            'synthetic-4a-initial',
            profile.partition,
            snapshot.hash,
          ),
          snapshot,
          fault: fault,
          incremental: incremental,
        );
      }
    } else {
      store = await SqliteContainer.open(
        profile.directory,
        profile.partition,
        fault: fault,
      );
    }
  } catch (e) {
    replies.send([
      'startup-error',
      e is ContractViolation
          ? e.code
          : e is NoteBoundaryFailure
          ? e.code
          : '${e.runtimeType}',
    ]);
    return;
  }
  final requests = ReceivePort(), tokens = <int, _Token>{};
  final transport = synchronization == null
      ? null
      : LoopbackTransport(synchronization.endpoint, synchronization.principal);
  SyntheticNoteDriver? effects;
  try {
    final admissionWatch = Stopwatch()..start();
    effects = await factory?.open(store, synchronization);
    SyntheticTrace.record('worker.effects-admission', admissionWatch.elapsedMicroseconds);
  } catch (e) {
    await store.close();
    requests.close();
    replies.send(['startup-error', 'effects-admission-${e.runtimeType}']);
    return;
  }
  final coordinator = synchronization == null
      ? null
      : Coordinator(
          store,
          profile.partition,
          synchronization.principal,
          transport!.request,
          domain: synchronization.domain,
          syntheticLocalCommit: effects?.commit,
        );
  if (coordinator != null) {
    try {
      await coordinator.context();
      final snapshot = await store.readSnapshot();
      final identityWatch = Stopwatch()..start();
      final data = codec.decode(snapshot.value.json);
      SyntheticTrace.record('worker.verify-identity-decode', identityWatch.elapsedMicroseconds);
      if (data.user.id != synchronization!.principal.user) {
        throw const NoteBoundaryFailure('sync-profile-owner-mismatch');
      }
    } catch (e) {
      await store.close();
      replies.send([
        'startup-error',
        e is ContractViolation
            ? e.code
            : e is NoteBoundaryFailure
            ? e.code
            : '${e.runtimeType}',
      ]);
      return;
    }
  }
  Future<CommittedTransactionNote> loaded(
    String id, {
    int preparation = 0,
    int commit = 0,
  }) async {
    final s = await store.readSnapshot();
    final data = SyntheticTrace.sync('worker.publication-decode', () => codec.decode(s.value.json));
    return CommittedTransactionNote(
      commandId: id,
      revision: s.revision,
      data: data,
      preparedCore: SyntheticTrace.sync('worker.publication-indexes-policy', () => SynoballCore(
        initialState: data.synoballState!,
        categoryPolicy: data.classification.policy,
      )),
      preparationMicros: preparation,
      commitMicros: commit,
    );
  }

  Completer<void>? gate;
  bool closing = false;
  var tail = Future<void>.value();
  Future<void> waitGate(String stage) async {
    gate = Completer<void>();
    replies.send(['stage', stage]);
    await gate!.future;
    gate = null;
  }

  void check(_Token t) {
    if (t.cancelled) throw const NoteBoundaryFailure('cancelled-before-commit');
  }

  replies.send(requests.sendPort);
  requests.listen((m) {
    final r = m as List;
    if (r[0] == 'dispose') {
      requests.close();
      return;
    }
    if (r[0] == 'release') {
      if (gate?.isCompleted == false) gate!.complete();
      return;
    }
    if (r[0] == 'cancel') {
      tokens[r[1]]?.cancelled = true;
      if (gate?.isCompleted == false) gate!.complete();
      return;
    }
    final id = r[0] as int, op = r[1] as String, token = _Token();
    if (op == 'close') {
      closing = true;
      if (r[2] == true) {
        for (final t in tokens.values) {
          t.cancelled = true;
        }
        if (gate?.isCompleted == false) gate!.complete();
      }
    } else if (closing) {
      replies.send([id, false, 'owner-closing', false]);
      return;
    }
    tokens[id] = token;
    tail = tail.then((_) async {
      var committed = false, commitAttempted = false;
      try {
        Object? result;
        switch (op) {
          case 'pending':
            result = await store.readPendingCommands();
          case 'inspect':
            final context = await store.readRemoteContext(),
                s = await store.readSnapshot();
            result = {
              'revision': s.revision,
              'checkpoint': await store.readCheckpoint(),
              'incremental': store.incremental,
              'storage_metrics': Map.of(store.incrementalMetrics),
              'cache_metrics': store.cacheDiagnostics,
              'lifetime_metrics': effects is SyntheticRemoteLifetime
                  ? Map.of((effects as SyntheticRemoteLifetime).lifetimeMetrics) : null,
              'transport_metrics': transport == null
                  ? null
                  : Map.of(transport.metrics),
              'context': context == null ? null : jsonDecode(context.json),
              'shadow': context == null
                  ? null
                  : jsonDecode(context.shadow.json),
            };
          case 'push':
            if (coordinator == null)
              throw const NoteBoundaryFailure('sync-not-enabled');
            await coordinator.push();
          case 'page':
            if (coordinator == null)
              throw const NoteBoundaryFailure('sync-not-enabled');
            result = await coordinator.page();
          case 'apply-page':
            if (coordinator == null)
              throw const NoteBoundaryFailure('sync-not-enabled');
            if (effects is SyntheticRemoteLifetime) {
              await (effects as SyntheticRemoteLifetime).beginRemote();
            } else { effects?.invalidate(); }
            result = await coordinator.applyPage(wire.object(r[2]));
            await SyntheticTrace.async('worker.owner-readmission', () async {
              if (effects is SyntheticRemoteLifetime) {
                await (effects as SyntheticRemoteLifetime).completeRemote();
              } else { await effects?.reload(); }
            });
          case 'sync':
            if (coordinator == null)
              throw const NoteBoundaryFailure('sync-not-enabled');
            coordinator.timingsMicros.clear();
            if (effects is SyntheticRemoteLifetime) {
              await (effects as SyntheticRemoteLifetime).beginRemote();
            } else { effects?.invalidate(); }
            if (r[2] == true) await coordinator.push();
            await coordinator.pull();
            await SyntheticTrace.async('worker.owner-readmission', () async {
              if (effects is SyntheticRemoteLifetime) {
                await (effects as SyntheticRemoteLifetime).completeRemote();
              } else { await effects?.reload(); }
            });
            final queue = await store.readPendingCommands();
            result = SynchronizedTransactionNotes(
              await loaded(''),
              queue.any((p) => p.receipt.state == DeliveryState.conflict)
                  ? NoteSyncStatus.requiresAttention
                  : queue.isEmpty
                  ? NoteSyncStatus.synchronized
                  : NoteSyncStatus.localOnly,
              await store.readCheckpoint(),
              queue.length,
              Map.of(coordinator.timingsMicros),
            );
          case 'load':
            final s = await store.readSnapshot();
            final data = SyntheticTrace.sync('worker.load-decode', () => codec.decode(s.value.json));
            final core = SyntheticTrace.sync('worker.load-indexes-policy', () => SynoballCore(
              initialState: data.synoballState!,
              categoryPolicy: data.classification.policy,
            ));
            result = CommittedTransactionNote(
              commandId: '',
              revision: s.revision,
              data: data,
              preparedCore: core,
            );
          case 'note':
          case 'note-delta':
            check(token);
            if (op == 'note-delta' && effects == null)
              throw const NoteBoundaryFailure('delta-not-enabled');
            final intent = r[2] as TransactionNoteIntent;
            if (coordinator != null) {
              coordinator.timingsMicros.clear();
              final receipt = await coordinator.edit(
                intent.commandId,
                intent.transactionId,
                intent.note,
                expectedRevision: intent.expectedRevision,
                now: bookkeeping?.now(),
                beforeCommit: () async {
                  await Future<void>.delayed(Duration.zero);
                  if (probe == BoundaryProbe.beforeCommitGate)
                    await waitGate('before-commit');
                  check(token);
                  commitAttempted = true;
                },
              );
              committed = true;
              if (Platform.environment['QESTO_4A_PROCESS_FAULT'] ==
                  'after-commit-before-reply')
                exit(86);
              if (probe == BoundaryProbe.afterCommitGate)
                await waitGate('after-commit');
              if (probe == BoundaryProbe.afterCommitError || token.cancelled)
                throw const NoteBoundaryFailure(
                  'committed-reload-required',
                  outcomeUnknown: true,
                );
              result = op == 'note-delta'
                  ? effects!.takeDelta(receipt.id)
                  : await loaded(
                      receipt.id,
                      preparation:
                          coordinator.timingsMicros['local_prepare'] ?? 0,
                      commit: coordinator.timingsMicros['local_commit'] ?? 0,
                    );
              break;
            }
            wire.identifier(intent.commandId);
            wire.identifier(intent.transactionId);
            final s = await store.readSnapshot();
            final queue = await store.readPendingCommands();
            final prior = await store.lookupCommandReceipt(intent.commandId);
            if (prior != null) {
              final old = queue
                  .where((p) => p.receipt.id == intent.commandId)
                  .firstOrNull;
              final storedIntent = old == null
                  ? null
                  : jsonDecode(old.immutableJson)['intent'];
              final body = effects == null
                  ? storedIntent
                  : storedIntent?['wire'];
              if (body == null ||
                  body['transaction_id'] != intent.transactionId ||
                  body['note'] != intent.note) {
                throw const NoteBoundaryFailure('command-id-collision');
              }
              final data = codec.decode(s.value.json);
              result = op == 'note-delta'
                  ? null
                  : CommittedTransactionNote(
                      commandId: intent.commandId,
                      revision: s.revision,
                      data: data,
                      preparedCore: SynoballCore(
                        initialState: data.synoballState!,
                        categoryPolicy: data.classification.policy,
                      ),
                    );
              break;
            }
            if (s.revision != intent.expectedRevision)
              throw const NoteBoundaryFailure('stale-local-revision');
            if (queue.any(
              (p) =>
                  (effects == null
                      ? jsonDecode(p.immutableJson)['intent']
                      : jsonDecode(
                          p.immutableJson,
                        )['intent']['wire'])['transaction_id'] ==
                  intent.transactionId,
            )) {
              throw const NoteBoundaryFailure('target-has-pending-proposal');
            }
            final cmd = wire.NoteCommand.parse({
              'protocol_version': 1,
              'domain_version': 1,
              'workspace_id': profile.workspace,
              'device_id': profile.device,
              'workspace_epoch': profile.epoch,
              'change_id': intent.commandId,
              'kind': 'transaction.set_note',
              'transaction_id': intent.transactionId,
              'base_revision': '0',
              'note': intent.note,
            });
            if (effects != null) {
              final receipt = await effects.commit(
                cmd,
                s,
                bookkeeping?.now() ?? DateTime.now().toUtc(),
                () async {
                  await Future<void>.delayed(Duration.zero);
                  if (probe == BoundaryProbe.beforeCommitGate)
                    await waitGate('before-commit');
                  check(token);
                  commitAttempted = true;
                },
              );
              committed = true;
              if (Platform.environment['QESTO_4A_PROCESS_FAULT'] ==
                  'after-commit-before-reply')
                exit(86);
              if (probe == BoundaryProbe.afterCommitGate)
                await waitGate('after-commit');
              if (probe == BoundaryProbe.afterCommitError || token.cancelled) {
                throw const NoteBoundaryFailure(
                  'committed-reload-required',
                  outcomeUnknown: true,
                );
              }
              result = op == 'note-delta'
                  ? effects.takeDelta(receipt.id)
                  : await loaded(receipt.id);
              break;
            }
            final watch = Stopwatch()..start();
            final prepared = prepareTransactionNote(
              codec.decode(s.value.json),
              intent.transactionId,
              intent.note,
              clock: bookkeeping?.now,
              ids: bookkeeping == null ? null : SyntheticIds(intent.commandId),
            );
            final snapshot = FinancialSnapshot(codec.encode(prepared.data));
            final preparation = watch.elapsedMicroseconds;
            await Future<void>.delayed(Duration.zero);
            if (probe == BoundaryProbe.beforeCommitGate)
              await waitGate('before-commit');
            check(token);
            watch.reset();
            commitAttempted = true;
            final receipt = await store.commitMutation(
              Mutation(
                id: intent.commandId,
                partition: profile.partition,
                expectedRevision: intent.expectedRevision,
                snapshot: snapshot,
                intentJson: jsonEncode(cmd.body),
              ),
            );
            final commit = watch.elapsedMicroseconds;
            committed = true;
            if (Platform.environment['QESTO_4A_PROCESS_FAULT'] ==
                'after-commit-before-reply')
              exit(86);
            if (probe == BoundaryProbe.afterCommitGate)
              await waitGate('after-commit');
            if (probe == BoundaryProbe.afterCommitError || token.cancelled) {
              throw const NoteBoundaryFailure(
                'committed-reload-required',
                outcomeUnknown: true,
              );
            }
            result = CommittedTransactionNote(
              commandId: receipt.id,
              revision: receipt.revision,
              data: prepared.data,
              preparedCore: prepared.core,
              preparationMicros: preparation,
              commitMicros: commit,
            );
          case 'close':
            await store.close();
            if (probe == BoundaryProbe.closeError)
              throw const NoteBoundaryFailure('synthetic-shutdown-error');
          default:
            throw const NoteBoundaryFailure('unknown-operation');
        }
        replies.send([id, true, result, DateTime.now().microsecondsSinceEpoch]);
      } catch (e) {
        if (op == 'sync' || op == 'apply-page') effects?.invalidate();
        if (effects != null &&
            (committed ||
                commitAttempted ||
                (e is NoteBoundaryFailure && e.outcomeUnknown))) {
          effects.invalidate(outcomeUnknown: true);
        }
        replies.send([
          id,
          false,
          e is NoteBoundaryFailure
              ? e.code
              : e is ContractViolation
              ? e.code
              : '${e.runtimeType}',
          committed ||
              e is SqliteException ||
              (commitAttempted &&
                  !(e is ContractViolation &&
                      e.code == 'synthetic-before-commit')) ||
              (e is NoteBoundaryFailure && e.outcomeUnknown),
        ]);
      } finally {
        tokens.remove(id);
      }
    });
  });
}
