import 'dart:async';
import 'dart:isolate';
import 'contract.dart';
import 'sqlite_container.dart';

/// One bounded, supervised writer. The low-level SQL implementation stays in
/// its isolate. An abnormal exit yields unknown durability, never success;
/// the caller must reopen and lookup the SAME command ID before retrying.
class ContainerWriter implements SyncTransactionContainer {
  ContainerWriter._(
    this._port,
    this._isolate,
    this._messages,
    this._errors,
    this._exits,
    this._pending,
    this.maxQueue,
  );
  final SendPort _port;
  final Isolate _isolate;
  final ReceivePort _messages, _errors, _exits;
  final Map<int, Completer<Object?>> _pending;
  final int maxQueue;
  int _next = 0;
  bool _closing = false, _dead = false;
  static Future<ContainerWriter> open(
    String directory,
    Partition partition, {
    int maxQueue = 32,
  }) async {
    if (maxQueue < 1 || maxQueue > 128) throw ArgumentError('queue bound');
    final messages = ReceivePort(),
        errors = ReceivePort(),
        exits = ReceivePort();
    final ready = Completer<SendPort>(), pending = <int, Completer<Object?>>{};
    ContainerWriter? writer;
    void failed() {
      writer?._dead = true;
      if (!ready.isCompleted)
        ready.completeError(const ContractViolation('owner-start-failed'));
      for (final c in pending.values.toList()) {
        c.completeError(const ContractViolation('owner-lost-outcome-unknown'));
      }
      pending.clear();
    }

    errors.listen((_) => failed());
    exits.listen((_) => failed());
    messages.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
        return;
      }
      final r = m as List;
      final completer = pending.remove(r[0]);
      if (completer == null) return;
      if (r[1] == true) {
        completer.complete(r[2]);
      } else {
        completer.completeError(ContractViolation(r[2] as String));
      }
    });
    final isolate = await Isolate.spawn(
      _worker,
      [directory, partition, messages.sendPort],
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true,
    );
    try {
      final port = await ready.future.timeout(const Duration(seconds: 30));
      return writer = ContainerWriter._(
        port,
        isolate,
        messages,
        errors,
        exits,
        pending,
        maxQueue,
      );
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      messages.close();
      errors.close();
      exits.close();
      rethrow;
    }
  }

  Future<T> _request<T>(String op, [Object? argument, bool shutdown = false]) {
    if (_dead || (_closing && !shutdown))
      return Future.error(const ContractViolation('owner-closed'));
    if (!shutdown && _pending.length >= maxQueue)
      return Future.error(const ContractViolation('owner-queue-full'));
    final id = ++_next, completer = Completer<Object?>();
    _pending[id] = completer;
    _port.send([id, op, argument]);
    return completer.future.then((v) => v as T);
  }

  @override
  Future<VersionedSnapshot> readSnapshot() => _request('read');
  @override
  Future<CommandReceipt> commitMutation(Mutation m) => _request('commit', m);
  @override
  Future<CommandReceipt?> lookupCommandReceipt(String id) =>
      _request('receipt', id);
  @override
  Future<List<PendingCommand>> readPendingCommands() => _request('pending');
  @override
  Future<void> markCommandAcknowledged(SyntheticReceipt r) =>
      _request('ack', r);
  @override
  Future<RemoteApplyResult> applyRemoteBundle(RemoteBundle b) =>
      _request('remote', b);
  @override
  Future<int> readCheckpoint() => _request('cursor');
  @override
  Future<RemoteContext?> readRemoteContext() => _request('sync-context');
  @override
  Future<void> initializeRemoteContext(String json) =>
      _request('sync-init', json);
  @override
  Future<RecoveryPoint> backup() => _request('backup');
  @override
  Future<RecoveryPoint> recover() => _request('recover');
  @override
  Future<RecoveryPoint> rotateKey() => _request('rotate');
  @override
  Future<void> close() async {
    if (_closing) throw const ContractViolation('shutdown-already-started');
    _closing = true;
    try {
      if (!_dead) await _request<void>('close', null, true);
    } finally {
      _dead = true;
      _messages.close();
      _errors.close();
      _exits.close();
    }
  }

  /// Explicit test harness hook, not graceful shutdown; durability is unknown.
  void simulateWorkerCrash() => _isolate.kill(priority: Isolate.immediate);
}

Future<void> _worker(List<Object> args) async {
  final store = await SqliteContainer.open(
    args[0] as String,
    args[1] as Partition,
  );
  final replies = args[2] as SendPort, requests = ReceivePort();
  replies.send(requests.sendPort);
  var tail = Future<void>.value();
  requests.listen((m) {
    final request = m as List;
    tail = tail.then((_) async {
      try {
        Object? value;
        switch (request[1]) {
          case 'read':
            value = await store.readSnapshot();
          case 'commit':
            value = await store.commitMutation(request[2] as Mutation);
          case 'receipt':
            value = await store.lookupCommandReceipt(request[2] as String);
          case 'pending':
            value = await store.readPendingCommands();
          case 'ack':
            await store.markCommandAcknowledged(request[2] as SyntheticReceipt);
          case 'remote':
            value = await store.applyRemoteBundle(request[2] as RemoteBundle);
          case 'cursor':
            value = await store.readCheckpoint();
          case 'sync-context':
            value = await store.readRemoteContext();
          case 'sync-init':
            await store.initializeRemoteContext(request[2] as String);
          case 'backup':
            value = await store.backup();
          case 'recover':
            value = await store.recover();
          case 'rotate':
            value = await store.rotateKey();
          case 'close':
            await store.close();
            requests.close();
          default:
            throw const ContractViolation('unknown-owner-operation');
        }
        replies.send([request[0], true, value]);
      } catch (e) {
        replies.send([
          request[0],
          false,
          e is ContractViolation ? e.code : '${e.runtimeType}',
        ]);
      }
    });
  });
}
