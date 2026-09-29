import 'package:flutter/material.dart';

import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../../data/models/qesto_models.dart';
import '../../../budget/state/budget_controller.dart';
import '../../../shared/placeholder_screen.dart';
import '../../domain/models/statistics_models.dart';
import '../sections/overview_expenses_sections.dart';
import '../sections/secondary_statistics_sections.dart';
import '../state/statistics_controller.dart';
import '../widgets/statistics_components.dart';
import 'statistics_auxiliary_screens.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({required this.budgetController, super.key});

  final BudgetController budgetController;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late final StatisticsController _controller;
  late final List<ScrollController> _sectionScrollControllers;
  final _tabsController = ScrollController();
  final _tabKeys = List.generate(
    StatisticsSection.values.length,
    (_) => GlobalKey(),
  );

  @override
  void initState() {
    super.initState();
    _controller = StatisticsController(
      budgetController: widget.budgetController,
    );
    _sectionScrollControllers = List.generate(
      StatisticsSection.values.length,
      (_) => ScrollController(),
    );
    _controller.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _tabKeys[_controller.section.index].currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 260),
          alignment: 0.42,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _tabsController.dispose();
    for (final controller in _sectionScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        return Scaffold(
          backgroundColor: context.qestoColors.background,
          body: SafeArea(
            child: Column(
              children: [
                _StatisticsHeader(
                  onBack: () => Navigator.of(context).pop(),
                  onNotifications: _openNotifications,
                  onProfile: _openProfile,
                  onRefresh: _refreshAnalytics,
                  isRefreshing: _controller.isRefreshing,
                ),
                _QuickControls(
                  controller: _controller,
                  onPeriod: _showPeriodSheet,
                  onComparison: _showComparisonSheet,
                  onFilters: _showFilterSheet,
                  onTracked: () =>
                      _push(TrackedStatisticsScreen(controller: _controller)),
                  onExplore: () => _push(const ExploreStatisticsScreen()),
                  onQuality: () =>
                      _push(DataQualityScreen(controller: _controller)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: context.qestoColors.primarySoft,
                        borderRadius: QestoGeometry.control,
                      ),
                      child: Text(
                        statisticsRangeLabel(_controller.query.period),
                        style: TextStyle(
                          color: context.qestoColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                _StatisticsTabs(
                  controller: _controller,
                  scrollController: _tabsController,
                  tabKeys: _tabKeys,
                ),
                if (snapshot.dataQuality.issues.isNotEmpty &&
                    _controller.section == StatisticsSection.overview)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                    child: InkWell(
                      onTap: () =>
                          _push(DataQualityScreen(controller: _controller)),
                      borderRadius: QestoGeometry.control,
                      child: StatisticsInfoBanner(
                        message:
                            'Статистика может быть неполной: ${snapshot.dataQuality.issues.length} операций или признаков требуют проверки',
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                  ),
                Expanded(child: _buildSectionBody()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionBody() => IndexedStack(
    index: _controller.section.index,
    children: [
      OverviewStatisticsSection(
        controller: _controller,
        scrollController: _sectionScrollControllers[0],
      ),
      ExpensesStatisticsSection(
        controller: _controller,
        scrollController: _sectionScrollControllers[1],
      ),
      RhythmStatisticsSection(
        controller: _controller,
        scrollController: _sectionScrollControllers[2],
      ),
      MerchantsStatisticsSection(
        controller: _controller,
        scrollController: _sectionScrollControllers[3],
      ),
      CategoriesStatisticsSection(
        controller: _controller,
        scrollController: _sectionScrollControllers[4],
      ),
      CashFlowStatisticsSection(
        controller: _controller,
        scrollController: _sectionScrollControllers[5],
      ),
      BudgetQualityStatisticsSection(
        controller: _controller,
        scrollController: _sectionScrollControllers[6],
      ),
      RecurringStatisticsSection(
        controller: _controller,
        scrollController: _sectionScrollControllers[7],
      ),
    ],
  );

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _openNotifications() {
    _push(
      const PlaceholderScreen(
        title: 'Уведомления',
        description: 'Новые выводы статистики появятся здесь',
        icon: Icons.notifications_none_rounded,
      ),
    );
  }

  void _openProfile() {
    _push(
      const PlaceholderScreen(
        title: 'Профиль',
        description: 'Настройки профиля будут добавлены позднее',
        icon: Icons.person_outline_rounded,
      ),
    );
  }

  Future<void> _showPeriodSheet() async {
    final selected = await showModalBottomSheet<StatisticsPeriodPreset>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PeriodSheet(selected: _controller.query.preset),
    );
    if (selected == null || !mounted) return;
    if (selected == StatisticsPeriodPreset.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: widget.budgetController.referenceDate,
        initialDateRange: DateTimeRange(
          start: _controller.query.period.start,
          end: _controller.query.period.end,
        ),
      );
      if (range != null) _controller.setCustomPeriod(range.start, range.end);
    } else {
      _controller.setPeriodPreset(selected);
    }
  }

  Future<void> _showComparisonSheet() async {
    final selected = await showModalBottomSheet<StatisticsComparison>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          _ComparisonSheet(selected: _controller.query.comparison),
    );
    if (selected != null) _controller.setComparison(selected);
  }

  Future<void> _showFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _StatisticsFilterSheet(controller: _controller),
    );
  }

  Future<void> _refreshAnalytics() async {
    try {
      await _controller.refreshFromLocalData();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить аналитику')),
      );
    }
  }
}

class _StatisticsHeader extends StatelessWidget {
  const _StatisticsHeader({
    required this.onBack,
    required this.onNotifications,
    required this.onProfile,
    required this.onRefresh,
    required this.isRefreshing,
  });
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21),
          ),
          Expanded(
            child: Text(
              'Статистика',
              key: const Key('statistics-title'),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Обновить аналитику',
            onPressed: isRefreshing ? null : onRefresh,
            icon: isRefreshing
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 22),
          ),
          IconButton(
            onPressed: onNotifications,
            tooltip: 'Уведомления',
            icon: const Icon(Icons.notifications_none_rounded, size: 27),
            color: context.qestoColors.secondaryText,
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: 'Профиль пользователя',
            child: InkResponse(
              onTap: onProfile,
              radius: 26,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      context.qestoColors.controlHighlight,
                      context.qestoColors.controlMid,
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF4B5874),
                  size: 27,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickControls extends StatelessWidget {
  const _QuickControls({
    required this.controller,
    required this.onPeriod,
    required this.onComparison,
    required this.onFilters,
    required this.onTracked,
    required this.onExplore,
    required this.onQuality,
  });
  final StatisticsController controller;
  final VoidCallback onPeriod;
  final VoidCallback onComparison;
  final VoidCallback onFilters;
  final VoidCallback onTracked;
  final VoidCallback onExplore;
  final VoidCallback onQuality;

  @override
  Widget build(BuildContext context) {
    final quality = controller.snapshot.dataQuality;
    return SizedBox(
      height: 68,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: [
            StatisticsIconButton(
              key: const Key('statistics-period-button'),
              icon: Icons.calendar_month_outlined,
              tooltip: 'Период',
              onPressed: onPeriod,
            ),
            const SizedBox(width: 9),
            StatisticsIconButton(
              key: const Key('statistics-comparison-button'),
              icon: Icons.compare_arrows_rounded,
              tooltip: 'Сравнение',
              onPressed: onComparison,
            ),
            const SizedBox(width: 9),
            StatisticsIconButton(
              key: const Key('statistics-filter-button'),
              icon: Icons.tune_rounded,
              tooltip: 'Фильтры',
              onPressed: onFilters,
              badge: controller.query.activeFilterCount == 0
                  ? null
                  : '${controller.query.activeFilterCount}',
            ),
            const SizedBox(width: 26),
            StatisticsIconButton(
              key: const Key('statistics-tracked-button'),
              icon: Icons.star_border_rounded,
              tooltip: 'Отслеживаемое',
              onPressed: onTracked,
            ),
            const SizedBox(width: 9),
            StatisticsIconButton(
              key: const Key('statistics-explore-button'),
              icon: Icons.search_rounded,
              tooltip: 'Исследовать',
              onPressed: onExplore,
            ),
            const SizedBox(width: 9),
            StatisticsIconButton(
              key: const Key('statistics-quality-button'),
              icon: Icons.bar_chart_rounded,
              tooltip: 'Полнота данных',
              onPressed: onQuality,
              badge: quality.issues.isEmpty
                  ? null
                  : quality.criticalCount > 0
                  ? '!'
                  : '${quality.issues.length}',
              badgeColor: quality.criticalCount > 0
                  ? context.qestoColors.danger
                  : context.qestoColors.orange,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsTabs extends StatelessWidget {
  const _StatisticsTabs({
    required this.controller,
    required this.scrollController,
    required this.tabKeys,
  });
  final StatisticsController controller;
  final ScrollController scrollController;
  final List<GlobalKey> tabKeys;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 53,
      child: SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 18, right: 72),
        child: Row(
          children: [
            for (final section in StatisticsSection.values)
              InkWell(
                key: tabKeys[section.index],
                onTap: () => controller.selectSection(section),
                child: Container(
                  key: Key('statistics-tab-${section.name}'),
                  margin: const EdgeInsets.only(right: 28),
                  padding: const EdgeInsets.only(top: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: controller.section == section
                            ? context.qestoColors.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    section.label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: controller.section == section
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: controller.section == section
                          ? context.qestoColors.primary
                          : context.qestoColors.secondaryText,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSheet extends StatelessWidget {
  const _PeriodSheet({required this.selected});
  final StatisticsPeriodPreset selected;

  @override
  Widget build(BuildContext context) {
    final labels = <StatisticsPeriodPreset, String>{
      StatisticsPeriodPreset.currentWeek: 'Текущая неделя',
      StatisticsPeriodPreset.currentBudget: 'Текущий бюджетный период',
      StatisticsPeriodPreset.last30Days: 'Последние 30 дней',
      StatisticsPeriodPreset.threeMonths: '3 месяца',
      StatisticsPeriodPreset.sixMonths: '6 месяцев',
      StatisticsPeriodPreset.currentYear: 'Текущий год',
      StatisticsPeriodPreset.last12Months: 'Последние 12 месяцев',
      StatisticsPeriodPreset.allTime: 'Всё время',
      StatisticsPeriodPreset.custom: 'Произвольный период',
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
        children: [
          Text('Период', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final entry in labels.entries)
            ListTile(
              onTap: () => Navigator.of(context).pop(entry.key),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                selected == entry.key
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected == entry.key
                    ? context.qestoColors.primary
                    : context.qestoColors.secondaryText,
              ),
              title: Text(entry.value),
            ),
        ],
      ),
    );
  }
}

class _ComparisonSheet extends StatelessWidget {
  const _ComparisonSheet({required this.selected});
  final StatisticsComparison selected;

  @override
  Widget build(BuildContext context) {
    final labels = <StatisticsComparison, String>{
      StatisticsComparison.none: 'Без сравнения',
      StatisticsComparison.previousSameLength:
          'Предыдущий период такой же длины',
      StatisticsComparison.previousYear: 'Аналогичный период прошлого года',
      StatisticsComparison.average3: 'Среднее за 3 периода',
      StatisticsComparison.average6: 'Среднее за 6 периодов',
      StatisticsComparison.average12: 'Среднее за 12 периодов',
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
        children: [
          Text('Сравнение', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final entry in labels.entries)
            ListTile(
              onTap: () => Navigator.of(context).pop(entry.key),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                selected == entry.key
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected == entry.key
                    ? context.qestoColors.primary
                    : context.qestoColors.secondaryText,
              ),
              title: Text(entry.value),
            ),
        ],
      ),
    );
  }
}

class _StatisticsFilterSheet extends StatefulWidget {
  const _StatisticsFilterSheet({required this.controller});
  final StatisticsController controller;

  @override
  State<_StatisticsFilterSheet> createState() => _StatisticsFilterSheetState();
}

class _StatisticsFilterSheetState extends State<_StatisticsFilterSheet> {
  late Set<String> accounts;
  late Set<String> categories;
  late Set<String> subcategories;
  late Set<String> merchants;
  late Set<TransactionType> types;
  late bool includeCash;
  late bool includeLarge;
  late bool includeRecurring;
  late bool includeRefunds;
  late bool includeUncategorized;
  late bool onlyConfirmed;

  @override
  void initState() {
    super.initState();
    final query = widget.controller.query;
    accounts = {...query.accountIds};
    categories = {...query.categoryIds};
    subcategories = {...query.subcategoryIds};
    merchants = {...query.merchantNames};
    types = {...query.transactionTypes};
    includeCash = query.includeCash;
    includeLarge = query.includeLargePurchases;
    includeRecurring = query.includeRecurring;
    includeRefunds = query.includeRefunds;
    includeUncategorized = query.includeUncategorized;
    onlyConfirmed = query.onlyConfirmed;
  }

  @override
  Widget build(BuildContext context) {
    final allSubcategories =
        widget.controller.budgetController.categories
            .expand((item) => item.subcategories)
            .toSet()
            .toList()
          ..sort();
    final allMerchants = widget.controller.snapshot.merchants
        .map((item) => item.id)
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Фильтры',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: _resetLocal,
                  child: const Text('Сбросить'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                _FilterGroup(
                  title: 'Счета',
                  children: [
                    for (final item
                        in widget.controller.budgetController.accounts)
                      FilterChip(
                        label: Text(item.title),
                        selected: accounts.contains(item.id),
                        onSelected: (_) =>
                            setState(() => _toggle(accounts, item.id)),
                      ),
                  ],
                ),
                _FilterGroup(
                  title: 'Категории',
                  children: [
                    for (final item
                        in widget.controller.budgetController.categories)
                      FilterChip(
                        label: Text(item.name),
                        selected: categories.contains(item.id),
                        onSelected: (_) =>
                            setState(() => _toggle(categories, item.id)),
                      ),
                  ],
                ),
                _FilterGroup(
                  title: 'Подкатегории',
                  children: [
                    for (final item in allSubcategories.take(14))
                      FilterChip(
                        label: Text(item),
                        selected: subcategories.contains(item),
                        onSelected: (_) =>
                            setState(() => _toggle(subcategories, item)),
                      ),
                  ],
                ),
                _FilterGroup(
                  title: 'Продавцы',
                  children: [
                    for (final item in allMerchants.take(14))
                      FilterChip(
                        label: Text(item),
                        selected: merchants.contains(item),
                        onSelected: (_) =>
                            setState(() => _toggle(merchants, item)),
                      ),
                  ],
                ),
                _FilterGroup(
                  title: 'Типы операций',
                  children: [
                    for (final item in TransactionType.values)
                      FilterChip(
                        label: Text(_transactionTypeLabel(item)),
                        selected: types.contains(item),
                        onSelected: (_) => setState(() => _toggle(types, item)),
                      ),
                  ],
                ),
                SwitchListTile(
                  value: includeCash,
                  onChanged: (value) => setState(() => includeCash = value),
                  title: const Text('Наличные'),
                ),
                SwitchListTile(
                  value: includeLarge,
                  onChanged: (value) => setState(() => includeLarge = value),
                  title: const Text('Крупные покупки'),
                ),
                SwitchListTile(
                  value: includeRecurring,
                  onChanged: (value) =>
                      setState(() => includeRecurring = value),
                  title: const Text('Регулярные операции'),
                ),
                SwitchListTile(
                  value: includeRefunds,
                  onChanged: (value) => setState(() => includeRefunds = value),
                  title: const Text('Возвраты'),
                ),
                SwitchListTile(
                  value: includeUncategorized,
                  onChanged: (value) =>
                      setState(() => includeUncategorized = value),
                  title: const Text('Операции без категории'),
                ),
                SwitchListTile(
                  value: onlyConfirmed,
                  onChanged: (value) => setState(() => onlyConfirmed = value),
                  title: const Text('Только подтверждённые'),
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: FilledButton(
                key: const Key('statistics-apply-filters'),
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text('Применить'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _apply() {
    widget.controller.applyFilters(
      accountIds: accounts,
      categoryIds: categories,
      subcategoryIds: subcategories,
      merchantNames: merchants,
      transactionTypes: types,
      includeCash: includeCash,
      includeLargePurchases: includeLarge,
      includeRecurring: includeRecurring,
      includeRefunds: includeRefunds,
      includeUncategorized: includeUncategorized,
      onlyConfirmed: onlyConfirmed,
    );
    Navigator.of(context).pop();
  }

  void _resetLocal() {
    setState(() {
      accounts.clear();
      categories.clear();
      subcategories.clear();
      merchants.clear();
      types.clear();
      includeCash = true;
      includeLarge = true;
      includeRecurring = true;
      includeRefunds = true;
      includeUncategorized = true;
      onlyConfirmed = false;
    });
  }

  void _toggle<T>(Set<T> values, T value) =>
      values.contains(value) ? values.remove(value) : values.add(value);

  String _transactionTypeLabel(TransactionType type) => switch (type) {
    TransactionType.expense => 'Расход',
    TransactionType.income => 'Доход',
    TransactionType.transfer => 'Перевод',
    TransactionType.refund => 'Возврат',
    TransactionType.savingsTransfer => 'В накопления',
    TransactionType.investment => 'Инвестиция',
  };
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => QestoCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 7, children: children),
      ],
    ),
  );
}
