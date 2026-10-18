import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/synoball/core/models.dart' as old_models;
import 'package:qesto/synoball/adapters/source_identity.dart' as old_identity;
import 'package:qesto/synoball/synoball.dart' as legacy;
import 'package:qesto_synoball_core/qesto_synoball_core.dart' as shared;

void main() {
  final fixed = DateTime.utc(2026, 9, 8, 12);

  test(
    'old imports and shared imports expose identical types and ID sequence',
    () {
      expect(identical(legacy.Money, shared.Money), isTrue);
      expect(
        identical(old_models.CanonicalTransaction, shared.CanonicalTransaction),
        isTrue,
      );
      expect(identical(legacy.SynoballCore, shared.SynoballCore), isTrue);
      expect(identical(legacy.SynoballState, shared.SynoballState), isTrue);
      expect(
        identical(legacy.StatementAdapter, shared.StatementAdapter),
        isTrue,
      );
      expect(
        identical(
          legacy.TransactionDeduplicator,
          shared.TransactionDeduplicator,
        ),
        isTrue,
      );
      expect(
        old_identity.sourceIdentity('compat', [486122, 'RUB']),
        shared.sourceIdentity('compat', [486122, 'RUB']),
      );
      final a = legacy.SynoballIdFactory(clock: () => fixed);
      final b = shared.SynoballIdFactory(clock: () => fixed);
      final first = a.next('compat').split('-');
      final second = b.next('compat').split('-');
      expect(first[1], '${fixed.microsecondsSinceEpoch}');
      expect(int.parse(second[2]), int.parse(first[2]) + 1);
      expect(first[3], '1');
      expect(second[3], '1');
    },
  );

  test(
    'legacy adapter -> shared core -> existing codec keeps canonical state',
    () {
      final ids = shared.SynoballIdFactory(clock: () => fixed);
      final core = shared.SynoballCore(ids: ids, clock: () => fixed);
      final result = core.ingest(
        legacy.StatementAdapter(ids: ids),
        legacy.StatementInput(
          entityId: 'synthetic-user',
          receivedAt: fixed,
          rawPayload: '{"synthetic":true}',
          batchName: 'Compatibility',
          account: const legacy.SynoballAccount(
            id: 'account-existing',
            entityId: 'synthetic-user',
            name: 'Synthetic savings',
            type: legacy.SynoballAccountType.savings,
            currency: 'RUB',
            balance: legacy.Money(minorUnits: 1500025, currency: 'RUB'),
          ),
          transactions: [
            legacy.TransactionSeed(
              canonicalId: 'transaction-existing',
              accountId: 'account-existing',
              amount: const legacy.Money(minorUnits: 486122, currency: 'RUB'),
              direction: legacy.FinancialDirection.outflow,
              occurredAt: fixed,
              description: 'Synthetic expense',
              providerTransactionId: 'provider-existing',
              confidence: 1,
            ),
          ],
        ),
      );
      final transaction = core.transactions.single;
      core.updateTransaction(
        transaction.copyWith(
          userCategoryOverride: 'sport',
          userNote: 'Synthetic note',
          tags: ['user-field:category', 'user-field:note'],
        ),
        actorId: 'synthetic-user',
      );
      core.deleteTransaction(transaction.id, actorId: 'synthetic-user');
      final data = UserFinancialData(
        user: const QestoUser(
          id: 'synthetic-user',
          name: 'Synthetic',
          defaultCurrency: 'RUB',
        ),
        referenceDate: fixed,
        synoballState: core.state,
      );
      const codec = UserFinancialDataCodec();
      final encoded = codec.encode(data);
      expect(jsonDecode(encoded)['schemaVersion'], 7);
      final decoded = codec.decode(encoded);
      final decodedState = decoded.synoballState!;
      expect(decodedState.toJson(), data.synoballState!.toJson());
      expect(decodedState.transactions.single.amount.minorUnits, 486122);
      expect(decodedState.accounts.single.balance.minorUnits, 1500025);
      expect(
        decodedState.transactions.single.status,
        shared.CanonicalTransactionStatus.deleted,
      );
      expect(decodedState.transactions.single.userCategoryOverride, 'sport');

      // The inverse import direction also shares the same types and semantics.
      final restored = legacy.SynoballCore(
        initialState: decodedState,
        ids: ids,
        clock: () => fixed,
      );
      expect(
        restored.restoreDeletedTransaction(
          transaction.id,
          actorId: 'synthetic-user',
        ),
        isTrue,
      );
      expect(
        restored.transactions.single.id,
        result.createdTransactionIds.single,
      );
      expect(restored.transactions.single.userNote, 'Synthetic note');
      expect(restored.transactions.single.amount.toJson(), {
        'value': '4861.22',
        'currency': 'RUB',
      });
      expect(
        codec.decode(codec.encode(decoded)).synoballState!.toJson(),
        decodedState.toJson(),
      );
    },
  );

  test(
    'app bridge/read model keep all existing transaction types and money',
    () {
      final originals = <BudgetTransaction>[
        for (final currency in ['RUB', 'USD', 'EUR', 'CNY'])
          for (final type in TransactionType.values)
            BudgetTransaction(
              id: 'existing-$currency-${type.name}',
              userId: 'synthetic-user',
              accountId: 'existing-$currency',
              date: fixed,
              amount: 4861,
              exactAmountMinor: 486122,
              currency: currency,
              type: type,
              merchant: 'Synthetic ${type.name}',
              transferDirection: type == TransactionType.transfer
                  ? TransferDirection.outgoing
                  : null,
            ),
      ];
      final source = UserFinancialData(
        user: const QestoUser(
          id: 'synthetic-user',
          name: 'Synthetic',
          defaultCurrency: 'RUB',
        ),
        referenceDate: fixed,
        accounts: [
          for (final currency in ['RUB', 'USD', 'EUR', 'CNY'])
            QestoAccount(
              id: 'existing-$currency',
              userId: 'synthetic-user',
              title: 'Synthetic',
              balance: 15000,
              exactBalanceMinor: 1500025,
              currency: currency,
              type: AccountType.savings,
            ),
        ],
        transactions: originals,
      );
      final ids = shared.SynoballIdFactory(clock: () => fixed);
      final core = shared.SynoballCore(ids: ids, clock: () => fixed);
      core.ingest(
        legacy.LegacyQestoAdapter(ids: ids),
        const legacy.QestoLegacyBridge().buildInput(source),
      );
      final projected = const legacy.QestoReadModelService().build(core.state);
      expect(projected.transactions, hasLength(originals.length));
      for (final original in originals) {
        final result = projected.transactions.singleWhere(
          (t) => t.id == original.id,
        );
        expect(result.amountMinor, original.amountMinor);
        expect(result.currency, original.currency);
        expect(result.type, original.type);
        expect(result.transferDirection, original.transferDirection);
      }
      for (final account in projected.accounts) {
        expect(account.balanceMinor, 1500025);
        expect(account.type, AccountType.savings);
      }
      const cashFlow = CashFlowCalculationService();
      for (final currency in ['RUB', 'USD', 'EUR', 'CNY']) {
        final before = cashFlow.calculate(
          transactions: originals,
          from: fixed,
          toExclusive: fixed.add(const Duration(days: 1)),
          currency: currency,
        );
        final after = cashFlow.calculate(
          transactions: projected.transactions,
          from: fixed,
          toExclusive: fixed.add(const Duration(days: 1)),
          currency: currency,
        );
        expect(after.externalInflowsMinor, before.externalInflowsMinor);
        expect(after.externalOutflowsMinor, before.externalOutflowsMinor);
        expect(after.netCashFlowMinor, before.netCashFlowMinor);
        expect(
          after.internalTransfersExcluded,
          before.internalTransfersExcluded,
        );
      }
    },
  );
}
