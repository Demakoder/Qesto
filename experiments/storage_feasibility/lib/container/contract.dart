/// Experimental, local-only API. No SQL or financial rule is exposed here.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';

String digest(String bytes) => sha256.convert(utf8.encode(bytes)).toString();
String canonicalJson(Object? value) {
  Object? sort(Object? v) => switch (v) {
    Map m => {
      for (final k in (m.keys.cast<String>().toList()..sort())) k: sort(m[k]),
    },
    List l => l.map(sort).toList(),
    _ => v,
  };
  return jsonEncode(sort(value));
}

class Partition {
  const Partition(this.workspace, this.lineage);
  final String workspace, lineage;
  String get key => canonicalJson({'workspace': workspace, 'lineage': lineage});
}

/// Bytes are produced/validated by the existing codec outside storage. The
/// version tag is checked here; this is not a second UserFinancialDataCodec.
class FinancialSnapshot {
  FinancialSnapshot(this.json) {
    if ((jsonDecode(json) as Map)['schemaVersion'] != 7) {
      throw FormatException('Only codec v7 is supported by this experiment');
    }
  }
  final String json;
  late final String hash = digest(json);
}

class VersionedSnapshot {
  const VersionedSnapshot(this.revision, this.value);
  final int revision;
  final FinancialSnapshot value;
}

class Mutation {
  Mutation({
    required this.id,
    required this.partition,
    required this.expectedRevision,
    required this.snapshot,
    required String intentJson,
    List<String> dependencies = const [],
  }) : intentJson = canonicalJson(jsonDecode(intentJson)),
       dependencies = List.unmodifiable(dependencies);
  final String id, intentJson;
  final Partition partition;
  final int expectedRevision;
  final FinancialSnapshot snapshot;
  final List<String> dependencies;
  late final String immutableJson = canonicalJson({
    'format': 1,
    'id': id,
    'partition': partition.key,
    'base': expectedRevision,
    'snapshotDigest': snapshot.hash,
    'intent': jsonDecode(intentJson),
    'dependencies': dependencies,
  });
}

enum DeliveryState {
  queued,
  inFlight,
  accepted,
  conflict,
  blockedDependency,
  rejectedRequiringAttention,
  pausedAuthentication,
}

class CommandReceipt {
  const CommandReceipt(
    this.id,
    this.revision,
    this.state,
    this.contentDigest, {
    this.serverReceipt,
  });
  final String id, contentDigest;
  final int revision;
  final DeliveryState state;
  final String? serverReceipt;
  bool get locallyDurable => true;
  bool get remotelyAccepted => state == DeliveryState.accepted;
}

class PendingCommand {
  const PendingCommand(this.receipt, this.immutableJson, this.attempts);
  final CommandReceipt receipt;
  final String immutableJson;
  final int attempts;
}

class SyntheticReceipt {
  const SyntheticReceipt(
    this.id,
    this.commandId,
    this.partition,
    this.contentDigest,
    this.state,
    this.payloadJson,
  );
  final String id, commandId, contentDigest, payloadJson;
  final Partition partition;
  final DeliveryState state;
  String get json => canonicalJson({
    'id': id,
    'command': commandId,
    'partition': partition.key,
    'digest': contentDigest,
    'state': state.name,
    'payload': jsonDecode(payloadJson),
  });
}

class RemoteBundle {
  RemoteBundle({
    required this.id,
    required this.partition,
    required this.fromCursor,
    required this.toCursor,
    required this.expectedRevision,
    required this.shadow,
    Map<String, String> aliases = const {},
    List<String> coveredCommands = const [],
    this.protocolVersion = 1,
    this.projection,
    this.syncContextJson,
    List<SyntheticReceipt> receipts = const [],
  }) : aliases = Map.unmodifiable(aliases),
       receipts = List.unmodifiable(receipts),
       coveredCommands = List.unmodifiable(coveredCommands);
  final String id;
  final Partition partition;
  final int fromCursor, toCursor, expectedRevision, protocolVersion;
  final FinancialSnapshot shadow;
  // Optional Stage 3b extension. Caller proves the note-only pending overlay;
  // the old conservative whole-snapshot policy is unchanged when omitted.
  final FinancialSnapshot? projection;
  final String? syncContextJson;
  final Map<String, String> aliases;
  final List<String> coveredCommands;
  final List<SyntheticReceipt> receipts;
  // expectedRevision is a local CAS precondition, not part of remote identity.
  String get json => canonicalJson({
    'id': id,
    'partition': partition.key,
    'from': fromCursor,
    'to': toCursor,
    'version': protocolVersion,
    'shadow': shadow.hash,
    'aliases': aliases,
    'coveredCommands': coveredCommands,
    if (projection != null) 'projection': projection!.hash,
    if (syncContextJson != null) 'syncContext': digest(syncContextJson!),
    if (receipts.isNotEmpty)
      'receipts': receipts.map((r) => jsonDecode(r.json)).toList(),
  });
}

class RemoteContext {
  const RemoteContext(this.json, this.shadow);
  final String json;
  final FinancialSnapshot shadow;
}

/// Optional experiment extension; not a production storage schema/API migration.
abstract interface class SyncTransactionContainer
    implements TransactionContainer {
  Future<RemoteContext?> readRemoteContext();
  Future<void> initializeRemoteContext(String json);
}

class RemoteApplyResult {
  const RemoteApplyResult(
    this.revision,
    this.cursor,
    this.localProjectionRetained,
  );
  final int revision, cursor;
  final bool localProjectionRetained;
}

class MigrationManifest {
  const MigrationManifest(this.id, this.partition, this.sourceDigest);
  final String id, sourceDigest;
  final Partition partition;
  String get json => canonicalJson({
    'id': id,
    'partition': partition.key,
    'codec': 7,
    'sourceDigest': sourceDigest,
  });
}

class RecoveryPoint {
  const RecoveryPoint(this.generation, this.revision, this.digest);
  final int generation, revision;
  final String digest;
}

class ContractViolation implements Exception {
  const ContractViolation(this.code);
  final String code;
  @override
  String toString() => 'TransactionContainer: $code';
}

abstract interface class TransactionContainer {
  Future<VersionedSnapshot> readSnapshot();
  Future<CommandReceipt> commitMutation(Mutation mutation);
  Future<CommandReceipt?> lookupCommandReceipt(String id);
  Future<List<PendingCommand>> readPendingCommands();
  Future<void> markCommandAcknowledged(SyntheticReceipt receipt);
  Future<RemoteApplyResult> applyRemoteBundle(RemoteBundle bundle);
  Future<int> readCheckpoint();
  Future<RecoveryPoint> backup();
  Future<RecoveryPoint> recover();
  Future<RecoveryPoint> rotateKey();
  Future<void> close();
}
