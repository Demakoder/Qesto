import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/repositories/local_qesto_repository.dart';
import 'package:qesto/desktop/pages/desktop_accounts_page.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/capital/domain/account_capital_service.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/analytics/qesto_read_model.dart';
import 'package:qesto/synoball/core/models.dart';

// Anonymized shape of the failing persisted profile: the unassigned ID EXISTS
// in both account collections as virtual/other, alongside real liquid accounts.
final _today = DateTime(2026, 9, 27);
const _bucket = 'unassigned-bank-RUB';
const _entity = 'ent-fixture-user';

CanonicalTransaction _operation(
  String id,
  int day,
  int amount, {
  String account = _bucket,
  bool income = false,
  bool internal = false,
  String? excludedStatus,
}) => CanonicalTransaction(
  id: id,
  entityId: _entity,
  accountId: account,
  status: excludedStatus == 'pending'
      ? CanonicalTransactionStatus.pending
      : CanonicalTransactionStatus.posted,
  amount: Money(minorUnits: amount * 100, currency: 'RUB'),
  direction: income ? FinancialDirection.inflow : FinancialDirection.outflow,
  occurredAt: DateTime(2026, 9, day),
  rawDescription: id,
  normalizedDescription: id,
  eventType: FinancialEventType.observed,
  createdAt: _today,
  updatedAt: _today,
  fieldTrust: SourceTrustLevel.bankStatement,
  transferDirection: internal ? (income ? 'incoming' : 'outgoing') : null,
  tags: [
    if (account == _bucket) 'sber-account-unresolved',
    'legacy-type-${internal
        ? 'transfer'
        : income
        ? 'income'
        : 'expense'}',
    if (internal) qestoInternalTransferTag,
    if (excludedStatus != null) 'sber-status-$excludedStatus',
  ],
);

Future<BudgetController> _load(List<CanonicalTransaction> rows) async {
  final state = SynoballState(
    accounts: const [
      SynoballAccount(
        id: 'card',
        entityId: _entity,
        name: 'Liquid account',
        type: SynoballAccountType.checking,
        currency: 'RUB',
        balance: Money(minorUnits: 240000, currency: 'RUB'),
      ),
      SynoballAccount(
        id: _bucket,
        entityId: _entity,
        name: 'Unassigned bank observations',
        type: SynoballAccountType.other,
        currency: 'RUB',
        balance: Money(minorUnits: 0, currency: 'RUB'),
        isVirtual: true,
      ),
      SynoballAccount(
        id: 'broker',
        entityId: _entity,
        name: 'Investment',
        type: SynoballAccountType.brokerage,
        currency: 'RUB',
        balance: Money(minorUnits: 1000000, currency: 'RUB'),
        isVirtual: true,
      ),
    ],
    transactions: rows,
  );
  final model = const QestoReadModelService().build(state);
  final persisted = UserFinancialData(
    user: const QestoUser(
      id: 'fixture-user',
      name: 'Fixture',
      defaultCurrency: 'RUB',
    ),
    referenceDate: _today,
    accounts: model.accounts,
    transactions: model.transactions,
    synoballState: state,
  );
  final source = const UserFinancialDataCodec().encode(persisted);
  final store = MemoryKeyValueStore({'qesto.user-financial-data.v1': source});
  final loaded = await LocalQestoRepository(
    store: store,
    publicStore: store,
  ).getUserFinancialData();
  expect(await store.readString('qesto.user-financial-data.v1'), source);
  // Pin only the clock; persistence/read-model selection follows production.
  return BudgetController(
    configuration: budgetConfiguration,
    financialData: loaded.copyWith(referenceDate: _today),
  );
}

AccountCapitalSnapshot _snapshot(
  BudgetController c, [
  CapitalPeriod period = CapitalPeriod.oneMonth,
]) => const AccountCapitalService().calculate(
  accounts: c.accounts,
  accountPreferences: c.accountPreferences,
  transactions: c.transactions,
  upcomingExpenses: c.upcomingExpenses,
  savingsGoals: c.savingsGoals,
  synoballState: c.synoballState,
  asOf: c.referenceDate,
  period: period,
  baseCurrency: 'RUB',
);

Map<int, int> _balances(Iterable<AccountBalancePoint> points) => {
  for (final p in points) p.date.day: p.balance,
};

void main() {
  test(
    'persisted virtual routing account retains later monetary history',
    () async {
      final c = await _load([
        _operation('earlier', 6, 1000, account: 'card'),
        _operation('later-income', 8, 3800, income: true),
        _operation('later-expense', 12, 330),
        _operation('unpaired-own-debit', 26, 15000, internal: true),
        _operation('pending', 20, 90000, excludedStatus: 'pending'),
        _operation('cancelled', 21, 80000, excludedStatus: 'cancelled'),
        _operation('broker-fee', 22, 500, account: 'broker'),
      ]);
      addTearDown(c.dispose);
      expect(
        c.accounts.singleWhere((a) => a.id == _bucket).type,
        AccountType.other,
      );
      expect(c.transactions, hasLength(7));
      for (final period in CapitalPeriod.values) {
        final result = _snapshot(c, period);
        final days = _balances(result.history);
        expect(result.totalLiquidAssets, 2400);
        expect(days[5], 14930, reason: period.name);
        expect(days[6], 13930);
        expect(days[7], 13930);
        expect(days[8], 17730);
        expect(days[12], 17400);
        expect(days[20], 17400);
        expect(days[21], 17400);
        expect(days[22], 17400);
        expect(days[25], 17400);
        expect(days[26], 2400);
        expect(days[27], 2400);
        expect(result.history.last.balance, result.totalLiquidAssets);
      }
      // Cash Flow keeps its own semantics: internal movement is not spending.
      final flow = c.cashFlowForRange(
        from: DateTime(2026, 9),
        toExclusive: DateTime(2026, 10),
      );
      expect(flow.externalInflows, 3800);
      expect(flow.externalOutflows, 1830);
      expect(flow.internalTransfersExcluded, 15000);
    },
  );

  testWidgets('new persisted-path operation updates existing liquidity chart', (
    tester,
  ) async {
    final c = await _load([_operation('earlier', 6, 1000, account: 'card')]);
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(body: DesktopAccountsPage(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    List<AccountBalancePoint> chartPoints() {
      final dynamic painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere(
            (w) => w.painter.runtimeType.toString() == '_BalancePainter',
          )
          .painter;
      return painter.points as List<AccountBalancePoint>;
    }

    final before = chartPoints();
    expect(_balances(before)[12], 2400);
    await c.addImportedTransactions([
      BudgetTransaction(
        id: 'new-import',
        userId: 'fixture-user',
        accountId: _bucket,
        date: DateTime(2026, 9, 12),
        amount: 1500,
        currency: 'RUB',
        type: TransactionType.expense,
        title: 'Imported purchase',
        tags: const ['sber-account-unresolved'],
      ),
    ]);
    await tester.pumpAndSettle();
    final after = chartPoints();
    expect(after, isNot(same(before)));
    expect(_balances(after)[11], 3900);
    expect(_balances(after)[12], 2400);
    expect(after.last.balance, 2400);
    expect(tester.takeException(), isNull);
  });
}
