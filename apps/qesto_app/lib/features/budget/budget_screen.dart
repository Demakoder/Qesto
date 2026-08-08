import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/qesto_elements.dart';
import '../../core/widgets/states.dart';
import '../../data/models/qesto_models.dart';
import '../shared/placeholder_screen.dart';
import '../statistics/presentation/screens/statistics_screen.dart';
import '../statement_import/presentation/statement_import_screen.dart';
import 'accounts_screen.dart';
import 'add_expense_screen.dart';
import 'budget_details_screen.dart';
import 'state/budget_controller.dart';
import 'widgets/budget_limit_card.dart';
import 'widgets/budget_period_selector.dart';
import 'widgets/spending_donut_card.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({required this.controller, super.key});

  final BudgetController controller;

  @override
  State<BudgetScreen> createState() => BudgetScreenState();
}

class BudgetScreenState extends State<BudgetScreen> {
  late final PageController _pageController;
  late final Map<String, ScrollController> _scrollControllers;
  late int _currentIndex;
  late String _currentPeriodId;

  List<BudgetPeriod> get _periods => widget.controller.periods;

  @override
  void initState() {
    super.initState();
    _currentIndex = _initialIndex();
    _currentPeriodId = _periods[_currentIndex].id;
    _pageController = PageController(initialPage: _currentIndex);
    _scrollControllers = <String, ScrollController>{};
    widget.controller.addListener(_handleControllerChanged);
  }

  int _initialIndex() {
    final reference = widget.controller.referenceDate;
    final index = _periods.indexWhere((period) => period.contains(reference));
    return index < 0 ? 0 : index;
  }

  void scrollToTop() {
    final controller = _scrollControllers[_currentPeriodId];
    if (controller == null) return;
    if (controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _pageController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  ScrollController _scrollControllerFor(String periodId) =>
      _scrollControllers.putIfAbsent(periodId, ScrollController.new);

  void _handleControllerChanged() {
    final index = _periods.indexWhere(
      (period) => period.id == _currentPeriodId,
    );
    if (index < 0 || index == _currentIndex) return;
    _currentIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
    });
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _periods.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _openBudgetDetails(BudgetPeriod period) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BudgetDetailsScreen(
          controller: widget.controller,
          initialPeriodId: period.id,
        ),
      ),
    );
  }

  void _openCapital() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CapitalScreen(accounts: widget.controller.accounts),
      ),
    );
  }

  void _openStatistics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatisticsScreen(budgetController: widget.controller),
      ),
    );
  }

  void _openAddMenu(BudgetPeriod period) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: QestoColors.surface,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Добавить', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              _AddMenuItem(
                icon: Icons.remove_circle_outline_rounded,
                title: 'Добавить расход',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddExpenseScreen(
                        controller: widget.controller,
                        period: period,
                      ),
                    ),
                  );
                },
              ),
              _AddMenuItem(
                icon: Icons.add_circle_outline_rounded,
                title: 'Добавить доход',
                onTap: () => _openPlaceholder(
                  sheetContext,
                  'Добавить доход',
                  Icons.trending_up_rounded,
                ),
              ),
              _AddMenuItem(
                icon: Icons.swap_horiz_rounded,
                title: 'Добавить перевод',
                onTap: () => _openPlaceholder(
                  sheetContext,
                  'Добавить перевод',
                  Icons.swap_horiz_rounded,
                ),
              ),
              _AddMenuItem(
                icon: Icons.assignment_return_rounded,
                title: 'Добавить возврат',
                onTap: () => _openPlaceholder(
                  sheetContext,
                  'Добавить возврат',
                  Icons.assignment_return_rounded,
                ),
              ),
              _AddMenuItem(
                icon: Icons.upload_file_rounded,
                title: 'Загрузить выписку',
                onTap: () => _openStatementImport(sheetContext),
              ),
              _AddMenuItem(
                icon: Icons.receipt_long_rounded,
                title: 'Добавить чек',
                onTap: () => _openPlaceholder(
                  sheetContext,
                  'Добавить чек',
                  Icons.qr_code_scanner_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openStatementImport(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    final importedCount = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => StatementImportScreen(controller: widget.controller),
      ),
    );
    if (!mounted || importedCount == null || importedCount == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено операций: $importedCount')),
    );
  }

  void _openPlaceholder(
    BuildContext sheetContext,
    String title,
    IconData icon,
  ) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderScreen(
          title: title,
          description: 'Эта возможность будет добавлена позднее',
          icon: icon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_periods.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: EmptyState(message: 'В этом периоде пока нет расходов'),
      );
    }

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => PageView.builder(
        controller: _pageController,
        itemCount: _periods.length,
        onPageChanged: (index) => setState(() {
          _currentIndex = index;
          _currentPeriodId = _periods[index].id;
        }),
        itemBuilder: (context, index) {
          final period = _periods[index];
          final summary = widget.controller.summaryFor(period);
          return SingleChildScrollView(
            key: PageStorageKey(period.id),
            controller: _scrollControllerFor(period.id),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 26),
            child: Column(
              children: [
                BudgetPeriodSelector(
                  period: period,
                  hasPrevious: index > 0,
                  hasNext: index < _periods.length - 1,
                  onPrevious: () => _goToPage(index - 1),
                  onNext: () => _goToPage(index + 1),
                ),
                const SizedBox(height: 2),
                BudgetLimitCard(
                  summary: summary,
                  onTap: () => _openBudgetDetails(period),
                ),
                const SizedBox(height: 14),
                if (summary.isEmpty)
                  const EmptyState(
                    message: 'В этом периоде пока нет расходов',
                    icon: Icons.calendar_month_outlined,
                  )
                else
                  SpendingDonutCard(summary: summary),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: QestoButton(
                        label: 'Капитал',
                        icon: Icons.account_balance_rounded,
                        style: QestoButtonStyle.secondary,
                        onPressed: _openCapital,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: QestoButton(
                        label: 'Добавить',
                        icon: Icons.add_circle_rounded,
                        onPressed: () => _openAddMenu(period),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: QestoButton(
                    label: 'Статистика',
                    icon: Icons.query_stats_rounded,
                    style: QestoButtonStyle.secondary,
                    onPressed: _openStatistics,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AddMenuItem extends StatelessWidget {
  const _AddMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      minTileHeight: 52,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          color: QestoColors.primarySoft,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: QestoColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: QestoColors.secondaryText,
      ),
    );
  }
}
