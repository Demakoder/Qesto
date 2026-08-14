import 'clock.dart';

class OpenBankingAuditEvent {
  const OpenBankingAuditEvent({
    required this.eventType,
    required this.outcome,
    required this.occurredAt,
    this.providerId,
    this.consentId,
    this.interactionId,
    this.errorCode,
  });

  final String eventType;
  final String outcome;
  final DateTime occurredAt;
  final String? providerId;
  final String? consentId;
  final String? interactionId;
  final String? errorCode;

  Map<String, Object?> toJson() => {
    'eventType': eventType,
    'outcome': outcome,
    'occurredAt': occurredAt.toIso8601String(),
    'providerId': providerId,
    'consentId': consentId,
    'interactionId': interactionId,
    'errorCode': errorCode,
  };
}

abstract interface class OpenBankingAuditSink {
  void record(OpenBankingAuditEvent event);
}

class InMemoryOpenBankingAuditSink implements OpenBankingAuditSink {
  final List<OpenBankingAuditEvent> events = [];

  @override
  void record(OpenBankingAuditEvent event) => events.add(event);
}

class OpenBankingAuditor {
  const OpenBankingAuditor(this.clock, this.sink);

  final OpenBankingClock clock;
  final OpenBankingAuditSink sink;

  void record({
    required String eventType,
    required String outcome,
    String? providerId,
    String? consentId,
    String? interactionId,
    String? errorCode,
  }) {
    sink.record(
      OpenBankingAuditEvent(
        eventType: eventType,
        outcome: outcome,
        occurredAt: clock.now(),
        providerId: providerId,
        consentId: consentId,
        interactionId: interactionId,
        errorCode: errorCode,
      ),
    );
  }
}
