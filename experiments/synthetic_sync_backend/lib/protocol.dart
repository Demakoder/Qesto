import 'dart:convert';
import 'package:crypto/crypto.dart';

const protocolVersion = 1;
const domainVersion = 1;
const experimentMarker = 'qesto.synthetic-sync.v1';
const maxBodyBytes = 16384;

class ApiError implements Exception {
  const ApiError(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => '$status:$code';
}

String canonicalJson(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sort(v[k])};
    }
    if (v is List) return v.map(sort).toList();
    return v;
  }

  return jsonEncode(sort(value));
}

String digest(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();
Map<String, dynamic> object(Object? value) {
  if (value is! Map<String, dynamic>)
    throw const ApiError(400, 'INVALID_OBJECT');
  return value;
}

void exactKeys(Map<String, dynamic> map, Set<String> keys) {
  if (map.length != keys.length || !map.keys.every(keys.contains)) {
    throw const ApiError(400, 'UNKNOWN_OR_MISSING_FIELD');
  }
}

String identifier(Object? v) {
  if (v is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,96}$').hasMatch(v)) {
    throw const ApiError(400, 'INVALID_IDENTIFIER');
  }
  return v;
}

int decimal(Object? v) {
  if (v is! String || !RegExp(r'^(0|[1-9][0-9]{0,17})$').hasMatch(v)) {
    throw const ApiError(400, 'INVALID_REVISION');
  }
  return int.parse(v);
}

void versions(Object? protocol, Object? domain) {
  if (protocol is! int ||
      domain is! int ||
      protocol != protocolVersion ||
      domain != domainVersion) {
    throw const ApiError(409, 'VERSION_MISMATCH');
  }
}

class NoteCommand {
  NoteCommand._(
    this.body,
    this.changeId,
    this.workspace,
    this.device,
    this.epoch,
    this.target,
    this.baseRevision,
    this.note,
  );
  factory NoteCommand.parse(Object? value) {
    final m = object(value);
    exactKeys(m, {
      'protocol_version',
      'domain_version',
      'workspace_id',
      'device_id',
      'workspace_epoch',
      'change_id',
      'kind',
      'transaction_id',
      'base_revision',
      'note',
    });
    versions(m['protocol_version'], m['domain_version']);
    if (m['kind'] != 'transaction.set_note')
      throw const ApiError(422, 'UNSUPPORTED_COMMAND');
    final note = m['note'];
    if (note is! String ||
        utf8.encode(note).length > 4096 ||
        note.contains('\u0000')) {
      throw const ApiError(400, 'INVALID_NOTE');
    }
    return NoteCommand._(
      Map.unmodifiable(m),
      identifier(m['change_id']),
      identifier(m['workspace_id']),
      identifier(m['device_id']),
      identifier(m['workspace_epoch']),
      identifier(m['transaction_id']),
      decimal(m['base_revision']),
      note,
    );
  }
  final Map<String, dynamic> body;
  final String changeId, workspace, device, epoch, target, note;
  final int baseRevision;
  String get contentDigest => digest(body);
}

class Principal {
  const Principal(this.token, this.user, this.device, this.workspace);
  final String token, user, device, workspace;
  void authorize(String w, String d) {
    if (w != workspace || d != device)
      throw const ApiError(403, 'FORBIDDEN_SCOPE');
  }
}

// Opaque authenticated cursor, not an authorization credential.
class CursorCodec {
  CursorCodec(this.key);
  final List<int> key;
  String encode(String workspace, String epoch, int after, int? high) {
    final payload = base64Url.encode(
      utf8.encode(
        canonicalJson({
          'w': workspace,
          'e': epoch,
          'p': protocolVersion,
          'd': domainVersion,
          'after': '$after',
          'high': high == null ? null : '$high',
        }),
      ),
    );
    return '$payload.${Hmac(sha256, key).convert(utf8.encode(payload))}';
  }

  ({int after, int? high}) decode(
    String token,
    String workspace,
    String epoch,
  ) {
    try {
      if (token.length > 2048) throw const FormatException();
      final parts = token.split('.');
      if (parts.length != 2) throw const FormatException();
      final expected = Hmac(
        sha256,
        key,
      ).convert(utf8.encode(parts[0])).toString();
      var mismatch = expected.length ^ parts[1].length;
      if (parts[1].length == expected.length) {
        for (var i = 0; i < expected.length; i++)
          mismatch |= expected.codeUnitAt(i) ^ parts[1].codeUnitAt(i);
      }
      if (mismatch != 0) throw const FormatException();
      final m = object(jsonDecode(utf8.decode(base64Url.decode(parts[0]))));
      if (m['w'] != workspace ||
          m['e'] != epoch ||
          m['p'] != protocolVersion ||
          m['d'] != domainVersion)
        throw const FormatException();
      return (
        after: decimal(m['after']),
        high: m['high'] == null ? null : decimal(m['high']),
      );
    } catch (_) {
      throw const ApiError(409, 'INVALID_CURSOR');
    }
  }
}
