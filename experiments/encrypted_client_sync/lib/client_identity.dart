import 'package:qesto_synthetic_sync/protocol.dart' as w;

/// Synthetic CLI credentials only. A client never receives the server's DB
/// password, cursor signing key, or another device's bearer token.
class ClientIdentity {
  ClientIdentity._(this.principal, this.epoch);
  factory ClientIdentity.parse(Object? value, int index) {
    final m = w.object(value);
    w.exactKeys(m, {
      'marker',
      'index',
      'token',
      'user',
      'device',
      'workspace',
      'epoch',
    });
    if (m['marker'] != 'qesto.encrypted-sync-client.v1' ||
        m['index'] != index ||
        m['token'] is! String ||
        (m['token'] as String).length < 32)
      throw const w.ApiError(400, 'INVALID_TEST_CLIENT_IDENTITY');
    return ClientIdentity._(
      w.Principal(
        m['token'] as String,
        w.identifier(m['user']),
        w.identifier(m['device']),
        w.identifier(m['workspace']),
      ),
      w.identifier(m['epoch']),
    );
  }
  final w.Principal principal;
  final String epoch;
}
