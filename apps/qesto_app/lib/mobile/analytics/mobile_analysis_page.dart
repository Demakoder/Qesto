import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/services/cash_flow_calculation_service.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/transaction_route_scope.dart';
import '../../features/profile/services/cbr_currency_service.dart';
import '../../features/statistics/domain/models/statistics_models.dart';
import '../../features/statistics/presentation/screens/statistics_screen.dart';
import '../../features/statistics/presentation/state/analytics_presentation_selectors.dart';
import '../../features/statistics/presentation/state/statistics_controller.dart';
import '../../features/statistics/presentation/widgets/statistics_charts.dart';
import 'mobile_financial_widgets.dart';
import 'mobile_statistics_controls.dart';

/// Each route owns only query/selection UI state. The financial controller and
/// all selectors/services are the same ones used by desktop presentation.
class MobileAnalysisPage extends StatefulWidget {
  const MobileAnalysisPage({
    required this.controller,
    required this.section,
    required this.onOpenFilteredTransactions,
    this.initialRange,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final StatisticsSection section;
  final StatisticsDateRange? initialRange;
  final ValueChanged<List<String>> onOpenFilteredTransactions;
  final bool initiallyHidden;
  @override
  State<MobileAnalysisPage> createState() => _MobileAnalysisPageState();
}

class _MobileAnalysisPageState extends State<MobileAnalysisPage> {
  late final StatisticsController _statistics;
  late bool _hidden = widget.initiallyHidden;
  late String _currency = widget.controller.user.expenseDisplayCurrency;
  DateTime? _day;
  bool _cumulative = true;
  bool _refreshing = false;
  bool _error = false;
  @override
  void initState() {
    super.initState();
    _statistics = StatisticsController(budgetController: widget.controller);
    final range = widget.initialRange;
    if (range != null) _statistics.setCustomPeriod(range.start, range.end);
    _statistics.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (_day != null && !_statistics.query.period.contains(_day!)) {
          _day = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _statistics.removeListener(_changed);
    _statistics.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      await _statistics.refreshFromLocalData();
      setState(() => _error = false);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _open(Iterable<BudgetTransaction> rows) =>
      widget.onOpenFilteredTransactions(
        rows.map((t) => t.id).toList(growable: false),
      );
  int _convert(int value) => CbrCurrencyService.convertRubles(value, _currency);
  bool _consumer(BudgetTransaction t) =>
      _statistics.calculationService.isConsumerExpense(t);
  List<BudgetTransaction> _dayRows(DateTime date) => _statistics
      .snapshot
      .transactions
      .where(_consumer)
      .where((t) => DateUtils.isSameDay(t.date, date))
      .toList();
  Future<void> _options() async {
    final action = await mobileChoice(context, 'Параметры аналитики', const {
      'comparison': 'Сравнение периодов',
      'currency': 'Валюта отображения расходов',
      'quality': 'Качество и полнота данных',
      'refresh': 'Обновить локальные данные',
    }, '');
    if (!mounted) return;
    switch (action) {
      case 'comparison':
        final selected = await mobileChoice(
          context,
          'Сравнение',
          mobileComparisonLabels,
          _statistics.query.comparison,
        );
        if (selected != null && mounted) _statistics.setComparison(selected);
      case 'currency':
        final selected = await mobileChoice(context, 'Валюта расходов', {
          for (final c in CbrCurrencyService.expenseDisplayCurrencies) c: c,
        }, _currency);
        if (selected == null || !mounted) return;
        try {
          await widget.controller.updateExpenseDisplayCurrency(selected);
          if (mounted) setState(() => _currency = selected);
        } catch (_) {
          if (mounted) setState(() => _error = true);
        }
      case 'quality':
        final report = _statistics.snapshot.dataQuality;
        showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Качество и полнота данных',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Text(
                  'Показатели основаны на загруженных данных. Отсутствие операций не доказывает полноту банковской истории.',
                ),
                for (final issue in report.issues)
                  ListTile(title: Text(issue.title)),
                if (report.issues.isEmpty)
                  const Text('Известных предупреждений нет'),
                if (report.issues.any((i) => i.transactionId != null))
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      TransactionRouteScope.of(
                        context,
                      )?.openAttention(_statistics);
                    },
                    child: const Text('Операции, требующие внимания'),
                  ),
              ],
            ),
          ),
        );
      case 'refresh':
        await _refresh();
    }
  }

  void _dayList() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/analytics/days'),
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Расходы по дням')),
        body: ListView.builder(
          itemCount: _statistics.snapshot.daily.length,
          itemBuilder: (context, index) {
            final p = _statistics.snapshot.daily[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MobileValueRow(
                title: formatDate(p.date),
                amount: _convert(p.amount),
                currency: _currency,
                hidden: _hidden,
                caption: '${p.count} операций',
                onTap: () => _open(_dayRows(p.date)),
              ),
            );
          },
        ),
      ),
    ),
  );
  Widget _groupList(
    String title,
    List<StatisticsGroupStat> groups,
    List<BudgetTransaction> Function(String) rows,
  ) {
    Widget row(StatisticsGroupStat group) => MobileValueRow(
      title: group.label,
      amount: _convert(group.amount),
      currency: _currency,
      hidden: _hidden,
      caption: '${group.count} операций',
      color: group.colorValue == null ? null : Color(group.colorValue!),
      onTap: () => _open(rows(group.id)),
    );
    return MobileSection(
      title: title,
      child: Column(
        children: [
          if (groups.isEmpty) const Text('Расходов в этой выборке нет'),
          for (final g in groups.take(5)) row(g),
          if (groups.length > 5)
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(title)),
                    body: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: groups.length,
                      itemBuilder: (_, i) => row(groups[i]),
                    ),
                  ),
                ),
              ),
              child: Text('Показать все (${groups.length})'),
            ),
        ],
      ),
    );
  }

  List<Widget> _expenses() {
    final s = _statistics.snapshot;
    final selected = s.daily
        .where((p) => DateUtils.isSameDay(p.date, _day))
        .firstOrNull;
    final hasComparison =
        _statistics.query.comparison != StatisticsComparison.none &&
        s.comparisonTransactions.isNotEmpty;
    return [
      MobileSection(
        title: 'Расходы периода',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileMoney(
              _convert(s.summary.expenses),
              currency: _currency,
              hidden: _hidden,
              size: 34,
            ),
            Text('${s.summary.purchaseCount} покупок'),
            MobileValueRow(
              title: 'Средний чек',
              amount: _convert(s.summary.averageCheck.round()),
              currency: _currency,
              hidden: _hidden,
            ),
            if (_statistics.query.comparison != StatisticsComparison.none)
              Text(
                _hidden
                    ? 'Сравнение скрыто'
                    : !hasComparison || s.summary.changePercent == null
                    ? 'Нет сопоставимых данных для сравнения'
                    : 'Изменение расходов: ${s.summary.changePercent! >= 0 ? '+' : ''}${s.summary.changePercent!.toStringAsFixed(1)}%',
              ),
            TextButton(
              onPressed: () => _open(s.transactions.where(_consumer)),
              child: const Text('Все операции расходов'),
            ),
          ],
        ),
      ),
      if (!_hidden) ...[
        Row(
          children: [
            const Expanded(child: Text('Динамика расходов')),
            PopupMenuButton<bool>(
              tooltip: 'Вид графика',
              onSelected: (v) => setState(() => _cumulative = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: true, child: Text('Накопительно')),
                PopupMenuItem(value: false, child: Text('За день')),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_cumulative ? 'Накопительно' : 'За день'),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
        StatisticsLineChartCard(
          key: const Key('mobile-analysis-chart'),
          title: '',
          points: s.daily,
          comparison: hasComparison ? s.comparisonDaily : const [],
          cumulative: _cumulative,
          currency: _currency,
          amountConverter: _convert,
          height: 160,
          enableScrub: true,
          selectedDate: _day,
          onDaySelected: (date) => setState(() => _day = date),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(
                  '${formatDate(selected.date)} · за день ${formatMoney(_convert(selected.amount), _currency)} · накоплено ${formatMoney(_convert(selected.cumulative), _currency)}',
                  key: const Key('mobile-analysis-chart-selection'),
                ),
                TextButton(
                  onPressed: () => _open(_dayRows(selected.date)),
                  child: const Text('Операции выбранного дня'),
                ),
              ],
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Коснитесь графика или проведите по нему для выбора дня.',
            ),
          ),
      ],
      TextButton.icon(
        key: const Key('mobile-analysis-day-list'),
        onPressed: _dayList,
        icon: const Icon(Icons.view_list_outlined),
        label: const Text('Даты и суммы списком'),
      ),
      _groupList(
        'Категории расходов',
        s.categories,
        _statistics.transactionsForCategory,
      ),
      _groupList('Продавцы', s.merchants, _statistics.transactionsForMerchant),
      TextButton.icon(
        onPressed: _moreExpenses,
        icon: const Icon(Icons.insights_outlined),
        label: const Text('Дополнительные показатели расходов'),
      ),
      if (_currency != 'RUB')
        Text(
          'Пересчёт отображения: встроенный курс ЦБ от ${formatDate(CbrCurrencyService.embeddedSnapshot.date)}. Исходные суммы не изменены.',
        ),
    ];
  }

  void _moreExpenses() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/analytics/expenses/more'),
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Подробности расходов')),
        body: ListenableBuilder(
          listenable: _statistics,
          builder: (context, _) {
            final s = _statistics.snapshot;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                MobileSection(
                  title: 'Чеки и частота',
                  child: Column(
                    children: [
                      MobileValueRow(
                        title: 'Медианный чек',
                        amount: _convert(s.summary.medianCheck.round()),
                        currency: _currency,
                        hidden: _hidden,
                      ),
                      MobileValueRow(
                        title: 'Средние расходы за день',
                        amount: _convert(s.summary.averageDailyExpense.round()),
                        currency: _currency,
                        hidden: _hidden,
                      ),
                      for (final m in s.merchants)
                        MobileValueRow(
                          title: m.label,
                          amount: _convert(m.averageCheck.round()),
                          currency: _currency,
                          hidden: _hidden,
                          caption: _hidden
                              ? '${m.count} покупок'
                              : '${m.count} покупок · медиана ${formatMoney(_convert(m.medianCheck.round()), _currency)}',
                          onTap: () =>
                              _open(_statistics.transactionsForMerchant(m.id)),
                        ),
                    ],
                  ),
                ),
                MobileSection(
                  title: 'Диапазоны сумм',
                  child: Column(
                    children: [
                      for (final b in s.buckets)
                        MobileValueRow(
                          title: b.label,
                          amount: _convert(b.amount),
                          currency: _currency,
                          hidden: _hidden,
                          caption: '${b.count} операций',
                        ),
                    ],
                  ),
                ),
                MobileSection(
                  title: 'Крупнейшие операции',
                  child: Column(
                    children: [
                      for (final t in s.largestTransactions)
                        MobileValueRow(
                          title: t.merchant ?? t.title ?? 'Операция',
                          amount: _convert(t.amount),
                          currency: _currency,
                          hidden: _hidden,
                          caption: formatDate(t.date),
                          onTap: () => _open([t]),
                        ),
                    ],
                  ),
                ),
                if (!_hidden && s.insights.isNotEmpty)
                  MobileSection(
                    title: 'Наблюдения по данным',
                    child: Column(
                      children: [
                        for (final i in s.insights)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(i.title),
                            subtitle: Text(
                              '${i.explanation}\n${i.calculation}',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  List<Widget> _flow() {
    final q = _statistics.query;
    final currency = widget.controller.user.defaultCurrency;
    final rows = _statistics.snapshot.transactions
        .where((t) => t.currency == currency)
        .toList();
    final flow = const CashFlowCalculationService().calculate(
      transactions: rows,
      from: q.period.start,
      toExclusive: q.period.end.add(const Duration(days: 1)),
      currency: currency,
    );
    List<BudgetTransaction> treated(CashFlowTreatment t) =>
        rows.where((r) => widget.controller.cashFlowTreatment(r) == t).toList();
    Widget groups(String title, CashFlowTreatment treatment) {
      final members = cashFlowDisplayMembers(
        widget.controller,
        rows,
        treatment,
      );
      final amounts = cashFlowDisplayGroups(widget.controller, rows, treatment);
      final entries = amounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      Widget row(MapEntry<String, int> e) => MobileValueRow(
        title: e.key,
        amount: e.value,
        currency: currency,
        hidden: _hidden,
        caption: '${members[e.key]!.length} операций',
        onTap: () => _open(members[e.key]!),
      );
      return MobileSection(
        title: title,
        child: Column(
          children: [
            if (entries.isEmpty) const Text('Нет операций'),
            for (final e in entries.take(5)) row(e),
            if (entries.length > 5)
              TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(title)),
                      body: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [for (final e in entries) row(e)],
                      ),
                    ),
                  ),
                ),
                child: Text('Показать все (${entries.length})'),
              ),
          ],
        ),
      );
    }

    return [
      MobileSection(
        title: 'Чистый денежный поток',
        child: Column(
          children: [
            MobileMoney(
              flow.netCashFlow,
              currency: currency,
              hidden: _hidden,
              size: 34,
              showSign: true,
              color: flow.netCashFlow < 0
                  ? context.qestoColors.negative
                  : context.qestoColors.positive,
            ),
            MobileValueRow(
              title: 'Доходы',
              amount: flow.externalInflows,
              currency: currency,
              hidden: _hidden,
              onTap: () => _open(treated(CashFlowTreatment.externalInflow)),
            ),
            MobileValueRow(
              title: 'Расходы',
              amount: flow.externalOutflows,
              currency: currency,
              hidden: _hidden,
              onTap: () => _open(treated(CashFlowTreatment.externalOutflow)),
            ),
            const Text(
              'Доходы − расходы. Не остаток на счетах. Внутренние переводы исключены.',
            ),
            TextButton(
              onPressed: () => _open(rows),
              child: const Text('Все операции потока'),
            ),
          ],
        ),
      ),
      if (_statistics.snapshot.transactions.any((t) => t.currency != currency))
        MobileAnalysisNotice(
          'Поток показан в $currency. Операции других валют не суммируются.',
        ),
      groups('Источники дохода', CashFlowTreatment.externalInflow),
      groups('Направления расходов', CashFlowTreatment.externalOutflow),
      if (treated(CashFlowTreatment.internalTransfer).isNotEmpty)
        TextButton(
          onPressed: () => _open(treated(CashFlowTreatment.internalTransfer)),
          child: const Text('Исключённые внутренние переводы'),
        ),
      MobileSection(
        title: 'Поток по месяцам',
        child: Column(
          children: [
            for (
              var month = DateTime(q.period.start.year, q.period.start.month);
              !month.isAfter(q.period.end);
              month = DateTime(month.year, month.month + 1)
            )
              _monthFlow(month, rows, currency),
          ],
        ),
      ),
    ];
  }

  Widget _monthFlow(
    DateTime month,
    List<BudgetTransaction> rows,
    String currency,
  ) {
    final end = DateTime(month.year, month.month + 1);
    final members = rows
        .where((t) => !t.date.isBefore(month) && t.date.isBefore(end))
        .toList();
    final flow = const CashFlowCalculationService().calculate(
      transactions: members,
      from: month,
      toExclusive: end,
      currency: currency,
    );
    return MobileValueRow(
      title: '${month.month.toString().padLeft(2, '0')}.${month.year}',
      amount: flow.netCashFlow,
      currency: currency,
      hidden: _hidden,
      caption: _hidden
          ? 'Суммы скрыты'
          : 'Доходы ${formatMoney(flow.externalInflows, currency)} · расходы ${formatMoney(flow.externalOutflows, currency)}',
      color: flow.netCashFlow < 0
          ? context.qestoColors.negative
          : context.qestoColors.positive,
      onTap: () => _open(members),
    );
  }

  List<Widget> _rhythm() {
    final s = _statistics.snapshot;
    final weeks = rhythmWeekAmounts(_statistics);
    final cycle = rhythmSalaryCycle(_statistics);
    const labels = [
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
      'Воскресенье',
    ];
    return [
      if (!_hidden)
        MobileSection(
          title: 'Календарь расходов',
          child: StatisticsHeatmap(
            points: s.daily,
            onDayTap: (point) => _open(_dayRows(point.date)),
          ),
        ),
      MobileSection(
        title: 'Расходы по дням недели',
        child: Column(
          children: [
            for (final w in s.weekdays)
              MobileValueRow(
                title: labels[w.weekday - 1],
                amount: w.amount,
                hidden: _hidden,
                caption: _hidden
                    ? '${w.count} операций'
                    : '${w.count} операций · чек ${formatMoney(w.averageCheck.round(), 'RUB')}',
                onTap: () => _open(
                  s.transactions
                      .where(_consumer)
                      .where((t) => t.date.weekday == w.weekday),
                ),
              ),
          ],
        ),
      ),
      MobileSection(
        title: 'Недели периода',
        child: Column(
          children: [
            for (final w in weeks.entries)
              MobileValueRow(
                title: '${w.key}-я неделя',
                amount: w.value,
                hidden: _hidden,
                onTap: () => _open(
                  s.transactions
                      .where(_consumer)
                      .where(
                        (t) =>
                            t.date
                                        .difference(
                                          _statistics.query.period.start,
                                        )
                                        .inDays ~/
                                    7 +
                                1 ==
                            w.key,
                      ),
                ),
              ),
          ],
        ),
      ),
      MobileSection(
        title: 'После поступления дохода',
        child: cycle == null
            ? const Text(
                'Нет поступлений в выбранной выборке. Цикл не определён.',
              )
            : Column(
                children: [
                  MobileValueRow(
                    title: 'Первые 5 дней',
                    amount: cycle.expenses,
                    hidden: _hidden,
                    caption: _hidden
                        ? 'Суммы скрыты'
                        : 'С ${formatDate(cycle.day)} · ${(cycle.share * 100).toStringAsFixed(0)}% расходов',
                    onTap: () => _open(
                      s.transactions
                          .where(_consumer)
                          .where(
                            (t) =>
                                !t.date.isBefore(cycle.day) &&
                                t.date.difference(cycle.day).inDays < 5,
                          ),
                    ),
                  ),
                  const Text(
                    'Наблюдение по истории, не оценка привычек и не прогноз зарплаты.',
                  ),
                ],
              ),
      ),
      TextButton.icon(
        onPressed: _dayList,
        icon: const Icon(Icons.calendar_view_month),
        label: const Text('Календарь: даты и суммы списком'),
      ),
      const MobileAnalysisNotice(
        'Для расчёта времени суток нужно больше операций с точным временем.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.section.label),
      actions: [
        IconButton(
          key: const Key('mobile-analysis-privacy'),
          tooltip: _hidden ? 'Показать суммы' : 'Скрыть суммы',
          onPressed: () => setState(() => _hidden = !_hidden),
          icon: const Icon(Icons.visibility_outlined),
        ),
        IconButton(
          key: const Key('mobile-analysis-options'),
          tooltip: 'Параметры аналитики',
          onPressed: _options,
          icon: const Icon(Icons.more_vert),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: PageStorageKey('mobile-analysis-${widget.section.name}'),
          padding: const EdgeInsets.all(16),
          children: [
            MobilePeriodControl(
              controller: _statistics,
              onFilter: () => showStatisticsFilterSheet(
                context,
                _statistics,
                compact: true,
              ),
            ),
            MobileActiveFilters(controller: _statistics),
            if (_refreshing) const LinearProgressIndicator(),
            if (_error) MobileReadError(onRetry: _refresh, hasPrevious: true),
            if (_statistics.snapshot.transactions.isEmpty)
              const MobileAnalysisNotice(
                'В выбранном периоде и фильтрах нет операций. Проверьте выборку или добавьте данные.',
              ),
            if (_statistics.snapshot.dataQuality.issues.isNotEmpty)
              MobileAnalysisNotice(
                'Есть предупреждения о данных. Итоги могут быть неполными.',
                onTap: () => TransactionRouteScope.of(
                  context,
                )?.openAttention(_statistics),
                icon: Icons.info_outline,
              ),
            ...switch (widget.section) {
              StatisticsSection.cashFlow => _flow(),
              StatisticsSection.rhythm => _rhythm(),
              _ => _expenses(),
            },
          ],
        ),
      ),
    ),
  );
}
