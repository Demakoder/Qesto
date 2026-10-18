/// Stage 4c storage representation, not a financial model or JSON patch engine.
/// Exact source bytes are reconstructed; the existing codec remains the model.
library;

import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'contract.dart';

class JsonChunks {
  const JsonChunks(this.parts);
  final List<String> parts;

  factory JsonChunks.split(String source) {
    // Deterministic lexical boundaries: every 32 record-level separators, plus
    // root fields. Unlike fixed byte offsets a changed note length does not
    // rewrite the suffix. Strings/escaped quotes/brackets are opaque.
    var quoted = false, escaped = false, depth = 0, records = 0, start = 0;
    final parts = <String>[];
    for (var i = 0; i < source.length; i++) {
      final c = source.codeUnitAt(i);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == 92) {
          escaped = true;
        } else if (c == 34) {
          quoted = false;
        }
        continue;
      }
      if (c == 34) {
        quoted = true;
        continue;
      }
      if (c == 91 || c == 123) depth++;
      if (c == 93 || c == 125) depth--;
      if (c == 44 && depth <= 3 && (depth <= 1 || ++records >= 32)) {
        parts.add(source.substring(start, i + 1));
        start = i + 1;
        records = 0;
      }
    }
    if (start < source.length) parts.add(source.substring(start));
    return JsonChunks(List.unmodifiable(parts));
  }
}

/// Rows + one ordered versioned manifest are authoritative. No full JSON copy
/// is persisted. All calls belong to the container's existing SQL transaction.
class ChunkedJsonStore {
  ChunkedJsonStore(this.db, {this.fault});
  final Database db;
  final void Function(String)? fault;
  int writtenBytes = 0, writtenChunks = 0;
  static void create(Database db) => db.execute(
    'CREATE TABLE json_chunks(scope TEXT NOT NULL, slot INTEGER NOT NULL, body TEXT NOT NULL, hash TEXT NOT NULL, PRIMARY KEY(scope,slot)) WITHOUT ROWID',
  );

  String write(String scope, String json) {
    final pieces = JsonChunks.split(json).parts;
    final previous = {
      for (final r in db.select(
        'SELECT slot,body,hash FROM json_chunks WHERE scope=?',
        [scope],
      ))
        r['slot'] as int: r,
    };
    final hashes = <String>[];
    final statement = db.prepare(
      'INSERT INTO json_chunks VALUES (?,?,?,?) ON CONFLICT(scope,slot) DO UPDATE SET body=excluded.body,hash=excluded.hash',
    );
    try {
      for (var i = 0; i < pieces.length; i++) {
        final body = pieces[i], old = previous[i];
        final same = old != null && old['body'] == body;
        final hash = same ? old['hash'] as String : digest(body);
        // Verify reused data too; accidental row/hash corruption must not be
        // blessed by a new manifest even when the body is unchanged.
        if (same && digest(body) != hash)
          throw const ContractViolation('chunk-corrupt');
        hashes.add(hash);
        if (!same) {
          statement.execute([scope, i, body, hash]);
          writtenChunks++;
          writtenBytes += utf8.encode(body).length;
          fault?.call('chunk-after-row');
        }
      }
      db.execute('DELETE FROM json_chunks WHERE scope=? AND slot>=?', [
        scope,
        pieces.length,
      ]);
    } finally {
      statement.close();
    }
    final manifest = jsonEncode({
      'chunk_format': 1,
      'scope': scope,
      'hashes': hashes,
      'digest': digest(json),
    });
    writtenBytes += utf8.encode(manifest).length;
    return manifest;
  }

  String read(String scope, String manifest) {
    final m = jsonDecode(manifest) as Map;
    if (m['chunk_format'] != 1 || m['scope'] != scope || m['hashes'] is! List) {
      throw const ContractViolation('chunk-manifest');
    }
    final hashes = m['hashes'] as List;
    final rows = db.select(
      'SELECT slot,body,hash FROM json_chunks WHERE scope=? ORDER BY slot',
      [scope],
    );
    if (rows.length != hashes.length)
      throw const ContractViolation('chunk-count');
    final out = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i], body = r['body'] as String;
      if (r['slot'] != i ||
          r['hash'] != hashes[i] ||
          digest(body) != hashes[i]) {
        throw const ContractViolation('chunk-corrupt');
      }
      out.write(body);
    }
    final json = out.toString();
    if (digest(json) != m['digest'])
      throw const ContractViolation('chunk-root-digest');
    return json;
  }
}
