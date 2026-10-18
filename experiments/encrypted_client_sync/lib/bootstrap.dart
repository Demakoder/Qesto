import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_synthetic_sync/domain.dart';
import 'profile_adapter.dart';
import 'coordinator_domain.dart';

/// Explicit fixture bootstrap, never recovery or production migration. Both
/// clients are seeded from the same known synthetic epoch at server head zero.
Future<void> bootstrap(
  String directory,
  FinancialSnapshot fixture,
  w.Principal p,
  Map<String, dynamic> server, {
  CoordinatorDomain domain = const LegacyCoordinatorDomain(),
  bool incremental = false,
}) async {
  domain.validateHeader(server);
  w.versions(server['protocol_version'], server['domain_version']);
  if (server['workspace_id'] != p.workspace || server['head'] != '0')
    throw const ContractViolation('bootstrap-requires-fresh-synthetic-epoch');
  final epoch = w.identifier(server['workspace_epoch']);
  final local = ProfileAdapter.core(fixture);
  final expected = {
    for (final t in local.transactions) t.id: transactionWire(t),
  };
  final actual = <String, Object?>{}, revisions = <String, String>{};
  for (final raw in server['entities'] as List) {
    final e = w.object(raw), t = ProfileAdapter.decodeEntity(e);
    if (t.entityId != domain.entityFor(p.user) ||
        actual.containsKey(t.id) ||
        e['revision'] != '0')
      throw const ContractViolation('bootstrap-entity-mismatch');
    actual[t.id] = e['transaction'];
    revisions[t.id] = '0';
  }
  if (canonicalJson(actual) != canonicalJson(expected))
    throw const ContractViolation('bootstrap-fixture-not-identical');
  final partition = Partition(p.workspace, epoch);
  final store = await SqliteContainer.migrate(
    directory,
    MigrationManifest('synthetic-3b-${p.device}', partition, fixture.hash),
    fixture,
    incremental: incremental,
  );
  try {
    await store.initializeRemoteContext(
      canonicalJson({
        'format': 1,
        'checkpoint': 0,
        'workspace': p.workspace,
        'owner': p.user,
        'device': p.device,
        'epoch': epoch,
        'cursor': server['cursor'],
        'revisions': revisions,
        'pages': {},
        if (server.containsKey('financial_profile'))
          'financial_profile': server['financial_profile'],
        if (server.containsKey('policy_digest'))
          'policy_digest': server['policy_digest'],
      }),
    );
  } finally {
    await store.close();
  }
}
