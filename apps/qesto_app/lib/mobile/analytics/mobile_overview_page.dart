import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../desktop/desktop_destination.dart';
import '../../desktop/overview/desktop_overview_data.dart';
import '../../desktop/overview/overview_drilldown_panel.dart';
import '../../desktop/overview/overview_expense_trend_chart.dart';
import '../../features/budget/services/cash_flow_calculation_service.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/transaction_route_scope.dart';
import '../../features/statistics/domain/models/statistics_models.dart';
import '../../features/statistics/presentation/state/statistics_controller.dart';
import 'mobile_analysis_page.dart';
import 'mobile_financial_widgets.dart';
import 'mobile_upcoming_page.dart';

class MobileOverviewPage extends StatefulWidget {
  const MobileOverviewPage({
    required this.controller,
    required this.period,
    required this.onOpenDestination,
    required this.onOpenTransaction,
    required this.onOpenFilteredTransactions,
    super.key,
  });
  final BudgetController controller;
  final BudgetPeriod period;
  final ValueChanged<DesktopDestination> onOpenDestination;
  final ValueChanged<String> onOpenTransaction;
  final ValueChanged<List<String>> onOpenFilteredTransactions;
  @override
  State<MobileOverviewPage> createState() => _MobileOverviewPageState();
}

class _MobileOverviewPageState extends State<MobileOverviewPage> {
  late StatisticsController _statistics = StatisticsController(
    budgetController: widget.controller,
  );
  DesktopOverviewData? _data;
  bool _hidden = false;
  bool _error = false;
  bool _refreshing = false;
  var _granularity = OverviewTrendGranularity.days;
  OverviewTrendSelection? _selected;
  @override
  void initState() {
    super.initState();
    _read();
    widget.controller.addListener(_changed);
  }

  void _read() {
    try {
      final data = DesktopOverviewData.build(widget.controller, widget.period);
      _statistics.setCustomPeriod(
        widget.period.startDate,
        widget.controller.activeDateFor(widget.period),
      );
      _data = data;
      _error = false;
    } catch (_) {
      _error = true;
    }
  }

  void _changed() {
    if (mounted) setState(_read);
  }

