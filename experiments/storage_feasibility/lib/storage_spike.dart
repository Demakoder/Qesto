/// EXPERIMENT ONLY. Not imported by Qesto; not a production schema or migration.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

enum Candidate { driftMc, directMc, payloadGcm }

enum Fault { beforeTransaction, afterSnapshot, afterOutbox, afterCommit }

const marker = 'QESTO_SYNTHETIC_SECRET_NO_REAL_FINANCIAL_DATA';

Uint8List randomKey() =>
    Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)));

Directory createSpikeDirectory() {
  final dir = Directory.systemTemp.createTempSync('qesto-storage-spike-');
  File('${dir.path}/.qesto-storage-spike').writeAsStringSync('synthetic-only');
  return dir;
}

void requireOwnedPath(String path) {
  final parent = File(path).absolute.parent;
  if (!parent.path.contains('qesto-storage-spike-') ||
      !File('${parent.path}/.qesto-storage-spike').existsSync()) {
    throw StateError(
      'Only explicitly marked synthetic spike directories allowed',
    );
  }
}

bool walResetFixed(int version) =>
    version >= 3051003 || version == 3050007 || version == 3044006;

/// All release checks throw, never rely on assert. Key is never logged.
sql.Database openNative(String path, Candidate candidate, List<int>? key) {
  requireOwnedPath(path);
  if (key == null || key.length != 32) {
    throw StateError('An existing 256-bit key is required; never regenerate');
  }
  final db = sql.sqlite3.open(path);
  try {
    if (!walResetFixed(sql.sqlite3.version.versionNumber)) {
      throw StateError('Native SQLite does not satisfy WAL-reset fix gate');
    }
    final hasCipher = db.select('PRAGMA cipher').isNotEmpty;
    if (candidate != Candidate.payloadGcm) {
      if (!hasCipher)
        throw StateError('Encrypted library required; no fallback');
      db.execute("PRAGMA cipher = 'sqlcipher'");
      db.execute('PRAGMA hmac_check = 1');
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute('PRAGMA key = "x\'$hex\'"');
      // Setting PRAGMA key alone does not validate the key.
      db.select('SELECT count(*) FROM sqlite_master');
    } else if (hasCipher) {
      throw StateError('Candidate C must be measured with ordinary SQLite');
    }
    db.execute('PRAGMA busy_timeout = 3000');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA temp_store = MEMORY');
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

abstract class Engine {
  Future<void> execute(String query, [List<Object?> args = const []]);
  Future<List<Map<String, Object?>>> select(
    String query, [
    List<Object?> args = const [],
  ]);
  Future<T> transaction<T>(Future<T> Function() body);
  Future<void> close();
}

class DirectEngine implements Engine {
  DirectEngine(this.raw);
  final sql.Database raw;
  @override
  Future<void> execute(String query, [List<Object?> args = const []]) async =>
      raw.execute(query, args);
  @override
  Future<List<Map<String, Object?>>> select(
    String query, [
    List<Object?> args = const [],
  ]) async => [for (final row in raw.select(query, args)) Map.of(row)];
  @override
  Future<T> transaction<T>(Future<T> Function() body) async {
    raw.execute('BEGIN IMMEDIATE');
    try {
      final value = await body();
      raw.execute('COMMIT');
      return value;
    } catch (_) {
      // FULL/IOERR can already roll the transaction back. Cleanup must not
      // replace the original storage error with 'no transaction is active'.
      if (!raw.autocommit) {
        try {
          raw.execute('ROLLBACK');
        } catch (_) {
          // Caller must close/reopen after an I/O failure before retrying.
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> close() async => raw.close();
}

class _DriftDb extends drift.GeneratedDatabase {
  _DriftDb(sql.Database raw) : super(NativeDatabase.opened(raw));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<drift.TableInfo> get allTables => const [];
}

class DriftEngine implements Engine {
  DriftEngine(sql.Database raw) : db = _DriftDb(raw);
  final _DriftDb db;
  @override
  Future<void> execute(String query, [List<Object?> args = const []]) =>
      db.customStatement(query, args);
  @override
  Future<List<Map<String, Object?>>> select(
    String query, [
    List<Object?> args = const [],
  ]) async => [
    for (final row
        in await db
            .customSelect(
              query,
              variables: [
                for (final arg in args)
                  switch (arg) {
                    int v => drift.Variable.withInt(v),
                    String v => drift.Variable.withString(v),
                    Uint8List v => drift.Variable.withBlob(v),
                    _ => throw StateError('Unsupported experimental parameter'),
                  },
              ],
            )
            .get())
      row.data,
  ];
  @override
  Future<T> transaction<T>(Future<T> Function() body) => db.transaction(body);
  @override
  Future<void> close() => db.close();
}

const schema = [
  'CREATE TABLE IF NOT EXISTS key_guard(id INTEGER PRIMARY KEY, value BLOB NOT NULL)',
  'CREATE TABLE IF NOT EXISTS state(id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, snapshot BLOB NOT NULL)',
  'CREATE TABLE IF NOT EXISTS outbox(id TEXT PRIMARY KEY, revision INTEGER NOT NULL UNIQUE, payload BLOB NOT NULL)',
  'CREATE TRIGGER IF NOT EXISTS immutable_outbox_update BEFORE UPDATE ON outbox BEGIN SELECT RAISE(ABORT,\'immutable command\'); END',
  'CREATE TRIGGER IF NOT EXISTS immutable_outbox_delete BEFORE DELETE ON outbox BEGIN SELECT RAISE(ABORT,\'immutable command\'); END',
  'CREATE TABLE IF NOT EXISTS sync_meta(kind TEXT PRIMARY KEY, payload BLOB NOT NULL)',
];

class StaleRevision implements Exception {}

class CommandCollision implements Exception {}

class CheckpointResult {
  const CheckpointResult(this.busy, this.frames, this.checkpointed);
  final int busy;
  final int frames;
  final int checkpointed;
  int get pending => max(0, frames - checkpointed);
  Map<String, int> toJson() => {
    'busy': busy,
    'frames': frames,
    'checkpointed': checkpointed,
  };
}

abstract interface class CheckpointStore {
  String get path;
  sql.Database get raw;
  Future<CheckpointResult> checkpoint({String mode = 'PASSIVE'});
}

class SpikeStore implements CheckpointStore {
  SpikeStore._(this.path, this.candidate, this.key, this.raw, this.engine);
  final String path;
  final Candidate candidate;
  final List<int> key;
  final sql.Database raw;
  final Engine engine;
  static final _cipher = AesGcm.with256bits();

  static Future<SpikeStore> open(
    String path,
    Candidate candidate,
    List<int>? key, {
    String journal = 'WAL',
    int autoCheckpointPages = 0,
  }) async {
    if (journal != 'WAL' && journal != 'DELETE') throw ArgumentError('journal');
    final existed = File(path).existsSync();
    final raw = openNative(path, candidate, key);
    final engine = candidate == Candidate.driftMc
        ? DriftEngine(raw)
        : DirectEngine(raw);
    final store = SpikeStore._(path, candidate, List.of(key!), raw, engine);
    try {
      // Authenticate C before performing any schema changes on an existing DB.
      final hasGuard = raw
          .select("SELECT name FROM sqlite_master WHERE name='key_guard'")
          .isNotEmpty;
      if (existed && !hasGuard)
        throw StateError(
          'Existing database has no authenticated experiment identity; recovery required',
        );
      if (hasGuard) {
        final guard = raw
            .select('SELECT value FROM key_guard WHERE id=1')
            .single;
        if (await store.decode('key-guard', guard['value'] as List<int>) !=
            marker) {
          throw StateError('Key validation failed');
        }
      }
      raw.execute('PRAGMA journal_mode = $journal');
      raw.execute('PRAGMA synchronous = FULL');
      if (autoCheckpointPages < 0) throw ArgumentError('autoCheckpointPages');
      raw.execute('PRAGMA wal_autocheckpoint = $autoCheckpointPages');
      await engine.transaction(() async {
        for (final statement in schema) {
          await engine.execute(statement);
        }
        if ((await engine.select('SELECT id FROM key_guard')).isEmpty) {
          await engine.execute('INSERT INTO key_guard VALUES (1, ?)', [
            await store.encode('key-guard', marker),
          ]);
        }
      });
      return store;
    } catch (_) {
      try {
        await engine.close();
      } finally {
        raw.close();
      }
      rethrow;
    }
  }

  Future<Uint8List> encode(String aad, String value) async {
    final bytes = utf8.encode(value);
    if (candidate != Candidate.payloadGcm) return Uint8List.fromList(bytes);
    final box = await _cipher.encrypt(
      bytes,
      secretKey: SecretKey(key),
      aad: utf8.encode('qesto-spike-v1:$aad'),
    );
    return Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<String> decode(String aad, List<int> value) async {
    if (candidate != Candidate.payloadGcm) return utf8.decode(value);
    if (value.length < 28) throw StateError('Invalid encrypted payload');
    final box = SecretBox(
      value.sublist(12, value.length - 16),
      nonce: value.sublist(0, 12),
      mac: Mac(value.sublist(value.length - 16)),
    );
    return utf8.decode(
      await _cipher.decrypt(
        box,
        secretKey: SecretKey(key),
        aad: utf8.encode('qesto-spike-v1:$aad'),
      ),
    );
  }

  Future<int> revision() async {
    final rows = await engine.select('SELECT revision FROM state WHERE id=1');
    return rows.isEmpty ? 0 : rows.single['revision'] as int;
  }

  Future<String?> snapshot() async {
    final rows = await engine.select(
      'SELECT revision,snapshot FROM state WHERE id=1',
    );
    if (rows.isEmpty) return null;
    return decode(
      'snapshot:${rows.single['revision']}',
      rows.single['snapshot'] as List<int>,
    );
  }

  /// Immutable command contains only synthetic data, not Synoball events.
  /// All derived encrypted payloads are staged before the transaction starts.
  Future<int> apply({
    required String id,
    required int expected,
    required String snapshot,
    String intent = 'synthetic batch',
    void Function(Fault)? fault,
  }) async {
    final next = expected + 1;
    final command = jsonEncode({
      'id': id,
      'expected': expected,
      'snapshotDigest': hashes.sha256.convert(utf8.encode(snapshot)).toString(),
      'intent': intent,
    });
    final encryptedSnapshot = await encode('snapshot:$next', snapshot);
    final encryptedCommand = await encode('outbox:$id', command);
    final encryptedMeta = <String, Uint8List>{};
    for (final kind in ['checkpoint', 'server-shadow', 'conflict-proposals']) {
      encryptedMeta[kind] = await encode(
        'meta:$kind',
        jsonEncode({'revision': next, 'synthetic': marker, 'kind': kind}),
      );
    }
    fault?.call(Fault.beforeTransaction);
    final committed = await engine.transaction(() async {
      final previous = await engine.select(
        'SELECT revision,payload FROM outbox WHERE id=?',
        [id],
      );
      if (previous.isNotEmpty) {
        if (await decode(
              'outbox:$id',
              previous.single['payload'] as List<int>,
            ) !=
            command) {
          throw CommandCollision();
        }
        return previous.single['revision'] as int;
      }
      if (await revision() != expected) throw StaleRevision();
      await engine.execute('INSERT OR REPLACE INTO state VALUES(1,?,?)', [
        next,
        encryptedSnapshot,
      ]);
      fault?.call(Fault.afterSnapshot);
      await engine.execute('INSERT INTO outbox VALUES(?,?,?)', [
        id,
        next,
        encryptedCommand,
      ]);
      for (final entry in encryptedMeta.entries) {
        await engine.execute('INSERT OR REPLACE INTO sync_meta VALUES(?,?)', [
          entry.key,
          entry.value,
        ]);
      }
      fault?.call(Fault.afterOutbox);
      return next;
    });
    // A thrown error or process exit here represents a lost ACK, not rollback.
    fault?.call(Fault.afterCommit);
    return committed;
  }

  Future<void> verify() async {
    if ((await engine.select('PRAGMA integrity_check')).single.values.single !=
        'ok') {
      throw StateError('Integrity check failed');
    }
    final rev = await revision();
    final commands = await engine.select(
      'SELECT id,revision,payload FROM outbox ORDER BY revision',
    );
    if (commands.length != rev) throw StateError('Snapshot/outbox mismatch');
    for (var i = 0; i < commands.length; i++) {
      if (commands[i]['revision'] != i + 1) throw StateError('Revision gap');
      await decode(
        'outbox:${commands[i]['id']}',
        commands[i]['payload'] as List<int>,
      );
    }
    final value = await snapshot();
    if (rev > 0 && (value == null || commands.isEmpty))
      throw StateError('Lost snapshot');
    if (rev > 0) {
      final latest =
          jsonDecode(
                await decode(
                  'outbox:${commands.last['id']}',
                  commands.last['payload'] as List<int>,
                ),
              )
              as Map;
      if (latest['snapshotDigest'] !=
          hashes.sha256.convert(utf8.encode(value!)).toString()) {
        throw StateError('Snapshot digest mismatch');
      }
      final metadata = await engine.select(
        'SELECT kind,payload FROM sync_meta',
      );
      if (metadata.length != 3) throw StateError('Lost transactional metadata');
      for (final row in metadata) {
        final meta =
            jsonDecode(
                  await decode(
                    'meta:${row['kind']}',
                    row['payload'] as List<int>,
                  ),
                )
                as Map;
        if (meta['revision'] != rev) throw StateError('Non-atomic metadata');
      }
    }
  }

  Future<CheckpointResult> checkpoint({String mode = 'TRUNCATE'}) async {
    if (!const ['PASSIVE', 'FULL', 'RESTART', 'TRUNCATE'].contains(mode)) {
      throw ArgumentError('checkpoint mode');
    }
    final row = (await engine.select('PRAGMA wal_checkpoint($mode)')).single;
    return CheckpointResult(
      row.values.elementAt(0) as int,
      row.values.elementAt(1) as int,
      row.values.elementAt(2) as int,
    );
  }

  /// Online backup targets a keyed database, then reopens and validates it.
  /// A file copy without a recoverable key is deliberately not called a backup.
  Future<void> backup(String target, {void Function(double)? progress}) async {
    requireOwnedPath(target);
    if (File(target).existsSync())
      throw StateError('Backup target must be new');
    final other = openNative(target, candidate, key);
    try {
      await for (final percent in raw.backup(other, nPage: 8)) {
        progress?.call(percent);
      }
    } finally {
      other.close();
    }
    final restored = await SpikeStore.open(target, candidate, key);
    try {
      await restored.verify();
    } finally {
      await restored.close();
    }
  }

  Future<void> close() async {
    // NativeDatabase.opened may never take ownership if validation fails first.
    // sqlite3 close is idempotent; explicitly release even an unopened delegate.
    try {
      await engine.close();
    } finally {
      raw.close();
    }
  }

  /// DB-only rotation experiment, NOT an atomic DB + platform-vault protocol.
  /// Caller must retain both keys until the new database can be reopened.
  Future<void> rotateKey(List<int> replacement) async {
    if (replacement.length != 32) throw ArgumentError('256-bit key required');
    final cp = await checkpoint();
    if (cp.busy != 0 || cp.pending > 0) {
      throw StateError('Key rotation requires a completed checkpoint');
    }
    if (candidate != Candidate.payloadGcm) {
      raw.execute("PRAGMA cipher = 'sqlcipher'");
      final hex = replacement
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join();
      raw.execute('PRAGMA rekey = "x\'$hex\'"');
    } else {
      final updates =
          <
            ({
              String table,
              String column,
              String where,
              List<Object?> args,
              String aad,
              String value,
            })
          >[];
      final guard = (await engine.select(
        'SELECT value FROM key_guard WHERE id=1',
      )).single;
      updates.add((
        table: 'key_guard',
        column: 'value',
        where: 'id=1',
        args: [],
        aad: 'key-guard',
        value: await decode('key-guard', guard['value'] as List<int>),
      ));
      for (final row in await engine.select(
        'SELECT revision,snapshot FROM state',
      )) {
        final aad = 'snapshot:${row['revision']}';
        updates.add((
          table: 'state',
          column: 'snapshot',
          where: 'id=1',
          args: [],
          aad: aad,
          value: await decode(aad, row['snapshot'] as List<int>),
        ));
      }
      for (final table in ['outbox', 'sync_meta']) {
        final identifier = table == 'outbox' ? 'id' : 'kind';
        for (final row in await engine.select(
          'SELECT $identifier,payload FROM $table',
        )) {
          final aad = table == 'outbox'
              ? 'outbox:${row[identifier]}'
              : 'meta:${row[identifier]}';
          updates.add((
            table: table,
            column: 'payload',
            where: '$identifier=?',
            args: [row[identifier]],
            aad: aad,
            value: await decode(aad, row['payload'] as List<int>),
          ));
        }
      }
      final staged = <Uint8List>[];
      for (final update in updates) {
        final box = await _cipher.encrypt(
          utf8.encode(update.value),
          secretKey: SecretKey(replacement),
          aad: utf8.encode('qesto-spike-v1:${update.aad}'),
        );
        staged.add(
          Uint8List.fromList([
            ...box.nonce,
            ...box.cipherText,
            ...box.mac.bytes,
          ]),
        );
      }
      await engine.transaction(() async {
        // Ciphertext changes only; immutable logical commands stay identical.
        await engine.execute('DROP TRIGGER immutable_outbox_update');
        for (var i = 0; i < updates.length; i++) {
          final u = updates[i];
          await engine.execute(
            'UPDATE ${u.table} SET ${u.column}=? WHERE ${u.where}',
            [staged[i], ...u.args],
          );
        }
        await engine.execute(schema[3]);
      });
    }
    key
      ..clear()
      ..addAll(replacement);
  }
}

/// Uses the real shared model/serializer; no financial algorithm is duplicated.
/// A Synoball state, NOT a complete UserFinancialDataCodec v7 user profile.
String syntheticSnapshot(int count, {int editVersion = 0}) {
  final time = DateTime.utc(2026, 10, 9);
  return jsonEncode(
    SynoballState(
      transactions: [
        for (var i = 0; i < count; i++)
          CanonicalTransaction(
            id: 'synthetic-$i',
            entityId: 'synthetic-owner',
            accountId: 'synthetic-RUB',
            status: CanonicalTransactionStatus.posted,
            amount: Money(
              minorUnits: i % 10000 + 1,
              currency: i % 11 == 0 ? 'USD' : 'RUB',
            ),
            direction: i % 7 == 0
                ? FinancialDirection.inflow
                : FinancialDirection.outflow,
            occurredAt: time.subtract(Duration(minutes: i)),
            rawDescription: marker,
            userNote: editVersion > 0 && i < 100
                ? 'synthetic batch edit $editVersion'
                : null,
            normalizedDescription: marker,
            eventType: FinancialEventType.observed,
            createdAt: time,
            updatedAt: time,
            fieldTrust: SourceTrustLevel.bankStatement,
          ),
      ],
    ).toJson(),
  );
}
