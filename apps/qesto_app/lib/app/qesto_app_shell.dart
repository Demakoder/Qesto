import 'package:flutter/material.dart';

import '../core/theme/qesto_theme.dart';
import '../core/widgets/qesto_bottom_navigation.dart';
import '../core/widgets/qesto_card.dart';
import '../core/widgets/sticky_app_header.dart';
import '../data/models/qesto_models.dart';
import '../data/repositories/qesto_repository.dart';
import '../features/benefits/benefits_screen.dart';
import '../features/budget/budget_screen.dart';
import '../features/budget/state/budget_controller.dart';
import '../features/history/action_history_screen.dart';
import '../features/notification_import/data/notification_capture_service.dart';
import '../features/notification_import/presentation/notification_import_screen.dart';
import '../features/savings/savings_screen.dart';
import '../features/shared/placeholder_screen.dart';

class QestoAppShell extends StatefulWidget {
  const QestoAppShell({
    required this.data,
    required this.repository,
    super.key,
  });

  final QestoAppData data;
  final QestoRepository repository;

  @override
  State<QestoAppShell> createState() => _QestoAppShellState();
}

class _QestoAppShellState extends State<QestoAppShell> {
  final _budgetKey = GlobalKey<BudgetScreenState>();
  final _benefitsKey = GlobalKey<BenefitsScreenState>();
  final _savingsKey = GlobalKey<SavingsScreenState>();
  var _selectedIndex = 0;
  late final BudgetController _budgetController;

  static const _titles = ['Бюджет', 'Выгода', 'Накопления'];

  @override
  void initState() {
    super.initState();
    _budgetController = BudgetController(
      configuration: widget.data.budgetConfiguration,
      financialData: widget.data.financialData,
      onChanged: _saveFinancialData,
    );
  }

  Future<void> _saveFinancialData() => widget.repository.saveUserFinancialData(
    _budgetController.mergeInto(widget.data.financialData),
  );

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  void _selectDestination(int index) {
    if (index == _selectedIndex) {
      switch (index) {
        case 0:
          _budgetKey.currentState?.scrollToTop();
        case 1:
          _benefitsKey.currentState?.scrollToTop();
        case 2:
          _savingsKey.currentState?.scrollToTop();
      }
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _openNotifications() async {
    const service = NotificationCaptureService();

    if (!await service.hasAccess()) {
      await service.openSettings();
      return;
    }
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationImportScreen(
          controller: _budgetController,
          captureService: service,
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActionHistoryScreen(controller: _budgetController),
      ),
    );
  }

  void _openProfile() {
    final user = widget.data.financialData.user;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderScreen(
          title: 'Профиль',
          description: 'Настройки профиля будут добавлены позднее',
          icon: Icons.person_outline_rounded,
          child: QestoCard(
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: QestoColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: QestoColors.primary,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Основная валюта: ${user.defaultCurrency}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final financialData = data.financialData;
    return Scaffold(
      appBar: StickyAppHeader(
        title: _titles[_selectedIndex],
        user: financialData.user,
        onHistoryPressed: _openHistory,
        onNotificationsPressed: _openNotifications,
        onProfilePressed: _openProfile,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          BudgetScreen(key: _budgetKey, controller: _budgetController),
          BenefitsScreen(
            key: _benefitsKey,
            coupons: data.coupons,
            promotions: data.promotions,
            trackedProducts: financialData.trackedProducts,
          ),
          SavingsScreen(key: _savingsKey, goals: financialData.savingsGoals),
        ],
      ),
      bottomNavigationBar: QestoBottomNavigation(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectDestination,
      ),
    );
  }
}