  @override
  void didUpdateWidget(covariant MobileOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _statistics.dispose();
      _statistics = StatisticsController(budgetController: widget.controller);
      widget.controller.addListener(_changed);
    }
    if (oldWidget.period != widget.period ||
        oldWidget.controller != widget.controller) {
      _selected = null;
      _read();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _statistics.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      widget.controller.refreshLocalReadModel();
      setState(_read);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _analysis(StatisticsSection section) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(name: '/analytics/${section.name}'),
      builder: (_) => MobileAnalysisPage(
        controller: widget.controller,
        section: section,
        initialRange: StatisticsDateRange(
          widget.period.startDate,
          widget.controller.activeDateFor(widget.period),
        ),
        initiallyHidden: _hidden,
        onOpenFilteredTransactions: widget.onOpenFilteredTransactions,
      ),
    ),
  );
  void _ids(Iterable<BudgetTransaction> rows) =>
      widget.onOpenFilteredTransactions(rows.map((t) => t.id).toList());
  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: MobileReadError(onRetry: _refresh),
      );
    }
    final flow = widget.controller.cashFlowFor(widget.period);
    final issues = _statistics.snapshot.dataQuality.issues;
    final attention = issues
        .map((i) => i.transactionId)
        .whereType<String>()
        .toSet();
    final change = _statistics.snapshot.summary.changePercent;
    final upcoming = buildMobileUpcoming(widget.controller).upcoming;
    // The legacy bridge creates a zero-balance virtual fallback even for an
    // empty profile. Its existence is not evidence of a known capital balance.
    final hasCapitalData =
        widget.controller.synoballState.accounts.any(
          (account) => !account.isVirtual || account.balance.minorUnits != 0,
        ) ||
        widget.controller.investmentAccounts.isNotEmpty ||
        widget.controller.debts.isNotEmpty;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const PageStorageKey('mobile-overview-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
        children: [
          if (_error) MobileReadError(onRetry: _refresh, hasPrevious: true),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Сейчас',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: const Key('mobile-overview-privacy'),
                tooltip: _hidden ? 'Показать суммы' : 'Скрыть суммы',
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(
                  _hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              IconButton(
                key: const Key('overview-refresh'),
                tooltip: 'Обновить из локальных данных',
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          MobileSection(
            title: 'Финансовая сводка',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Капитал сейчас', style: TextStyle(fontSize: 12)),
                if (!hasCapitalData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Данные о капитале ещё не добавлены'),
                  )
                else
                  MobileMoney(
                    data.capital,
                    currency: data.currency,
                    hidden: _hidden,
                    size: 36,
                    key: const Key('mobile-overview-capital'),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: MobileMetric(
                        label: 'Расходы периода',
                        amount: data.expenses,
                        currency: data.currency,
                        hidden: _hidden,
                        onTap: () => _analysis(StatisticsSection.expenses),
                        key: const Key('mobile-overview-expenses'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MobileMetric(
                        label: 'Чистый поток',
                        amount: data.cashFlow,
                        currency: data.currency,
                        hidden: _hidden,
                        color: data.cashFlow < 0
                            ? context.qestoColors.negative
                            : context.qestoColors.positive,
                        onTap: () => _analysis(StatisticsSection.cashFlow),
                        key: const Key('mobile-overview-net'),
                      ),
                    ),
                  ],
                ),
                Text(
                  data.hasBudget
                      ? 'Лимит периода назначен'
                      : 'Бюджет пока не назначен',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (!_hidden &&
              change != null &&
              _statistics.snapshot.comparisonTransactions.isNotEmpty)
            MobileAnalysisNotice(
              'Расходы ${change >= 0 ? 'выше' : 'ниже'} на ${change.abs().toStringAsFixed(1)}% относительно сопоставимого периода.',
              onTap: () => _analysis(StatisticsSection.expenses),
              icon: Icons.insights_outlined,
            ),
          if (attention.isNotEmpty)
            MobileAnalysisNotice(
              '${attention.length} операций требуют внимания · ${issues.first.title}',
              onTap: () =>
                  TransactionRouteScope.of(context)?.openAttention(_statistics),
              icon: Icons.fact_check_outlined,
              key: const Key('mobile-overview-attention'),
            ),
          if (data.periodTransactions.isEmpty)
            const MobileAnalysisNotice(
              'За этот период операций нет. Добавьте данные через «+» или выберите другой период.',
            ),
          MobileSection(
            title: 'Расходы',
            action: () => _analysis(StatisticsSection.expenses),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_hidden && data.trend.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<OverviewTrendGranularity>(
                      onSelected: (value) => setState(() {
                        _granularity = value;
                        _selected = null;
                      }),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: OverviewTrendGranularity.days,
                          child: Text('По дням'),
                        ),
                        PopupMenuItem(
                          value: OverviewTrendGranularity.weeks,
                          child: Text('По неделям'),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _granularity == OverviewTrendGranularity.days
                                  ? 'По дням'
                                  : 'По неделям',
                            ),
                            const Icon(Icons.expand_more, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  OverviewExpenseTrendChart(
                    points: data.trend,
                    currency: data.currency,
                    granularity: _granularity,
                    height: 160,
                    enableScrub: true,
                    onSelection: (selection) =>
                        setState(() => _selected = selection),
                  ),
                  if (_selected case final selection?) ...[
                    Text(
                      '${formatDate(selection.from)} — ${formatDate(selection.through)} · накоплено ${formatMoney(selection.cumulativeAmount, data.currency)}',
                      key: const Key('mobile-overview-chart-selection'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    TextButton(
                      onPressed: () => _ids(
                        OverviewDrilldownData.forTrend(
                          controller: widget.controller,
                          period: widget.period,
                          selection: selection,
                        ).transactions,
                      ),
                      child: const Text('Операции выбранного интервала'),
                    ),
                  ],
                ] else if (_hidden)
                  const Text('Суммы и график скрыты'),
                for (final row in data.categoryBudgets.take(3))
                  MobileValueRow(
                    title: row.name,
                    amount: row.spent,
                    currency: data.currency,
                    hidden: _hidden,
                    color: row.color,
                    onTap: () => _ids(
                      OverviewDrilldownData.forCategory(
                        controller: widget.controller,
                        period: widget.period,
                        category: row,
                      ).transactions,
                    ),
                  ),
                TextButton(
                  key: const Key('mobile-overview-expenses-detail'),
                  onPressed: () => _analysis(StatisticsSection.expenses),
                  child: const Text('Вся аналитика расходов'),
                ),
              ],
            ),
          ),
          MobileSection(
            title: 'Денежный поток',
            action: () => _analysis(StatisticsSection.cashFlow),
            child: Column(
              children: [
                MobileValueRow(
                  title: 'Доходы',
                  amount: flow.externalInflows,
                  currency: data.currency,
                  hidden: _hidden,
                  color: context.qestoColors.positive,
                  onTap: () => _ids(
                    data.periodTransactions.where(
                      (t) =>
                          t.currency == data.currency &&
                          widget.controller.cashFlowTreatment(t) ==
                              CashFlowTreatment.externalInflow,
                    ),
                  ),
                ),
                MobileValueRow(
                  title: 'Расходы',
                  amount: flow.externalOutflows,
                  currency: data.currency,
                  hidden: _hidden,
                  color: context.qestoColors.negative,
                  onTap: () => _ids(
                    data.periodTransactions.where(
                      (t) =>
                          t.currency == data.currency &&
                          widget.controller.cashFlowTreatment(t) ==
                              CashFlowTreatment.externalOutflow,
                    ),
                  ),
                ),
                MobileValueRow(
                  title: 'Чистый поток',
                  amount: flow.netCashFlow,
                  currency: data.currency,
                  hidden: _hidden,
                ),
                const Text(
                  'Разница за период — не текущий остаток на счетах.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (data.topExpenses.isNotEmpty)
            MobileSection(
              title: 'Крупные расходы',
              action: () =>
                  widget.onOpenDestination(DesktopDestination.transactions),
              child: Column(
                children: [
                  for (final t in data.topExpenses.take(3))
                    MobileValueRow(
                      title: t.merchant ?? t.title ?? 'Операция',
                      amount: t.amount,
                      currency: t.currency,
                      hidden: _hidden,
                      caption: formatDate(t.date),
                      onTap: () => widget.onOpenTransaction(t.id),
                    ),
                ],
              ),
            ),
          if (upcoming.isNotEmpty)
            MobileSection(
              title: 'Ближайшие события',
              action: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => MobileUpcomingPage(
                    controller: widget.controller,
                    onOpenFilteredTransactions:
                        widget.onOpenFilteredTransactions,
                    initiallyHidden: _hidden,
                  ),
                ),
              ),
              child: Column(
                children: [
                  for (final event in upcoming.take(3))
                    MobileUpcomingRow(event: event, hidden: _hidden),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
