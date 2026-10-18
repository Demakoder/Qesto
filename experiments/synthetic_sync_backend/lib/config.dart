import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'protocol.dart';

class TestConfig {
  TestConfig(this.json) {
    if (json['marker'] != experimentMarker ||
        json['database'] != 'qesto_synthetic') {
      throw StateError('Only the isolated synthetic database is allowed');
    }
    if ((json['principals'] as List).isEmpty)
      throw StateError('Missing test identities');
    if (base64Decode(json['cursor_key'] as String).length < 32)
      throw StateError('Weak cursor key');
    for (final p in principals) {
      if (p.token.length < 32) throw StateError('Weak test token');
    }
    if (principals.map((p) => p.token).toSet().length != principals.length)
      throw StateError('Duplicate tokens');
  }
  factory TestConfig.read(String path) =>
      TestConfig(object(jsonDecode(File(path).readAsStringSync())));
  final Map<String, dynamic> json;
  List<Principal> get principals => (json['principals'] as List)
      .map(
        (p) => Principal(
          p['token'] as String,
          identifier(p['user']),
          identifier(p['device']),
          identifier(p['workspace']),
        ),
      )
      .toList();
  CursorCodec get cursors =>
      CursorCodec(base64Decode(json['cursor_key'] as String));
  Future<Connection> connect({bool admin = false}) => Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: json['pg_port'] as int,
      database: 'qesto_synthetic',
      username: admin ? 'qesto_admin' : 'qesto_sync',
      password: json[admin ? 'admin_password' : 'db_password'] as String,
    ),
    settings: ConnectionSettings(
      sslMode: SslMode.disable,
      connectTimeout: const Duration(seconds: 5),
      queryTimeout: const Duration(seconds: 15),
    ),
  );
}
