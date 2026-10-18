/// Synthetic Windows implementation. Never imported by the app.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sql;
import '../storage_spike.dart';
import '../wal_policy.dart';
import '../generation_vault.dart';
import '../windows_key_probe.dart';
import '../synthetic_trace.dart';
import 'contract.dart';
import 'chunked_json.dart';

part 'durable_effects.dart';

final _schema = [
  'CREATE TABLE identity(partition TEXT NOT NULL, format INTEGER NOT NULL)',
  'CREATE TABLE state(id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, snapshot TEXT NOT NULL, digest TEXT NOT NULL)',
  'CREATE TABLE journal(revision INTEGER PRIMARY KEY, kind TEXT NOT NULL, reference TEXT NOT NULL, digest TEXT NOT NULL)',
  'CREATE TABLE commands(id TEXT PRIMARY KEY, revision INTEGER NOT NULL UNIQUE REFERENCES journal(revision), body TEXT NOT NULL, digest TEXT NOT NULL)',
  'CREATE TABLE delivery(id TEXT PRIMARY KEY REFERENCES commands(id), state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, lease_until INTEGER, receipt TEXT, covered INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE receipts(id TEXT PRIMARY KEY, command_id TEXT NOT NULL REFERENCES commands(id), body TEXT NOT NULL)',
  'CREATE TABLE shadow(id INTEGER PRIMARY KEY CHECK(id=1), snapshot TEXT, cursor INTEGER NOT NULL, CHECK(snapshot IS NOT NULL OR cursor=0))',
  'CREATE TABLE checkpoint(id INTEGER PRIMARY KEY CHECK(id=1), cursor INTEGER NOT NULL)',
  'CREATE TABLE aliases(alias TEXT PRIMARY KEY, target TEXT NOT NULL)',
  'CREATE TABLE conflicts(id TEXT PRIMARY KEY, body TEXT NOT NULL)',
  'CREATE TABLE bundles(id TEXT PRIMARY KEY, digest TEXT NOT NULL, revision INTEGER NOT NULL, cursor INTEGER NOT NULL, retained INTEGER NOT NULL)',
  'CREATE TABLE migration(id TEXT PRIMARY KEY, manifest TEXT NOT NULL)',
  for (final table in [
    'commands',
    'journal',
    'receipts',
    'migration',
    'bundles',
  ])
    for (final op in ['UPDATE', 'DELETE'])
      'CREATE TRIGGER immutable_${table}_$op BEFORE $op ON $table BEGIN SELECT RAISE(ABORT,\'immutable record\'); END',
];

class SqliteContainer implements SyncTransactionContainer, CheckpointStore {
  SqliteContainer._(
    this.directory,
    this.partition,
    this._lock,
    this._manifest,
    this._db, {
    this.fault,
    this.availableBytes,
    this.softBytes = 32 * mib,
    this.hardBytes = 256 * mib,
  }) {
    _policy = _newPolicy();
  }
  final String directory;
  final Partition partition;
  final RandomAccessFile _lock;
  Map<String, dynamic> _manifest;
  sql.Database _db;
  final void Function(String)? fault;
  final int Function()? availableBytes;
  final int softBytes, hardBytes;
  late WalPolicy _policy;
  bool _busy = false, _closed = false;
  final Object _effectsAuthority = Object();
  final Set<ReaderLease> _readers = {};
  WalPolicy _newPolicy() {
    _db.execute('PRAGMA journal_mode=WAL');
    _db.execute('PRAGMA synchronous=FULL');
    return WalPolicy(
      this,
      available: availableBytes,
      softBytes: softBytes,
      hardBytes: hardBytes,
    );
  }

