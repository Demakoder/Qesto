import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'config.dart';
import 'domain.dart';
import 'domain_executor.dart';
import 'protocol.dart';

typedef FaultHook =
    Future<void> Function(
      String stage,
      NoteCommand command,
      TxSession? session,
    );

class SyncDatabase {
  SyncDatabase(
    this.config, {
    this.hook,
    this.executor = const LegacySyncDomainExecutor(),
  });
  final TestConfig config;
  final FaultHook? hook;
  final SyncDomainExecutor executor;

  Future<void> verifyEnvironment() async {
    final c = await config.connect();
    try {
      final marker = await c.execute('SELECT marker FROM experiment_identity');
      if (marker.single.single != experimentMarker)
        throw StateError('Wrong database');
      final roles = await c.execute(
        'SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname=current_user',
      );
      if (roles.single.any((v) => v != false))
        throw StateError('Unsafe database role');
    } finally {
      await c.close();
    }
  }

  Future<void> _scope(TxSession s, String workspace) async {
    await s.execute(
      r"SELECT set_config('qesto.workspace', $1, true)",
      parameters: [workspace],
    );
    await s.execute("SET LOCAL lock_timeout = '10s'");
    await s.execute('SET LOCAL synchronous_commit = on');
  }

  Future<Map<String, dynamic>> _workspace(
    TxSession s,
    Principal p, {
    bool lock = false,
  }) async {
    final row = await s.execute(
      'SELECT * FROM workspace WHERE workspace_id=\$1${lock ? ' FOR UPDATE' : ''}',
      parameters: [p.workspace],
    );
    if (row.isEmpty || row.single.toColumnMap()['owner_id'] != p.user)
      throw const ApiError(403, 'FORBIDDEN_SCOPE');
    return row.single.toColumnMap();
  }

  Future<Map<String, dynamic>> push(Principal p, NoteCommand command) async {
    final totalWatch = Stopwatch()..start();
    p.authorize(command.workspace, command.device);
    final c = await config.connect();
    try {
      final receipt = await c.runTx((s) async {
        await _scope(s, p.workspace);
        final w = await _workspace(s, p, lock: true);
        if (w['epoch'] != command.epoch)
          throw const ApiError(409, 'WORKSPACE_EPOCH_CHANGED');
        await hook?.call('locked', command, s);
        final old = await s.execute(
          r'SELECT body_digest, receipt FROM command_receipt WHERE workspace_id=$1 AND change_id=$2',
          parameters: [p.workspace, command.changeId],
        );
        if (old.isNotEmpty) {
          if (old.single[0] != command.contentDigest)
            throw const ApiError(409, 'IDEMPOTENCY_KEY_REUSED');
          return object(jsonDecode(old.single[1] as String));
        }
        final stored = w['state'] as String;
        final domainWatch = Stopwatch()..start();
        final state = executor.read(stored, p.user);
        executor.validateCommand(stored, command, p.user);
        final revisions = Map<String, dynamic>.from(w['revisions'] as Map);
        final matches = state.transactions.where(
          (t) =>
              t.id == command.target &&
              t.entityId == executor.entityFor(p.user),
        );
        if (matches.isEmpty) throw const ApiError(404, 'TRANSACTION_NOT_FOUND');
        final transaction = matches.single;
        final revision = decimal(revisions[command.target]);
        final seq = (w['head'] as int) + 1;
        final conflict = revision != command.baseRevision;
        final entities = <Map<String, dynamic>>[];
        SynoballState next = state;
        ExecutedDomainState? executed;
        final time = DateTime.now().toUtc();
        if (!conflict) {
          executed = executor.execute(stored, command, p.user, time);
          next = executed.core;
          final beforeById = {for (final t in state.transactions) t.id: t};
          if (beforeById.length != state.transactions.length)
            throw StateError('Duplicate canonical IDs');
          // Core can refresh derived metadata. Publish every changed transaction,
          // not a hand-written approximation of its result.
          for (final t in next.transactions) {
            final before = beforeById[t.id]!;
            if (canonicalJson(before.toJson()) != canonicalJson(t.toJson())) {
              final rev = decimal(revisions[t.id]) + 1;
              revisions[t.id] = '$rev';
              entities.add({
                'revision': '$rev',
                'transaction': transactionWire(t),
              });
            }
          }
          if (!entities.any(
            (v) => (v['transaction'] as Map)['id'] == command.target,
          )) {
            // A no-op still has one authoritative entity revision/receipt.
            revisions[transaction.id] = '${revision + 1}';
            entities.add({
              'revision': '${revision + 1}',
              'transaction': transactionWire(transaction),
            });
          }
        }
        executor.observe(
          'server_domain_diff',
          domainWatch.elapsedMicroseconds,
          bytes: utf8.encode(stored).length,
          entities: entities.length,
        );
        final sqlWatch = Stopwatch()..start();
        final result = <String, dynamic>{
          'protocol_version': protocolVersion,
          'domain_version': domainVersion,
          'workspace_id': p.workspace,
          'workspace_epoch': w['epoch'],
          'change_id': command.changeId,
          'content_digest': command.contentDigest,
          'status': conflict ? 'conflict' : 'accepted',
          'commit_seq': '$seq',
          'transaction_id': command.target,
          'revision': revisions[command.target],
          ...executor.metadata(stored, p.user),
          if (conflict)
            'conflict': {
              'base_revision': '${command.baseRevision}',
              'proposed_note': command.note,
              'current_note': transaction.userNote,
              'current_revision': '$revision',
            },
        };
        await s.execute(
          r'UPDATE workspace SET state=$1, revisions=$2::jsonb, head=$3 WHERE workspace_id=$4',
          parameters: [
            executed?.stored ?? stored,
            jsonEncode(revisions),
            seq,
            p.workspace,
          ],
        );
        await hook?.call('after-state', command, s);
        await s.execute(
          r'INSERT INTO command_receipt VALUES ($1,$2,$3,$4,$5,$6)',
          parameters: [
            p.workspace,
            command.changeId,
            command.contentDigest,
            canonicalJson(command.body),
            jsonEncode(result),
            seq,
          ],
        );
        final bundle = {
          'seq': '$seq',
          'receipt': result,
          'entities': entities,
          if (executed != null)
            ...executor.effect(stored, executed, command, p.user, time),
        };
        await s.execute(
          r'INSERT INTO change_bundle VALUES ($1,$2,$3,$4)',
          parameters: [p.workspace, seq, command.changeId, jsonEncode(bundle)],
        );
        await hook?.call('before-commit', command, s);
        executor.observe(
          'postgres_write_prepare',
          sqlWatch.elapsedMicroseconds,
          bytes: utf8.encode(executed?.stored ?? stored).length,
        );
        return result;
      });
      executor.observe('server_transaction', totalWatch.elapsedMicroseconds);
      await hook?.call('after-commit', command, null);
      return receipt;
    } finally {
      await c.close();
    }
  }

