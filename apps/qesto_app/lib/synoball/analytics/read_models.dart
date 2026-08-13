import '../core/models.dart';

class DailySpendingSummary {
  const DailySpendingSummary({required this.date, required this.amount});
  final DateTime date;
  final Money amount;
}

class MonthlyCategorySummary {
  const MonthlyCategorySummary({
    required this.month,
    required this.categoryId,
    required this.amount,
  });
  final DateTime month;
  final String categoryId;
  final Money amount;
}

class MerchantSpendingSummary {
  const MerchantSpendingSummary({
    required this.merchant,
    required this.amount,
    required this.transactionCount,
  });
  final String merchant;
  final Money amount;
  final int transactionCount;
}

class CashflowSummary {
  const CashflowSummary({
    required this.income,
    required this.expenses,
    required this.net,
  });
  final Money income;
  final Money expenses;
  final Money net;
}

class SynoballAnalyticsReadService {
  const SynoballAnalyticsReadService();

  List<DailySpendingSummary> dailySpending({
    required SynoballState state,
    required String entityId,
    required DateTime from,
    required DateTime to,
    String currency = 'RUB',
  }) {
    final totals = <DateTime, int>{};
    for (final transaction in _posted(state, entityId, currency)) {
      if (transaction.direction != FinancialDirection.outflow ||
          transaction.occurredAt.isBefore(from) ||
          !transaction.occurredAt.isBefore(to)) {
        continue;
      }
      final day = DateTime(
        transaction.occurredAt.year,
        transaction.occurredAt.month,
        transaction.occurredAt.day,
      );
      totals.update(
        day,
        (value) => value + transaction.amount.minorUnits,
        ifAbsent: () => transaction.amount.minorUnits,
      );
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map(
          (entry) => DailySpendingSummary(
            date: entry.key,
            amount: Money(minorUnits: entry.value, currency: currency),
          ),
        )
        .toList();
  }

  List<MonthlyCategorySummary> monthlyCategories({
    required SynoballState state,
    required String entityId,
    String currency = 'RUB',
  }) {
    final totals = <String, int>{};
    for (final transaction in _posted(state, entityId, currency)) {
      if (transaction.direction != FinancialDirection.outflow) continue;
      final category = transaction.effectiveCategory ?? 'other';
      final key =
          '${transaction.occurredAt.year}-'
          '${transaction.occurredAt.month.toString().padLeft(2, '0')}|$category';
      totals.update(
        key,
        (value) => value + transaction.amount.minorUnits,
        ifAbsent: () => transaction.amount.minorUnits,
      );
    }
    return totals.entries.map((entry) {
      final parts = entry.key.split('|');
      final month = parts.first.split('-').map(int.parse).toList();
      return MonthlyCategorySummary(
        month: DateTime(month[0], month[1]),
        categoryId: parts[1],
        amount: Money(minorUnits: entry.value, currency: currency),
      );
    }).toList();
  }

  List<MerchantSpendingSummary> merchantSpending({
    required SynoballState state,
    required String entityId,
    String currency = 'RUB',
  }) {
    final amounts = <String, int>{};
    final counts = <String, int>{};
    for (final transaction in _posted(state, entityId, currency)) {
      if (transaction.direction != FinancialDirection.outflow) continue;
      final merchant = transaction.merchantName ?? 'Неизвестный продавец';
      amounts.update(
        merchant,
        (value) => value + transaction.amount.minorUnits,
        ifAbsent: () => transaction.amount.minorUnits,
      );
      counts.update(merchant, (value) => value + 1, ifAbsent: () => 1);
    }
    final result = amounts.entries
        .map(
          (entry) => MerchantSpendingSummary(
            merchant: entry.key,
            amount: Money(minorUnits: entry.value, currency: currency),
            transactionCount: counts[entry.key]!,
          ),
        )
        .toList();
    result.sort((a, b) => b.amount.minorUnits.compareTo(a.amount.minorUnits));
    return result;
  }

  CashflowSummary cashflow({
    required SynoballState state,
    required String entityId,
    required DateTime from,
    required DateTime to,
    String currency = 'RUB',
  }) {
    var income = 0;
    var expenses = 0;
    for (final transaction in _posted(state, entityId, currency)) {
      if (transaction.occurredAt.isBefore(from) ||
          !transaction.occurredAt.isBefore(to)) {
        continue;
      }
      if (transaction.direction == FinancialDirection.inflow) {
        income += transaction.amount.minorUnits;
      } else if (transaction.direction == FinancialDirection.outflow) {
        expenses += transaction.amount.minorUnits;
      }
    }
    return CashflowSummary(
      income: Money(minorUnits: income, currency: currency),
      expenses: Money(minorUnits: expenses, currency: currency),
      net: Money(minorUnits: income - expenses, currency: currency),
    );
  }

  Iterable<CanonicalTransaction> _posted(
    SynoballState state,
    String entityId,
    String currency,
  ) => state.transactions.where(
    (item) =>
        item.entityId == entityId &&
        item.status == CanonicalTransactionStatus.posted &&
        item.amount.currency == currency,
  );
}
