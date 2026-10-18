import 'package:qesto_synthetic_sync/protocol.dart';
import 'package:qesto_encrypted_sync_experiment/coordinator_domain.dart';

/// Only the client's own token and public synthetic binding enter the worker.
/// No server config, DB password, signing key or another device token.
class NoteSyncBinding {
  const NoteSyncBinding({
    required this.principal,
    required this.endpoint,
    required this.domain,
    this.bootstrapResponse,
  });
  final Principal principal;
  final Uri endpoint;
  final CoordinatorDomain domain;
  final Map<String, dynamic>? bootstrapResponse;
}
