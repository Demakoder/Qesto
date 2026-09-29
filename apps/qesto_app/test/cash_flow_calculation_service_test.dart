import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';

void main() {
  const service = CashFlowCalculationService();
  final from = DateTime(2026, 8);
  final to = DateTime(2026, 9);

  BudgetTransaction transaction({
    required String id,
    required int amount,
    required TransactionType type,
    TransferDirection? direction,
    List<String> tags = const [],
    String? categoryId = 'other',
  }) => BudgetTransaction(
    id: id,
    userId: 'user',
    accountId: 'account',
    date: DateTime(2026, 8, 15),
    amount: amount,
    currency: 'RUB',
    type: type,
    categoryId: categoryId,
    transferDirection: direction,
    tags: tags,
  );

  QestoCashFlowSummary calculate(Iterable<BudgetTransaction> transactions) =>
      service.calculate(
        transactions: transactions,
        from: from,
        toExclusive: to,
        currency: 'RUB',
      );

  test('net cash flow is inflows minus outflows', () {
    final result = calculate([
      transaction(id: 'income', amount: 60000, type: TransactionType.income),
      transaction(
        id: 'expense',
        amount: 58000,
        type: TransactionType.expense,
        categoryId: null,
      ),
    ]);

    expect(result.externalInflows, 60000);
    expect(result.externalOutflows, 58000);
    expect(result.netCashFlow, 2000);
  });

  test('internal transfer pair has zero user-level impact', () {
    final result = calculate([
      transaction(
        id: 'internal-out',
        amount: 20000,
        type: TransactionType.transfer,
        direction: TransferDirection.outgoing,
        tags: const [qestoInternalTransferTag],
      ),
      transaction(
        id: 'internal-in',
        amount: 20000,
        type: TransactionType.transfer,
        direction: TransferDirection.incoming,
        tags: const [qestoInternalTransferTag],
      ),
    ]);

    expect(result.netCashFlow, 0);
    expect(result.internalTransferInflows, 20000);
    expect(result.internalTransferOutflows, 20000);
  });

  test('personal incoming and outgoing transfers affect cash flow', () {
    final result = calculate([
      transaction(
        id: 'incoming-person',
        amount: 10000,
        type: TransactionType.income,
        direction: TransferDirection.incoming,
        tags: const [qestoExternalTransferTag],
      ),
      transaction(
        id: 'outgoing-person',
        amount: 4000,
        type: TransactionType.expense,
        direction: TransferDirection.outgoing,
        tags: const [qestoExternalTransferTag],
      ),
    ]);

    expect(result.externalInflows, 10000);
    expect(result.externalOutflows, 4000);
    expect(result.netCashFlow, 6000);
  });

  test('an external outgoing transfer remains an outflow before migration', () {
    final result = calculate([
      transaction(
        id: 'legacy-outgoing-person',
        amount: 4000,
        type: TransactionType.transfer,
        direction: TransferDirection.outgoing,
      ),
    ]);

    expect(result.externalOutflows, 4000);
    expect(result.netCashFlow, -4000);
  });

  test('loyalty metadata never changes the monetary amount', () {
    final result = calculate([
      transaction(
        id: 'purchase-with-reward',
        amount: 500,
        type: TransactionType.expense,
        tags: const [qestoLoyaltyMetadataTag],
      ),
    ]);

    expect(result.externalOutflows, 500);
    expect(result.externalInflows, 0);
    expect(result.netCashFlow, -500);
  });
}
