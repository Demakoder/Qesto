import '../core/models.dart';

class SynoballDataQuality {
  const SynoballDataQuality({
    required this.overall,
    required this.freshness,
    required this.completeness,
    required this.sourceReliability,
    required this.warnings,
  });

  final double overall;
  final double freshness;
  final double completeness;
  final double sourceReliability;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
    'overall': overall,
    'freshness': freshness,
    'completeness': completeness,
    'sourceReliability': sourceReliability,
    'warnings': warnings,
  };
}

class ExpectedFinancialEvent {
  const ExpectedFinancialEvent({
    required this.id,
    required this.title,
    required this.amount,
    required this.expectedAt,
    required this.confidence,
    required this.eventType,
    this.recurringStreamId,
  });

  final String id;
  final String title;
  final Money amount;
  final DateTime expectedAt;
  final double confidence;
  final FinancialEventType eventType;
  final String? recurringStreamId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount.toJson(),
    'expectedAt': expectedAt.toIso8601String(),
    'confidence': confidence,
    'eventType': eventType.name,
    'recurringStreamId': recurringStreamId,
  };
}

class FinancialState {
  const FinancialState({
    required this.entityId,
    required this.asOf,
    required this.balances,
    required this.liquidMoney,
    required this.monthlyIncome,
    required this.incomeStability,
    required this.monthlyExpenses,
    required this.mandatoryExpenses,
    required this.freeCashflow,
    required this.recurringObligations,
    required this.plannedExpenses,
    required this.assets,
    required this.debts,
    required this.investments,
    required this.upcomingEvents,
    required this.dataQuality,
  });

  final String entityId;
  final DateTime asOf;
  final Map<String, Money> balances;
  final Money liquidMoney;
  final Money monthlyIncome;
  final double incomeStability;
  final Money monthlyExpenses;
  final Money mandatoryExpenses;
  final Money freeCashflow;
  final List<RecurringStream> recurringObligations;
  final Money plannedExpenses;
  final Money assets;
  final Money debts;
  final Money investments;
  final List<ExpectedFinancialEvent> upcomingEvents;
  final SynoballDataQuality dataQuality;

  Map<String, dynamic> toJson() => {
    'entityId': entityId,
    'asOf': asOf.toIso8601String(),
    'balances': balances.map((key, value) => MapEntry(key, value.toJson())),
    'liquidMoney': liquidMoney.toJson(),
    'monthlyIncome': monthlyIncome.toJson(),
    'incomeStability': incomeStability,
    'monthlyExpenses': monthlyExpenses.toJson(),
    'mandatoryExpenses': mandatoryExpenses.toJson(),
    'freeCashflow': freeCashflow.toJson(),
    'recurringObligations': recurringObligations
        .map((value) => value.toJson())
        .toList(),
    'plannedExpenses': plannedExpenses.toJson(),
    'assets': assets.toJson(),
    'debts': debts.toJson(),
    'investments': investments.toJson(),
    'upcomingEvents': upcomingEvents.map((value) => value.toJson()).toList(),
    'dataQuality': dataQuality.toJson(),
  };
}

class FinancialStateService {
  const FinancialStateService();

