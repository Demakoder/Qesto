import '../core/models.dart';

class AdapterHealth {
  const AdapterHealth({required this.healthy, this.message, this.checkedAt});

  final bool healthy;
  final String? message;
  final DateTime? checkedAt;
}

class AdaptedIngestion {
  const AdaptedIngestion({
    required this.rawPayload,
    required this.record,
    required this.candidates,
    this.receipts = const [],
    this.importBatch,
    this.accounts = const [],
    this.institutions = const [],
    this.connections = const [],
    this.consents = const [],
    this.warnings = const [],
  });

  final RawPayload rawPayload;
  final IngestionRecord record;
  final List<TransactionCandidate> candidates;
  final List<SynoballReceipt> receipts;
  final ImportBatch? importBatch;
  final List<SynoballAccount> accounts;
  final List<Institution> institutions;
  final List<SynoballConnection> connections;
  final List<SynoballConsent> consents;
  final List<String> warnings;
}

abstract interface class SynoballAdapter<T> {
  String get id;
  String get version;
  SynoballSourceType get sourceType;

  List<SynoballCapability> getCapabilities();
  AdapterHealth healthCheck();
  void validate(T input);
  AdaptedIngestion normalize(T input);

  AdaptedIngestion parse(T input) {
    validate(input);
    return normalize(input);
  }
}

abstract interface class PersistentSourceAdapter<T>
    implements SynoballAdapter<T> {
  Future<SynoballConnection> connect();
  Future<AdaptedIngestion> sync({String? cursor});
  Future<SynoballConnection> refreshAuthorization();
  Future<void> revoke();
}

class SynoballIdFactory {
  SynoballIdFactory({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  var _sequence = 0;
  static var _processSequence = 0;

  String next(String prefix) {
    _sequence += 1;
    _processSequence += 1;
    return '$prefix-${_clock().microsecondsSinceEpoch}-$_processSequence-$_sequence';
  }
}

class AdapterInputBase {
  const AdapterInputBase({
    required this.entityId,
    required this.receivedAt,
    required this.rawPayload,
    this.connectionId,
    this.institutionId,
  });

  final String entityId;
  final DateTime receivedAt;
  final String rawPayload;
  final String? connectionId;
  final String? institutionId;
}
