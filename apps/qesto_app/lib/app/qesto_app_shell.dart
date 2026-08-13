import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/qesto_theme.dart';
import '../core/widgets/qesto_bottom_navigation.dart';
import '../core/widgets/qesto_card.dart';
import '../core/widgets/sticky_app_header.dart';
import '../data/models/qesto_models.dart';
import '../data/repositories/qesto_repository.dart';
import '../desktop/desktop_app_shell.dart';
import '../features/benefits/benefits_screen.dart';
import '../features/budget/budget_screen.dart';
import '../features/budget/state/budget_controller.dart';
import '../features/history/action_history_screen.dart';
import '../features/notification_import/data/notification_capture_service.dart';
import '../features/notification_import/presentation/notification_import_screen.dart';
import '../features/notification_import/services/automatic_notification_importer.dart';
import '../features/savings/savings_screen.dart';
import '../features/shared/placeholder_screen.dart';

class QestoAppShell extends StatefulWidget {
  const QestoAppShell({
    required this.data,
    required this.repository,
    required this.onAllDataDeleted,
    super.key,
  });

  final QestoAppData data;
  final QestoRepository repository;
  final Future<void> Function() onAllDataDeleted;

  @override
  State<QestoAppShell> createState() => _QestoAppShellState();
}

class _QestoAppShellState extends State<QestoAppShell>
    with WidgetsBindingObserver {
  final _budgetKey = GlobalKey<BudgetScreenState>();
  final _benefitsKey = GlobalKey<BenefitsScreenState>();
  final _savingsKey = GlobalKey<SavingsScreenState>();
  var _selectedIndex = 0;
  late final BudgetController _budgetController;
  late final NotificationCaptureService _notificationCaptureService;
  late final AutomaticNotificationImporter _automaticNotificationImporter;
  StreamSubscription<void>? _notificationEvents;

  static const _titles = ['Бюджет', 'Выгода', 'Накопления'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _budgetController = BudgetController(
      configuration: widget.data.budgetConfiguration,
      financialData: widget.data.financialData,
      onChanged: _saveFinancialData,
    );
    _notificationCaptureService = const NotificationCaptureService();
    _automaticNotificationImporter = AutomaticNotificationImporter(
      controller: _budgetController,
      captureService: _notificationCaptureService,
    );
    _notificationEvents = _notificationCaptureService.notificationEvents.listen(
      (_) => unawaited(_drainNotificationInbox()),
      onError: (_) {
        // Native notification events do not exist on desktop/web.
      },
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_drainNotificationInbox()),
    );
  }

  Future<void> _drainNotificationInbox() async {
    await _automaticNotificationImporter.drain();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainNotificationInbox());
    }
  }

  Future<void> _saveFinancialData() => widget.repository.saveUserFinancialData(
    _budgetController.mergeInto(widget.data.financialData),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_notificationEvents?.cancel());
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
    var captureAvailable = false;
    try {
      captureAvailable = await _notificationCaptureService.hasAccess();
    } on Object {
      captureAvailable = false;
    }
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationImportScreen(
          controller: _budgetController,
          captureService: _notificationCaptureService,
          captureAvailable: captureAvailable,
          onAllDataDeleted: widget.onAllDataDeleted,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return DesktopAppShell(
            data: data,
            controller: _budgetController,
            onAllDataDeleted: widget.onAllDataDeleted,
          );
        }
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
              SavingsScreen(
                key: _savingsKey,
                goals: financialData.savingsGoals,
              ),
            ],
          ),
          bottomNavigationBar: QestoBottomNavigation(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectDestination,
          ),
        );
      },
    );
  }
}
