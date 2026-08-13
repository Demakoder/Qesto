import 'dart:convert';

import '../../core/models.dart';
import '../transaction_inputs.dart';

class CbrOpenFinanceFixtureParser {
  const CbrOpenFinanceFixtureParser();

  CbrOpenFinanceInput parse({
    required String entityId,
    required DateTime receivedAt,
    required String source,
  }) {
    final root = Map<String, dynamic>.from(jsonDecode(source) as Map);
    final institutionJson = _map(root['institution']);
    final institution = Institution(
      id: institutionJson['id'] as String,
      name: institutionJson['name'] as String,
      countryCode: institutionJson['countryCode'] as String,
    );
    final connectionId = 'con-cbr-${institution.id}';
    final consentJson = _map(root['consent']);
    final consent = SynoballConsent(
      id: 'cns-${consentJson['externalConsentId']}',
      entityId: entityId,
      connectionId: connectionId,
      status: ConsentStatus.values.byName(
        (consentJson['status'] as String).toLowerCase(),
      ),
      scopes: (consentJson['scopes'] as List).cast<String>(),
      purpose: 'Personal financial management',
      grantedAt: receivedAt,
      jurisdiction: institution.countryCode,
      externalConsentId: consentJson['externalConsentId'] as String,
    );
    final accountByExternalId = <String, SynoballAccount>{};
    for (final item in (root['accounts'] as List).cast<Map>()) {
      final json = Map<String, dynamic>.from(item);
      final externalId = json['externalId'] as String;
      final currency = json['currency'] as String;
      accountByExternalId[externalId] = SynoballAccount(
        id: 'acc-cbr-$externalId',
        entityId: entityId,
        name:
            '${institution.name} • ${externalId.substring(externalId.length - 4)}',
        type: SynoballAccountType.values.byName(
          (json['type'] as String).toLowerCase(),
        ),
        currency: currency,
        balance: Money.fromJson({
          'value': json['balance'] as String,
          'currency': currency,
        }),
        connectionId: connectionId,
        institutionId: institution.id,
        externalId: externalId,
      );
    }
    final transactions = (root['transactions'] as List)
        .cast<Map>()
        .map((item) {
          final json = Map<String, dynamic>.from(item);
          final externalAccountId = json['accountExternalId'] as String;
          final account = accountByExternalId[externalAccountId];
          if (account == null) {
            throw FormatException(
              'Unknown fixture account: $externalAccountId',
            );
          }
          final currency = json['currency'] as String;
          return TransactionSeed(
            accountId: account.id,
            amount: Money.fromJson({
              'value': json['amount'] as String,
              'currency': currency,
            }),
            direction: FinancialDirection.values.byName(
              (json['direction'] as String).toLowerCase(),
            ),
            occurredAt: DateTime.parse(json['occurredAt'] as String),
            description: json['description'] as String,
            merchant: json['description'] as String,
            providerCategory: json['category'] as String?,
            providerTransactionId: json['externalId'] as String,
            confidence: 1,
          );
        })
        .toList(growable: false);
    return CbrOpenFinanceInput(
      entityId: entityId,
      receivedAt: receivedAt,
      rawPayload: source,
      connection: SynoballConnection(
        id: connectionId,
        entityId: entityId,
        status: ConnectionStatus.active,
        method: 'CBR_OPEN_FINANCE',
        institutionId: institution.id,
        capabilities: const [
          SynoballCapability.accounts,
          SynoballCapability.balances,
          SynoballCapability.transactions,
        ],
        consentId: consent.id,
        adapterId: 'ru-cbr-open-finance',
        adapterVersion: 'mock-1.0.0',
        lastSyncedAt: receivedAt,
      ),
      institution: institution,
      consent: consent,
      accounts: accountByExternalId.values.toList(growable: false),
      transactions: transactions,
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);