  FinancialState calculate({
    required SynoballState state,
    required String entityId,
    required DateTime asOf,
    String currency = 'RUB',
    int plannedExpensesMinor = 0,
  }) {
    final accounts = state.accounts
        .where((item) => item.entityId == entityId && item.currency == currency)
        .toList();
    final monthStart = DateTime(asOf.year, asOf.month);
    final monthEnd = DateTime(asOf.year, asOf.month + 1);
    final transactions = state.transactions.where(
      (item) =>
          item.entityId == entityId &&
          item.status == CanonicalTransactionStatus.posted &&
          item.amount.currency == currency,
    );
    final currentMonth = transactions.where(
      (item) =>
          !item.occurredAt.isBefore(monthStart) &&
          item.occurredAt.isBefore(monthEnd),
    );
    final income = currentMonth
        .where((item) => item.direction == FinancialDirection.inflow)
        .fold<int>(0, (total, item) => total + item.amount.minorUnits);
    final expenses = currentMonth
        .where((item) => item.direction == FinancialDirection.outflow)
        .fold<int>(0, (total, item) => total + item.amount.minorUnits);
    final streams = state.recurringStreams
        .where(
          (item) =>
              item.entityId == entityId &&
              item.typicalAmount.currency == currency,
        )
        .toList();
    final mandatory = streams.fold<int>(
      0,
      (total, item) => total + item.typicalAmount.minorUnits,
    );
    final liquidTypes = {
      SynoballAccountType.checking,
      SynoballAccountType.card,
      SynoballAccountType.savings,
      SynoballAccountType.cash,
      SynoballAccountType.wallet,
    };
    final assetTypes = {
      ...liquidTypes,
      SynoballAccountType.deposit,
      SynoballAccountType.brokerage,
      SynoballAccountType.investment,
    };
    final liquid = accounts
        .where((item) => liquidTypes.contains(item.type))
        .fold<int>(0, (total, item) => total + item.balance.minorUnits);
    final assets = accounts
        .where((item) => assetTypes.contains(item.type))
        .fold<int>(0, (total, item) => total + item.balance.minorUnits);
    final debts = accounts
        .where(
          (item) =>
              item.type == SynoballAccountType.credit ||
              item.type == SynoballAccountType.loan,
        )
        .fold<int>(0, (total, item) => total + item.balance.minorUnits.abs());
    final investments = accounts
        .where(
          (item) =>
              item.type == SynoballAccountType.brokerage ||
              item.type == SynoballAccountType.investment,
        )
        .fold<int>(0, (total, item) => total + item.balance.minorUnits);
    final upcoming = streams
        .where((item) => item.nextExpectedAt.isAfter(asOf))
        .map(
          (item) => ExpectedFinancialEvent(
            id: 'expected-${item.id}',
            title: item.title,
            amount: item.typicalAmount,
            expectedAt: item.nextExpectedAt,
            confidence: item.confidence,
            eventType: FinancialEventType.expected,
            recurringStreamId: item.id,
          ),
        )
        .toList();
    final quality = _quality(state, entityId, asOf);
    return FinancialState(
      entityId: entityId,
      asOf: asOf,
      balances: {for (final account in accounts) account.id: account.balance},
      liquidMoney: Money(minorUnits: liquid, currency: currency),
      monthlyIncome: Money(minorUnits: income, currency: currency),
      incomeStability: _incomeStability(transactions, asOf),
      monthlyExpenses: Money(minorUnits: expenses, currency: currency),
      mandatoryExpenses: Money(minorUnits: mandatory, currency: currency),
      freeCashflow: Money(
        minorUnits: income - expenses - plannedExpensesMinor,
        currency: currency,
      ),
      recurringObligations: streams,
      plannedExpenses: Money(
        minorUnits: plannedExpensesMinor,
        currency: currency,
      ),
      assets: Money(minorUnits: assets, currency: currency),
      debts: Money(minorUnits: debts, currency: currency),
      investments: Money(minorUnits: investments, currency: currency),
      upcomingEvents: upcoming,
      dataQuality: quality,
    );
  }

  SynoballDataQuality _quality(
    SynoballState state,
    String entityId,
    DateTime asOf,
  ) {
    final records = state.ingestionRecords
        .where((item) => item.entityId == entityId)
        .toList();
    final connections = state.connections
        .where((item) => item.entityId == entityId)
        .toList();
    final warnings = <String>[];
    if (records.isEmpty) warnings.add('Нет импортированных финансовых данных');
    if (connections.isEmpty) {
      warnings.add('Нет постоянных подключений; картина может быть неполной');
    }
    final latest = records.isEmpty
        ? null
        : records.reduce(
            (left, right) =>
                left.receivedAt.isAfter(right.receivedAt) ? left : right,
          );
    final ageDays = latest == null
        ? 365
        : asOf.difference(latest.receivedAt).inDays.abs();
    final freshness = (1 - ageDays / 30).clamp(0, 1).toDouble();
    final successful = records
        .where((item) => item.status == IngestionStatus.completed)
        .length;
    final reliability = records.isEmpty ? 0.4 : successful / records.length;
    final sourceTypes = records.map((item) => item.sourceType).toSet();
    final completeness = (0.35 + sourceTypes.length * 0.1)
        .clamp(0, 0.9)
        .toDouble();
    final overall = (freshness * 0.3 + reliability * 0.35 + completeness * 0.35)
        .clamp(0, 0.95)
        .toDouble();
    return SynoballDataQuality(
      overall: overall,
      freshness: freshness,
      completeness: completeness,
      sourceReliability: reliability.toDouble(),
      warnings: warnings,
    );
  }

  double _incomeStability(
    Iterable<CanonicalTransaction> transactions,
    DateTime asOf,
  ) {
    final totals = <int>[];
    for (var offset = 0; offset < 3; offset++) {
      final start = DateTime(asOf.year, asOf.month - offset);
      final end = DateTime(asOf.year, asOf.month - offset + 1);
      totals.add(
        transactions
            .where(
              (item) =>
                  item.direction == FinancialDirection.inflow &&
                  !item.occurredAt.isBefore(start) &&
                  item.occurredAt.isBefore(end),
            )
            .fold(0, (total, item) => total + item.amount.minorUnits),
      );
    }
    final nonZero = totals.where((value) => value > 0).toList();
    if (nonZero.length < 2) return 0;
    final average = nonZero.reduce((a, b) => a + b) / nonZero.length;
    final deviation =
        nonZero
            .map((value) => (value - average).abs())
            .reduce((a, b) => a + b) /
        nonZero.length;
    return (1 - deviation / average).clamp(0, 1).toDouble();
  }
}
