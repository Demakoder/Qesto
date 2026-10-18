// Run using the unchanged app package configuration. Synthetic data only.
import 'dart:convert';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';

void main() {
  final now = DateTime.utc(2026, 10, 9);
  final transactions = <CanonicalTransaction>[
    for (var i = 0; i < 3; i++)
      CanonicalTransaction(
        id: 'spike-v7-$i',
        entityId: 'synthetic-owner',
        accountId: 'synthetic-account',
        status: i == 2
            ? CanonicalTransactionStatus.deleted
            : CanonicalTransactionStatus.posted,
        amount: Money(
          minorUnits: [486122, 1500025, 13][i],
          currency: i == 1 ? 'USD' : 'RUB',
        ),
        direction: i == 1
            ? FinancialDirection.inflow
            : FinancialDirection.outflow,
        occurredAt: now,
        rawDescription: 'synthetic codec v7',
        normalizedDescription: 'synthetic codec v7',
        userCategoryOverride: 'sport',
        userNote: 'synthetic user-owned note',
        tags: ['user-field:category', 'user-field:note'],
        eventType: FinancialEventType.observed,
        createdAt: now,
        updatedAt: now,
        fieldTrust: SourceTrustLevel.userConfirmed,
      ),
  ];
  const codec = UserFinancialDataCodec();
  final encoded = codec.encode(
    UserFinancialData(
      user: const QestoUser(
        id: 'synthetic-owner',
        name: 'Storage spike synthetic',
        defaultCurrency: 'RUB',
      ),
      referenceDate: now,
      synoballState: SynoballState(transactions: transactions),
    ),
  );
  final restored = codec.decode(encoded);
  if (restored.synoballState!.transactions[0].amount.minorUnits != 486122 ||
      jsonEncode(restored.synoballState!.toJson()) !=
          jsonEncode(SynoballState(transactions: transactions).toJson())) {
    throw StateError('Existing codec compatibility failed');
  }
  print(encoded);
}