  @override
  sql.Database get raw => _db; // harness only, not TransactionContainer API
  @override
  String get path => '$directory/container-${_manifest['active']}.db';
  String get _control => '$directory/container-vault.bin';
  String get _recovery => '$directory/container-recovery.bin';
  int get generation => _manifest['active'] as int;
  bool get requiresReopen => _policy.poisoned;
  bool get incremental =>
      _db.select('SELECT format FROM identity').single['format'] == 2;
  final Map<String, int> incrementalMetrics = {};
  // Bounded verified read cache, invalidated by any write on this connection,
  // external data_version change, generation switch or different manifest.
  // Raw fault injection therefore cannot hide behind a cached value.
  final Map<
    String,
    ({sql.Database db, int changes, int version, String stored, String json})
  >
  _readCache = {};
  final Map<String, ({String stored, String json, int version})> _stagedReads =
      {};
  final List<FinancialSnapshot> _financialCache = [];
  int? _readCacheBudget;
  /// Stage 4g opt-in only. Payload accounting is conservative UTF-16 bytes,
  /// NOT a bound on native RSS, temporary transaction buffers or model graphs.
  void setReadCacheBudgetForExperiment(int bytes) {
    _usable();
    if (_busy || bytes < 0) throw const ContractViolation('cache-budget-state');
    _readCacheBudget = bytes;
    _trimCaches();
  }
  int get retainedCachePayloadBytes {
    final strings = Set<String>.identity();
    for (final e in _readCache.values) { strings.add(e.json); strings.add(e.stored); }
    for (final e in _financialCache) { strings.add(e.json); }
    return strings.fold(0, (n, s) => n + s.length * 2) +
        256 * (_readCache.length + _financialCache.length);
  }
  Map<String, Object?> get cacheDiagnostics => {
    'budgetBytes': _readCacheBudget, 'payloadBytes': retainedCachePayloadBytes,
    'readEntries': _readCache.length, 'snapshotEntries': _financialCache.length,
    'stagedEntries': _stagedReads.length, 'storageGeneration': generation,
  };
  void _clearCaches() {
    _readCache.clear(); _financialCache.clear(); _stagedReads.clear();
  }
  void _trimCaches() {
    final budget = _readCacheBudget;
    if (budget == null) return; // Stage 4f control unchanged.
    // Drop superseded JSON generations first; current scope strings remain
    // shared by identity. Hash caches never grant integrity authority.
    _financialCache.removeWhere((f) => !_readCache.values.any((r) => identical(r.json, f.json)));
    while (retainedCachePayloadBytes > budget && _readCache.isNotEmpty) {
      _readCache.remove(_readCache.keys.first);
      _financialCache.removeWhere((f) => !_readCache.values.any((r) => identical(r.json, f.json)));
    }
  }
  FinancialSnapshot _financial(String json) {
    if (incremental) {
      for (final item in _financialCache) {
        if (item.json == json) return item;
      }
    }
    final item = FinancialSnapshot(json);
    if (incremental) {
      if (_financialCache.length == 2) _financialCache.removeAt(0);
      _financialCache.add(item);
      _trimCaches();
    }
    return item;
  }

  String _stored(String scope, String json) {
    if (!incremental) return json;
    final chunks = ChunkedJsonStore(_db, fault: fault);
    final result = chunks.write(scope, json);
    _stagedReads[scope] = (
      stored: result,
      json: json,
      version: _db.select('PRAGMA data_version').single.values.single as int,
    );
    incrementalMetrics.update(
      'written_chunks',
      (v) => v + chunks.writtenChunks,
      ifAbsent: () => chunks.writtenChunks,
    );
    incrementalMetrics.update(
      'written_payload_bytes',
      (v) => v + chunks.writtenBytes,
      ifAbsent: () => chunks.writtenBytes,
    );
    return result;
  }

  String _restored(String scope, String value, {sql.Database? database}) {
    final db = database ?? _db;
    if (db.select('SELECT format FROM identity').single['format'] == 1)
      return value;
    final changes = db.select('SELECT total_changes() n').single['n'] as int;
    final version =
        db.select('PRAGMA data_version').single.values.single as int;
    final cached = _readCache[scope];
    if (database == null &&
        cached != null &&
        identical(cached.db, db) &&
        cached.changes == changes &&
        cached.version == version &&
        cached.stored == value)
      return cached.json;
    final json = SyntheticTrace.sync('storage.reconstruct.$scope', () => ChunkedJsonStore(db).read(scope, value));
    if (database == null)
      _readCache[scope] = (
        db: db,
        changes: changes,
        version: version,
        stored: value,
        json: json,
      );
    _trimCaches();
    return json;
  }