  Future<Map<String, dynamic>> snapshot(Principal p) async {
    final c = await config.connect();
    try {
      return await c.runTx(
        (s) async {
          await _scope(s, p.workspace);
          final w = await _workspace(s, p);
          final state = executor.read(w['state'] as String, p.user);
          final revisions = w['revisions'] as Map;
          // Only primary canonical entities, not private raw payloads or codec-v7.
          return {
            'protocol_version': protocolVersion,
            'domain_version': domainVersion,
            'workspace_id': p.workspace,
            'workspace_epoch': w['epoch'],
            'head': '${w['head']}',
            ...executor.metadata(w['state'] as String, p.user),
            'entities': [
              for (final t in state.transactions)
                {
                  'revision': revisions[t.id],
                  'transaction': transactionWire(t),
                },
            ],
            'cursor': config.cursors.encode(
              p.workspace,
              w['epoch'] as String,
              w['head'] as int,
              null,
            ),
          };
        },
        settings: TransactionSettings(
          isolationLevel: IsolationLevel.repeatableRead,
        ),
      );
    } finally {
      await c.close();
    }
  }

  Future<Map<String, dynamic>> pull(
    Principal p,
    String? token,
    int limit,
  ) async {
    if (limit < 1 || limit > 100)
      throw const ApiError(400, 'INVALID_PAGE_SIZE');
    final c = await config.connect();
    try {
      return await c.runTx(
        (s) async {
          await _scope(s, p.workspace);
          final w = await _workspace(s, p);
          final epoch = w['epoch'] as String;
          final cursor = token == null
              ? (after: 0, high: null)
              : config.cursors.decode(token, p.workspace, epoch);
          final high = cursor.high ?? w['head'] as int;
          if (cursor.after > high || high > (w['head'] as int))
            throw const ApiError(409, 'INVALID_CURSOR');
          final rows = await s.execute(
            r'SELECT bundle FROM change_bundle WHERE workspace_id=$1 AND seq>$2 AND seq<=$3 ORDER BY seq LIMIT $4',
            parameters: [p.workspace, cursor.after, high, limit],
          );
          final bundles = rows
              .map((r) => object(jsonDecode(r.single as String)))
              .toList();
          var after = cursor.after;
          for (final b in bundles) {
            if (decimal(b['seq']) != after + 1)
              throw StateError('Non-contiguous server journal');
            after++;
          }
          if (bundles.isEmpty && after < high)
            throw StateError('Missing committed bundle');
          return {
            'protocol_version': protocolVersion,
            'domain_version': domainVersion,
            'workspace_id': p.workspace,
            'workspace_epoch': epoch,
            'from_seq': '${cursor.after}',
            ...executor.metadata(w['state'] as String, p.user),
            'high': '$high',
            'bundles': bundles,
            'has_more': after < high,
            'next_cursor': config.cursors.encode(
              p.workspace,
              epoch,
              after,
              after < high ? high : null,
            ),
          };
        },
        settings: TransactionSettings(
          isolationLevel: IsolationLevel.repeatableRead,
        ),
      );
    } finally {
      await c.close();
    }
  }
}
