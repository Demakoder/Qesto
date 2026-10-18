// Run with the existing app package config. No repository or profile is opened.
import 'dart:convert';
import 'dart:io';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import '../../../apps/qesto_app/test/fixtures/mobile_stage5_data.dart';

void main(List<String> args) {
  const codec = UserFinancialDataCodec();
  final now = DateTime.utc(2026, 10, 11);
  final state = SynoballState(
    transactions: [
      for (var i = 0; i < 3; i++)
        CanonicalTransaction(
          id: 'container-tx-$i',
          entityId: 'demo-user',
          accountId: 'cap-0',
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
          rawDescription: 'synthetic',
          normalizedDescription: 'synthetic',
          userCategoryOverride: 'sport',
          userNote: 'user-owned note',
          tags: ['user-field:category', 'user-field:note'],
          eventType: FinancialEventType.observed,
          createdAt: now,
          updatedAt: now,
          fieldTrust: SourceTrustLevel.userConfirmed,
        ),
    ],
  );
  if (args.isEmpty) {
    final initial = stage5Data().copyWith(synoballState: state);
    final encoded = codec.encode(initial);
    if (codec.encode(codec.decode(encoded)) != encoded)
      throw StateError('codec roundtrip');
    print(encoded);
  } else {
    // Explicit synthetic output path only, not a user-profile loader.
    if (!args.single.contains('qesto-storage-spike-'))
      throw StateError('synthetic-only');
    final bytes = File(args.single).readAsStringSync();
    final restored = codec.decode(bytes);
    if (codec.encode(restored) != bytes ||
        restored.synoballState!.transactions[0].amount.minorUnits != 486122 ||
        restored.synoballState!.transactions[1].amount.currency != 'USD' ||
        restored.synoballState!.transactions[2].status !=
            CanonicalTransactionStatus.deleted ||
        restored.accounts.isEmpty ||
        restored.debts.isEmpty ||
        restored.investmentAccounts.isEmpty ||
        restored.savingsGoals.isEmpty ||
        restored.budgetPeriods.isEmpty)
      throw StateError('lossless roundtrip failed');
    print(
      jsonEncode({
        'passed': true,
        'codecVersion': 7,
        'accounts': restored.accounts.length,
        'transactions': restored.transactions.length,
        'canonicalTransactions': restored.synoballState!.transactions.length,
        'debts': restored.debts.length,
        'investments': restored.investmentAccounts.length,
        'goals': restored.savingsGoals.length,
      }),
    );
  }
}