  static Future<RandomAccessFile> _acquire(String dir) async {
    requireOwnedPath('$dir/container.lock');
    final handle = await File(
      '$dir/container.lock',
    ).open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      return handle;
    } catch (_) {
      await handle.close();
      throw const ContractViolation('profile-already-owned');
    }
  }

  static Map<String, dynamic> _readManifest(String file, Partition partition) {
    try {
      final value =
          jsonDecode(
                utf8.decode(
                  WindowsKeyProbe.unprotect(File(file).readAsBytesSync()),
                ),
              )
              as Map<String, dynamic>;
      final generations = value['generations'] as Map;
      if (value['format'] != 'qesto.container.synthetic.v1' ||
          value['partition'] != partition.key ||
          value['active'] is! int ||
          !generations.containsKey('${value['active']}') ||
          generations.length > 2) {
        throw const FormatException('manifest');
      }
      for (final entry in generations.entries) {
        if ((int.tryParse(entry.key as String) ?? 0) < 1 ||
            base64Decode(entry.value['key'] as String).length != 32 ||
            entry.value['minimumRevision'] is! int)
          throw const FormatException('generation');
      }
      return value;
    } catch (_) {
      throw const ContractViolation('vault-recovery-required-bytes-retained');
    }
  }

  static void _publish(String file, Map<String, dynamic> manifest) =>
      GenerationVault.atomicReplace(
        file,
        WindowsKeyProbe.protect(utf8.encode(jsonEncode(manifest))),
      );
  static sql.Database _openDatabase(
    String dir,
    Map<String, dynamic> m, {
    bool create = false,
  }) {
    final path = '$dir/container-${m['active']}.db';
    if (!create && !File(path).existsSync())
      throw const ContractViolation('database-missing');
    return openNative(
      path,
      Candidate.directMc,
      base64Decode(
        (m['generations'] as Map)['${m['active']}']['key'] as String,
      ),
    );
  }

  static Future<SqliteContainer> open(
    String directory,
    Partition partition, {
    bool recovery = false,
    void Function(String)? fault,
    int Function()? availableBytes,
    int softBytes = 32 * mib,
    int hardBytes = 256 * mib,
  }) async {
    final lock = await _acquire(directory);
    sql.Database? db;
    try {
      final m = _readManifest(
        '$directory/container-${recovery ? 'recovery' : 'vault'}.bin',
        partition,
      );
      db = SyntheticTrace.sync<sql.Database>('storage.native-open-key', () => _openDatabase(directory, m));
      final store = SqliteContainer._(
        directory,
        partition,
        lock,
        m,
        db,
        fault: fault,
        availableBytes: availableBytes,
        softBytes: softBytes,
        hardBytes: hardBytes,
      );
      store.verify();
      if (recovery) {
        store._guardRecoveryAgainstOtherGenerations();
        _publish(store._control, m); // explicit operator opt-in only
      }
      return store;
    } catch (_) {
      db?.close();
      await lock.close();
      rethrow;
    }
  }

  /// Explicit synthetic bootstrap. Same manifest is resumable; no automatic
  /// provision on open failure and no per-transaction historical commands.
  static Future<SqliteContainer> migrate(
    String directory,
    MigrationManifest migration,
    FinancialSnapshot snapshot, {
    void Function(String)? fault,
    bool incremental = false,
  }) async {
    if (snapshot.hash != migration.sourceDigest)
      throw const ContractViolation('source-digest');
    final lock = await _acquire(directory);
    sql.Database? db;
    try {
      final control = '$directory/container-vault.bin';
      Map<String, dynamic> m;
      if (File(control).existsSync()) {
        m = _readManifest(control, migration.partition);
        if (m['migration'] != migration.json)
          throw const ContractViolation('migration-collision');
      } else {
        if (Directory(
          directory,
        ).listSync().any((e) => e.path.contains('container-'))) {
          throw const ContractViolation('existing-state-without-vault');
        }
        m = {
          'format': 'qesto.container.synthetic.v1',
          'partition': migration.partition.key,
          'migration': migration.json,
          'active': 1,
          'generations': {
            '1': {
              'key': base64Encode(randomKey()),
              'minimumRevision': 0,
              'digest': snapshot.hash,
            },
          },
        };
        _publish(control, m);
      }
      // Creation only under the same explicit migration manifest; a missing DB
      // after successful migration is NOT recreated (completion marker below).
      final complete = m['bootstrapComplete'] == true;
      db = _openDatabase(directory, m, create: !complete);
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
      final engine = DirectEngine(db);
      await engine.transaction(() async {
        final initialized = db!
            .select("SELECT name FROM sqlite_master WHERE name='migration'")
            .isNotEmpty;
        if (initialized) {
          if (db.select('SELECT format FROM identity').single['format'] !=
              (incremental ? 2 : 1)) {
            throw const ContractViolation('storage-format-mismatch');
          }
          final prior = db.select('SELECT manifest FROM migration WHERE id=?', [
            migration.id,
          ]);
          if (prior.length != 1 || prior.single['manifest'] != migration.json)
            throw const ContractViolation('migration-collision');
          return;
        }
        if (complete || db.select('SELECT name FROM sqlite_master').isNotEmpty)
          throw const ContractViolation(
            'incomplete-database-requires-recovery',
          );
        for (final s in _schema) {
          db.execute(s);
        }
        db.execute('INSERT INTO identity VALUES (?,?)', [
          migration.partition.key,
          incremental ? 2 : 1,
        ]);
        if (incremental) ChunkedJsonStore.create(db);
        db.execute('INSERT INTO state VALUES (1,0,?,?)', [
          incremental
              ? ChunkedJsonStore(db, fault: fault).write('state', snapshot.json)
              : snapshot.json,
          snapshot.hash,
        ]);
        db.execute('INSERT INTO journal VALUES (0,\'bootstrap\',?,?)', [
          migration.id,
          snapshot.hash,
        ]);
        fault?.call('migration-after-snapshot');
        // A local migration is not an accepted remote bootstrap. Until the
        // first complete synthetic page, there is no authoritative shadow.
        db.execute('INSERT INTO shadow VALUES (1,NULL,0)');
        db.execute('INSERT INTO checkpoint VALUES (1,0)');
        db.execute('INSERT INTO migration VALUES (?,?)', [
          migration.id,
          migration.json,
        ]);
        fault?.call('migration-before-commit');
      });
      fault?.call('migration-after-commit');
      m['bootstrapComplete'] = true;
      _publish(control, m);
      final store = SqliteContainer._(
        directory,
        migration.partition,
        lock,
        m,
        db,
        fault: fault,
      );
      store.verify();
      return store;
    } catch (_) {
      db?.close();
      await lock.close();
      rethrow;
    }
  }

  void _usable() {
    if (_closed) throw const ContractViolation('closed');
    if (_busy) throw const ContractViolation('operation-in-progress');
  }

  Future<T> _exclusive<T>(Future<T> Function() body) async {
    _usable();
    _busy = true;
    try {
      return await body();
    } finally {
      _busy = false;
    }
  }

  void _partition(Partition value) {
    if (value.key != partition.key)
      throw const ContractViolation('partition-mismatch');
  }

  VersionedSnapshot _snapshot() {
    final row = _db.select('SELECT * FROM state').single;
    final s = _financial(_restored('state', row['snapshot'] as String));
    if (s.hash != row['digest'])
      throw const ContractViolation('snapshot-corrupt');
    return VersionedSnapshot(row['revision'] as int, s);
  }

  @override
  Future<VersionedSnapshot> readSnapshot() async {
    _usable();
    return _snapshot();
  }

  @override
  Future<int> readCheckpoint() async {
    _usable();
    return _cursor;
  }

  bool get _hasSyncContext => _db
      .select("SELECT name FROM sqlite_master WHERE name='sync_context'")
      .isNotEmpty;

  @override
  Future<RemoteContext?> readRemoteContext() async {
    _usable();
    if (!_hasSyncContext) return null;
    final row = _db.select('SELECT body,digest FROM sync_context').single;
    if (digest(row['body'] as String) != row['digest'])
      throw const ContractViolation('sync-context-corrupt');
    return RemoteContext(
      row['body'] as String,
      _financial(
        _restored(
          'shadow',
          _db.select('SELECT snapshot FROM shadow').single['snapshot']
              as String,
        ),
      ),
    );
  }

  @override
  Future<void> initializeRemoteContext(
    String json,
  ) => _write(utf8.encode(json).length, () async {
    // Explicit opt-in on a fresh synthetic clone only. Existing outboxes and
    // cursor histories are never silently upgraded/replaced.
    if (_hasSyncContext ||
        _snapshot().revision != 0 ||
        _cursor != 0 ||
        _pending().isNotEmpty)
      throw const ContractViolation('sync-initialization-not-fresh');
    if ((jsonDecode(json) as Map)['checkpoint'] != 0)
      throw const ContractViolation('invalid-initial-sync-checkpoint');
    _db.execute(
      'CREATE TABLE sync_context(id INTEGER PRIMARY KEY CHECK(id=1), body TEXT NOT NULL, digest TEXT NOT NULL)',
    );
    _db.execute('INSERT INTO sync_context VALUES (1,?,?)', [
      json,
      digest(json),
    ]);
    _db.execute('UPDATE shadow SET snapshot=?', [
      _stored('shadow', _snapshot().value.json),
    ]);
  });

  int get _cursor =>
      _db.select('SELECT cursor FROM checkpoint').single['cursor'] as int;
  void _cas(int expected) {
    if (_db.select('SELECT revision FROM state').single['revision'] != expected)
      throw StaleRevision();
  }

  Future<T> _write<T>(
    int bytes,
    Future<T> Function() body,
  ) => _exclusive(() async {
    _stagedReads.clear();
    var committed = false;
    try {
      final result = await _policy.write(
        payloadBytes: bytes,
        commit: () => DirectEngine(_db).transaction(body),
        expectedRejection: (e) => e is ContractViolation,
      );
      committed = true;
      // Promote only after COMMIT. The staged bytes are exactly those whose
      // chunks/root were verified and written in that transaction, never a
      // speculative financial model. Rollback leaves no cache publication.
      final version =
          _db.select('PRAGMA data_version').single.values.single as int;
      final changes = _db.select('SELECT total_changes() n').single['n'] as int;
      for (final e in _stagedReads.entries) {
        if (e.value.version == version)
          _readCache[e.key] = (
            db: _db,
            version: version,
            changes: changes,
            stored: e.value.stored,
            json: e.value.json,
          );
      }
      _trimCaches();
      return result;
    } catch (_) {
      if (committed)
        _policy.poisoned =
            true; // post-commit read failure: unknown ACK, reload by immutable ID
      rethrow;
    } finally {
      _stagedReads.clear();
    }
  });
  CommandReceipt? _receipt(String id) {
    final rows = _db.select(
      'SELECT c.*,d.state,d.receipt FROM commands c JOIN delivery d USING(id) WHERE id=?',
      [id],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return CommandReceipt(
      id,
      r['revision'] as int,
      DeliveryState.values.byName(r['state'] as String),
      r['digest'] as String,
      serverReceipt: r['receipt'] as String?,
    );
  }

  @override
  Future<CommandReceipt?> lookupCommandReceipt(String id) async {
    _usable();
    return _receipt(id);
  }

  List<PendingCommand> _pending() => [
    for (final row in _db.select(
      'SELECT c.*,d.attempts FROM commands c JOIN delivery d USING(id) WHERE covered=0 ORDER BY c.revision',
    ))
      PendingCommand(
        _receipt(row['id'] as String)!,
        row['body'] as String,
        row['attempts'] as int,
      ),
  ];
  @override
  Future<List<PendingCommand>> readPendingCommands() async {
    _usable();
    return _pending();
  }

  @override
  Future<CommandReceipt> commitMutation(Mutation mutation) => _write(
    utf8.encode(mutation.snapshot.json).length +
        utf8.encode(mutation.immutableJson).length,
    () async {
      _partition(mutation.partition);
      final body = mutation.immutableJson,
          hash = digest(mutation.immutableJson);
      final old = _receipt(mutation.id);
      if (old != null) {
        if (old.contentDigest != hash) throw CommandCollision();
        return old;
      }
      if (mutation.id.isEmpty || mutation.dependencies.contains(mutation.id))
        throw const ContractViolation('invalid-command');
      _cas(mutation.expectedRevision);
      final revision = mutation.expectedRevision + 1;
      final blocked = mutation.dependencies.any(
        (id) => _receipt(id)?.remotelyAccepted != true,
      );
      _db.execute('INSERT INTO journal VALUES (?,\'local\',?,?)', [
        revision,
        mutation.id,
        mutation.snapshot.hash,
      ]);
      _db.execute('UPDATE state SET revision=?,snapshot=?,digest=?', [
        revision,
        _stored('state', mutation.snapshot.json),
        mutation.snapshot.hash,
      ]);
      fault?.call('local-after-snapshot');
      _db.execute('INSERT INTO commands VALUES (?,?,?,?)', [
        mutation.id,
        revision,
        body,
        hash,
      ]);
      _db.execute('INSERT INTO delivery(id,state) VALUES (?,?)', [
        mutation.id,
        (blocked ? DeliveryState.blockedDependency : DeliveryState.queued).name,
      ]);
      fault?.call('local-before-commit');
      return _receipt(mutation.id)!;
    },
  );

  Future<void> claim(
    String id, {
    required int nowMs,
    required int leaseMs,
  }) => _write(4096, () async {
    if (leaseMs <= 0 || leaseMs > 60000)
      throw const ContractViolation('lease-bound');
    final state = _receipt(id)?.state;
    if (state != DeliveryState.queued)
      throw const ContractViolation('not-deliverable');
    _db.execute(
      'UPDATE delivery SET state=?,attempts=attempts+1,lease_until=? WHERE id=?',
      [DeliveryState.inFlight.name, nowMs + leaseMs, id],
    );
  });
  Future<void> retryExpired({required int nowMs}) => _write(4096, () async {
    _db.execute(
      'UPDATE delivery SET state=?,lease_until=NULL WHERE state=? AND lease_until<=?',
      [DeliveryState.queued.name, DeliveryState.inFlight.name, nowMs],
    );
  });
  Future<void> resume(String id) => _write(4096, () async {
    final r = _receipt(id);
    if (r == null ||
        ![
          DeliveryState.blockedDependency,
          DeliveryState.pausedAuthentication,
        ].contains(r.state)) {
      throw const ContractViolation('explicit-resolution-required');
    }
    final command =
        jsonDecode(
              _db.select('SELECT body FROM commands WHERE id=?', [
                    id,
                  ]).single['body']
                  as String,
            )
            as Map;
    if ((command['dependencies'] as List).any(
      (d) => _receipt(d as String)?.remotelyAccepted != true,
    )) {
      throw const ContractViolation('dependency-unresolved');
    }
    _db.execute('UPDATE delivery SET state=?,lease_until=NULL WHERE id=?', [
      DeliveryState.queued.name,
      id,
    ]);
  });
  @override
  Future<void> markCommandAcknowledged(SyntheticReceipt receipt) => _write(
    utf8.encode(receipt.json).length,
    () async => _acknowledge(receipt),
  );
  void _acknowledge(SyntheticReceipt receipt) {
    _partition(receipt.partition);
    if (![
      DeliveryState.accepted,
      DeliveryState.conflict,
      DeliveryState.blockedDependency,
      DeliveryState.rejectedRequiringAttention,
      DeliveryState.pausedAuthentication,
    ].contains(receipt.state)) {
      throw const ContractViolation('invalid-receipt-state');
    }
    final prior = _db.select('SELECT body FROM receipts WHERE id=?', [
      receipt.id,
    ]);
    if (prior.isNotEmpty) {
      if (prior.single['body'] != receipt.json) throw CommandCollision();
      return;
    }
    final command = _receipt(receipt.commandId);
    if (command == null || command.contentDigest != receipt.contentDigest)
      throw const ContractViolation('receipt-command-mismatch');
    if (![DeliveryState.inFlight, DeliveryState.queued].contains(command.state))
      throw const ContractViolation('receipt-invalid-transition');
    _db.execute('INSERT INTO receipts VALUES (?,?,?)', [
      receipt.id,
      receipt.commandId,
      receipt.json,
    ]);
    fault?.call('ack-after-receipt');
    _db.execute(
      'UPDATE delivery SET state=?,receipt=?,lease_until=NULL WHERE id=?',
      [receipt.state.name, receipt.json, receipt.commandId],
    );
    // No cursor movement and no payload deletion: accepted may not be in shadow yet.
  }

  @override
  Future<RemoteApplyResult> applyRemoteBundle(RemoteBundle bundle) => _write(
    utf8.encode(bundle.shadow.json).length + utf8.encode(bundle.json).length,
    () async {
      _partition(bundle.partition);
      if (bundle.protocolVersion != 1)
        throw const ContractViolation('unsupported-bundle');
      final old = _db.select('SELECT * FROM bundles WHERE id=?', [bundle.id]);
      if (old.isNotEmpty) {
        final r = old.single;
        if (r['digest'] != digest(bundle.json)) throw CommandCollision();
        return RemoteApplyResult(
          r['revision'] as int,
          r['cursor'] as int,
          r['retained'] == 1,
        );
      }
      _cas(bundle.expectedRevision);
      if (bundle.fromCursor != _cursor || bundle.toCursor <= bundle.fromCursor)
        throw const ContractViolation('stale-cursor');
      for (final receipt in bundle.receipts) {
        _acknowledge(receipt);
      }
      for (final id in bundle.coveredCommands) {
        if (_receipt(id)?.remotelyAccepted != true)
          throw const ContractViolation('unconfirmed-covered-command');
        _db.execute('UPDATE delivery SET covered=1 WHERE id=?', [id]);
      }
      final pending = _pending();
      final retained = pending.isNotEmpty;
      final revision = bundle.expectedRevision + 1;
      // Deliberately conservative conflict policy, not a new financial merge.
      if ((bundle.projection == null) != (bundle.syncContextJson == null))
        throw const ContractViolation('incomplete-sync-projection');
      if (_hasSyncContext && bundle.syncContextJson == null)
        throw const ContractViolation('sync-projection-required');
      final projection =
          bundle.projection ?? (retained ? _snapshot().value : bundle.shadow);
      if (bundle.syncContextJson != null) {
        if (!_hasSyncContext)
          throw const ContractViolation('sync-not-initialized');
        if ((jsonDecode(bundle.syncContextJson!) as Map)['checkpoint'] !=
            bundle.toCursor)
          throw const ContractViolation('sync-checkpoint-mismatch');
        _db.execute('UPDATE sync_context SET body=?,digest=?', [
          bundle.syncContextJson!,
          digest(bundle.syncContextJson!),
        ]);
      }
      _db.execute('UPDATE shadow SET snapshot=?,cursor=?', [
        _stored('shadow', bundle.shadow.json),
        bundle.toCursor,
      ]);
      _db.execute('UPDATE state SET revision=?,snapshot=?,digest=?', [
        revision,
        _stored('state', projection.json),
        projection.hash,
      ]);
      _db.execute('INSERT INTO journal VALUES (?,\'remote\',?,?)', [
        revision,
        bundle.id,
        projection.hash,
      ]);
      if (retained && bundle.projection == null) {
        _db.execute('INSERT INTO conflicts VALUES (?,?)', [
          'bundle:${bundle.id}',
          canonicalJson({
            'reason': 'pending-projection-rebase-required',
            'bundle': bundle.id,
            'commands': pending.map((p) => p.receipt.id).toList(),
          }),
        ]);
      }
      for (final entry in bundle.aliases.entries) {
        if (entry.key == entry.value ||
            entry.key.isEmpty ||
            entry.value.isEmpty)
          throw const ContractViolation('invalid-alias');
        final current = _db.select('SELECT target FROM aliases WHERE alias=?', [
          entry.key,
        ]);
        if (current.isNotEmpty && current.single['target'] != entry.value)
          throw const ContractViolation('alias-conflict');
        _db.execute('INSERT OR IGNORE INTO aliases VALUES (?,?)', [
          entry.key,
          entry.value,
        ]);
        final visited = <String>{entry.key};
        var next = entry.value;
        while (true) {
          if (!visited.add(next)) throw const ContractViolation('alias-cycle');
          final rows = _db.select('SELECT target FROM aliases WHERE alias=?', [
            next,
          ]);
          if (rows.isEmpty) break;
          next = rows.single['target'] as String;
        }
      }
      fault?.call('remote-before-checkpoint');
      _db.execute('UPDATE checkpoint SET cursor=?', [bundle.toCursor]);
      _db.execute('INSERT INTO bundles VALUES (?,?,?,?,?)', [
        bundle.id,
        digest(bundle.json),
        revision,
        bundle.toCursor,
        retained ? 1 : 0,
      ]);
      fault?.call('remote-before-commit');
      return RemoteApplyResult(revision, bundle.toCursor, retained);
    },
  );

  void verify() => SyntheticTrace.sync('storage.verify', _verify);
  void _verify() {
    if (_db.select('PRAGMA integrity_check').single.values.single != 'ok' ||
        _db.select('PRAGMA foreign_key_check').isNotEmpty)
      throw const ContractViolation('database-integrity');
    final identity = _db.select('SELECT * FROM identity').single;
    if (identity['partition'] != partition.key ||
        ![1, 2].contains(identity['format']))
      throw const ContractViolation('database-identity');
    final s = _snapshot(),
        journal = _db.select('SELECT * FROM journal ORDER BY revision');
    if (journal.length != s.revision + 1 ||
        journal.last['digest'] != s.value.hash)
      throw const ContractViolation('journal-state');
    for (var i = 0; i < journal.length; i++) {
      if (journal[i]['revision'] != i)
        throw const ContractViolation('journal-gap');
      if (journal[i]['kind'] == 'local') {
        final c = _db.select(
          'SELECT * FROM commands WHERE id=? AND revision=?',
          [journal[i]['reference'], i],
        );
        if (c.length != 1 ||
            jsonDecode(c.single['body'] as String)['snapshotDigest'] !=
                journal[i]['digest'])
          throw const ContractViolation('snapshot-without-command');
      }
    }
    for (final c in _db.select('SELECT * FROM commands')) {
      final body = c['body'] as String;
      final parsed = jsonDecode(body) as Map;
      final r = _receipt(c['id'] as String);
      if (digest(body) != c['digest'] ||
          parsed['partition'] != partition.key ||
          parsed['id'] != c['id'] ||
          parsed['base'] != (c['revision'] as int) - 1 ||
          r == null)
        throw const ContractViolation('command-corrupt');
      if (r.serverReceipt != null) {
        final receipt = jsonDecode(r.serverReceipt!) as Map;
        final persisted = _db.select(
          'SELECT body FROM receipts WHERE id=? AND command_id=?',
          [receipt['id'], r.id],
        );
        if (persisted.length != 1 ||
            persisted.single['body'] != r.serverReceipt ||
            receipt['digest'] != r.contentDigest ||
            receipt['partition'] != partition.key)
          throw const ContractViolation('receipt-corrupt');
      }
      if (r.remotelyAccepted && r.serverReceipt == null)
        throw const ContractViolation('accepted-without-receipt');
    }
    if (_db.select('SELECT cursor FROM shadow').single['cursor'] != _cursor)
      throw const ContractViolation('checkpoint-shadow');
    if (_hasSyncContext) {
      final shadow = _db
          .select('SELECT snapshot FROM shadow')
          .single['snapshot'];
      if (shadow != null)
        FinancialSnapshot(_restored('shadow', shadow as String));
      final row = _db.select('SELECT body,digest FROM sync_context').single;
      if (digest(row['body'] as String) != row['digest'] ||
          (jsonDecode(row['body'] as String) as Map)['checkpoint'] != _cursor)
        throw const ContractViolation('sync-context-integrity');
    }
    final descriptor = (_manifest['generations'] as Map)['$generation'] as Map;
    final minimum = descriptor['minimumRevision'] as int;
    if (s.revision < minimum ||
        (s.revision == minimum && descriptor['digest'] != s.value.hash))
      throw const ContractViolation('generation-rollback');
  }

  @override
  Future<CheckpointResult> checkpoint({String mode = 'PASSIVE'}) async {
    if (!['PASSIVE', 'TRUNCATE', 'FULL', 'RESTART'].contains(mode))
      throw ArgumentError('mode');
    final row = _db.select('PRAGMA wal_checkpoint($mode)').single;
    return CheckpointResult(
      row['busy'] as int,
      row['log'] as int,
      row['checkpointed'] as int,
    );
  }

  Future<CheckpointResult> maintain() =>
      _exclusive(() => _policy.maintain(idle: true));

  Future<ReaderLease> leaseReader({
    Duration duration = const Duration(seconds: 2),
  }) async {
    _usable();
    if (duration <= Duration.zero ||
        duration > const Duration(seconds: 10) ||
        _readers.length >= 4)
      throw const ContractViolation('reader-budget');
    final db = _openDatabase(directory, _manifest);
    db.execute('PRAGMA query_only=ON');
    db.execute('BEGIN');
    final row = db.select('SELECT revision,snapshot FROM state').single;
    late ReaderLease lease;
    lease = ReaderLease._(
      db,
      VersionedSnapshot(
        row['revision'] as int,
        FinancialSnapshot(
          _restored('state', row['snapshot'] as String, database: db),
        ),
      ),
      DateTime.now().add(duration),
      () => _readers.remove(lease),
    );
    _readers.add(lease);
    return lease;
  }

  void _releaseReaders() {
    for (final r in _readers.toList()) {
      r.close();
    }
  }

  Future<RecoveryPoint> _copyGeneration({required bool promote}) async {
    if (_policy.poisoned)
      throw const ContractViolation('reopen-before-maintenance');
    _releaseReaders();
    verify();
    final generations = _manifest['generations'] as Map;
    if (generations.length != 1)
      throw const ContractViolation('generation-retirement-required');
    final s = _snapshot(), next = generation + 1;
    if ((availableBytes?.call() ?? availableDiskBytes(path)) <
        256 * mib + 2 * fileBytes(path)) {
      throw StoragePressure('backup-disk-headroom');
    }
    final targetPath = '$directory/container-$next.db';
    if (File(targetPath).existsSync())
      throw const ContractViolation('orphan-generation');
    final key = randomKey();
    final staged = jsonDecode(jsonEncode(_manifest)) as Map<String, dynamic>;
    (staged['generations'] as Map)['$next'] = {
      'key': base64Encode(key),
      'minimumRevision': s.revision,
      'digest': s.value.hash,
    };
    _publish(_control, staged); // both keys durable before any encrypted copy
    _manifest = staged;
    fault?.call('rotation-after-keys');
    final target = openNative(targetPath, Candidate.directMc, key);
    try {
      await for (final _ in _db.backup(target, nPage: 8)) {
        fault?.call('rotation-during-copy');
      }
      if (target.select('PRAGMA integrity_check').single.values.single !=
              'ok' ||
          target.select('SELECT digest FROM state').single['digest'] !=
              s.value.hash ||
          target.select('SELECT count(*) n FROM commands').single['n'] !=
              _db.select('SELECT count(*) n FROM commands').single['n']) {
        throw const ContractViolation('backup-verification');
      }
    } finally {
      target.close();
    }
    final candidate = Map<String, dynamic>.from(staged)..['active'] = next;
    final checked = _openDatabase(directory, candidate);
    final original = _db, originalManifest = _manifest;
    _db = checked;
    _manifest = candidate;
    try {
      verify();
    } finally {
      _db = original;
      _manifest = originalManifest;
      checked.close();
    }
    fault?.call('rotation-after-copy');
    _publish(_recovery, promote ? staged : candidate);
    if (promote) {
      _publish(_control, candidate);
      fault?.call('rotation-after-promotion');
      _db.close();
      _manifest = candidate;
      _db = _openDatabase(directory, candidate);
      if (_readCacheBudget != null) _clearCaches();
      _policy = _newPolicy();
    }
    return RecoveryPoint(next, s.revision, s.value.hash);
  }

  Future<RecoveryPoint> _copySafely(bool promote) => _exclusive(() async {
    try {
      return await _copyGeneration(promote: promote);
    } catch (_) {
      _policy.poisoned = true;
      rethrow;
    }
  });
  @override
  Future<RecoveryPoint> backup() => _copySafely(false);
  @override
  Future<RecoveryPoint> rotateKey() => _copySafely(true);

  String _durabilityFingerprint() => digest(
    canonicalJson({
      for (final table in [
        'state',
        'journal',
        'commands',
        'delivery',
        'receipts',
        'shadow',
        'checkpoint',
        'aliases',
        'conflicts',
        'bundles',
        'migration',
        if (_hasSyncContext) 'sync_context',
        if (incremental) 'json_chunks',
      ])
        table: [
          for (final row in _db.select('SELECT * FROM $table ORDER BY 1'))
            Map<String, Object?>.from(row),
        ],
    }),
  );

  /// Explicit backup recovery must not hide newer readable commands/receipts.
  /// A corrupt alternative can only be recovered to a stated older point;
  /// its files and keys remain available for later forensic salvage.
  void _guardRecoveryAgainstOtherGenerations() {
    final selected = _db, manifest = _manifest;
    final revision = _snapshot().revision,
        fingerprint = _durabilityFingerprint();
    for (final id in (manifest['generations'] as Map).keys) {
      if (id == '${manifest['active']}') continue;
      sql.Database? candidate;
      var incompatible = false;
      try {
        final other = Map<String, dynamic>.from(manifest)
          ..['active'] = int.parse(id as String);
        candidate = _openDatabase(directory, other);
        _db = candidate;
        _manifest = other;
        verify();
        final otherRevision = _snapshot().revision;
        incompatible =
            otherRevision > revision ||
            (otherRevision == revision &&
                _durabilityFingerprint() != fingerprint);
      } catch (_) {
        // Explicit recovery only. Never overwrite/delete the unreadable source.
      } finally {
        _db = selected;
        _manifest = manifest;
        candidate?.close();
      }
      if (incompatible)
        throw const ContractViolation(
          'recovery-would-hide-newer-or-divergent-state',
        );
    }
  }

  @override
  Future<RecoveryPoint> recover() => _exclusive(() async {
    _releaseReaders();
    final candidate = _readManifest(_recovery, partition);
    final db = _openDatabase(directory, candidate);
    final old = _db, oldManifest = _manifest;
    _db = db;
    _manifest = candidate;
    try {
      verify();
      _guardRecoveryAgainstOtherGenerations();
      _publish(_control, candidate);
    } catch (_) {
      db.close();
      _db = old;
      _manifest = oldManifest;
      rethrow;
    }
    old.close();
    if (_readCacheBudget != null) _clearCaches();
    _policy = _newPolicy();
    final s = _snapshot();
    return RecoveryPoint(generation, s.revision, s.value.hash);
  });
  @override
  Future<void> close() => _exclusive(() async {
    _releaseReaders();
    _closed = true;
    if (_readCacheBudget != null) _clearCaches();
    try {
      _db.close();
    } finally {
      await _lock.close();
    }
  });
}

class ReaderLease {
  ReaderLease._(this._db, this._snapshot, this.expiresAt, this._onClose) {
    _timer = Timer(expiresAt.difference(DateTime.now()), close);
  }
  final sql.Database _db;
  final VersionedSnapshot _snapshot;
  final DateTime expiresAt;
  final void Function() _onClose;
  bool _closed = false;
  late final Timer _timer;
  VersionedSnapshot read() {
    if (_closed || DateTime.now().isAfter(expiresAt)) {
      close();
      throw const ContractViolation('reader-expired');
    }
    return _snapshot;
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _timer.cancel();
      _db.close();
      _onClose();
    }
  }
}
