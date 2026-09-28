import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters/qesto_formatters.dart';
import '../core/platform/qesto_command_line.dart';
import '../core/theme/qesto_theme.dart';
import '../data/models/qesto_models.dart';
import '../features/budget/add_expense_screen.dart';
import '../features/budget/state/budget_controller.dart';
import '../features/history/action_history_screen.dart';
import '../features/bank_screenshot_import/presentation/bank_screenshot_import_screen.dart';
import '../features/bank_browser/data/browser_profile_manager.dart';
import '../features/bank_browser/sync/bank_sync_scheduler.dart';
import '../features/notification_import/presentation/notification_import_screen.dart';
import '../features/receipt_import/presentation/receipt_import_screen.dart';
import '../features/statement_import/data/bank_statement_file_models.dart';
import '../features/statement_import/presentation/statement_import_screen.dart';
import '../features/statistics/domain/models/statistics_models.dart';
import '../features/statistics/presentation/state/statistics_controller.dart';
import '../features/voice_input/data/voice_capture_service.dart';
import '../features/voice_input/domain/voice_transaction_draft_parser.dart';
import '../features/voice_transaction/data/voice_speech_recognizer.dart';
import '../features/voice_transaction/presentation/voice_transaction_confirmation_sheet.dart';
import '../features/voice_transaction/services/voice_transaction_parser.dart';
import 'desktop_destination.dart';
import 'desktop_financial_helpers.dart';
import 'pages/desktop_accounts_page.dart';
import 'pages/desktop_budget_page.dart';
import 'pages/desktop_bank_connections_page.dart';
import 'pages/desktop_cash_flow_page.dart';
import 'pages/desktop_dashboard_page.dart';
import 'pages/desktop_debts_page.dart';
import 'pages/desktop_investments_page.dart';
import 'pages/desktop_recurring_page.dart';
import 'pages/desktop_statistics_page.dart';
import 'pages/desktop_support_pages.dart';
import 'pages/desktop_transactions_page.dart';
import 'widgets/desktop_chrome.dart';
import 'widgets/desktop_components.dart';
import 'widgets/transaction_attention_panel.dart';

class DesktopAppShell extends StatefulWidget {
  const DesktopAppShell({
    required this.data,
    required this.controller,
    required this.onAllDataDeleted,
    required this.browserProfileManager,
    required this.bankSyncScheduler,
    this.bankConnectionsAvailable = true,
    this.onOpenNotificationInbox,
    super.key,
  });

  final QestoAppData data;
  final BudgetController controller;
  final Future<void> Function() onAllDataDeleted;
  final BrowserProfileManager browserProfileManager;
  final BankSyncScheduler bankSyncScheduler;
  final bool bankConnectionsAvailable;
  final Future<void> Function()? onOpenNotificationInbox;

  @override
  State<DesktopAppShell> createState() => _DesktopAppShellState();
}

class _DesktopAppShellState extends State<DesktopAppShell> {
  late final StatisticsController _statistics;
  late var _destination =
      (hasQestoCommandLineArgument('--qesto-bank-browser-smoke') ||
          hasQestoCommandLineArgument('--qesto-bank-browser-dev'))
      ? DesktopDestination.connections
      : DesktopDestination.dashboard;
  var _sidebarCollapsed = false;
  String? _dashboardPeriodId;
  String? _requestedTransactionId;
  var _transactionRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    _statistics = StatisticsController(budgetController: widget.controller);
  }

  @override
  void dispose() {
    _statistics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openGlobalSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openGlobalSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _openAddData,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _openAddData,
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            _select(DesktopDestination.settings),
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
            _select(DesktopDestination.settings),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return _mobileShell();
            }
            final forcedCollapsed = constraints.maxWidth < 1120;
            final collapsed = forcedCollapsed || _sidebarCollapsed;
            return Scaffold(
              backgroundColor: context.qestoVisual.workspace,
              body: Row(
                children: [
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) => Theme(
                      data: Theme.of(context),
                      child: DesktopSidebar(
                        selected: _destination,
                        collapsed: collapsed,
                        user: widget.controller.user,
                        bankConnectionsAvailable:
                            widget.bankConnectionsAvailable,
                        onSelected: _select,
                        onToggle: forcedCollapsed
                            ? () {}
                            : () => setState(
                                () => _sidebarCollapsed = !_sidebarCollapsed,
                              ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        ListenableBuilder(
                          listenable: _statistics,
                          builder: (context, _) => DesktopTopBar(
                            title: _destination == DesktopDestination.dashboard
                                ? _destination.label
                                : _destination.section == null
                                ? _destination.label
                                : '${_destination.section!.label} · ${_destination.label}',
                            period: _periodLabel,
                            compactSearch:
                                _destination == DesktopDestination.dashboard,
                            onPeriodPressed:
                                _destination == DesktopDestination.dashboard
                                ? _chooseDashboardPeriod
                                : null,
                            onSearch: _openGlobalSearch,
                            onAdd: _openAddData,
                            onNotifications: _openNotifications,
                            notificationCount: attentionTransactions(
                              _statistics,
                            ).length,
                          ),
                        ),
                        Expanded(
                          child: Theme(
                            data: Theme.of(context),
                            child: Material(
                              color: context.qestoColors.background,
                              child: _pageFor(_destination),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _mobileShell() {
    final section = _destination.section;
    final selectedIndex = section == null ? 0 : section.index + 1;
    final destinations = DesktopDestination.values
        .where((item) => section != null && item.section == section)
        .toList();
    return Scaffold(
      key: const Key('mobile-app-shell'),
      appBar: AppBar(
        title: Text(_destination.label, style: const TextStyle(fontSize: 19)),
        actions: [
          IconButton(
            tooltip: 'Поиск',
            onPressed: _openGlobalSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          ListenableBuilder(
            listenable: _statistics,
            builder: (context, _) => Badge(
              isLabelVisible: attentionTransactions(_statistics).isNotEmpty,
              label: Text(
                _badgeLabel(attentionTransactions(_statistics).length),
              ),
              child: IconButton(
                tooltip: 'Уведомления',
                onPressed: _openNotifications,
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ),
          ),
          IconButton(
            key: const Key('mobile-add-data'),
            tooltip: 'Добавить данные',
            onPressed: _openAddData,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => ListTile(
                  title: Text(widget.controller.user.name),
                  subtitle: Text(widget.controller.user.defaultCurrency),
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _select(DesktopDestination.settings);
                  },
                ),
              ),
              const Divider(),
              for (final item in [
                DesktopDestination.dashboard,
                DesktopDestination.insights,
                ...DesktopDestination.values.where(
                  (item) => item.section != null,
                ),
                DesktopDestination.settings,
              ])
                ListTile(
                  key: Key('mobile-destination-${item.name}'),
                  leading: Icon(item.icon),
                  title: Text(item.label),
                  subtitle: item.section == null
                      ? null
                      : Text(item.section!.label),
                  selected: _destination == item,
                  onTap: () {
                    Navigator.pop(context);
                    _select(item);
                  },
                ),
              ListTile(
                key: const Key('action-history-button'),
                leading: const Icon(Icons.history),
                title: const Text('История действий'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          ActionHistoryScreen(controller: widget.controller),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_destination == DesktopDestination.dashboard)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton.icon(
                    onPressed: _chooseDashboardPeriod,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(_periodLabel ?? 'Период'),
                  ),
                ),
              ),
            if (destinations.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    for (final item in destinations)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('mobile-tab-${item.name}'),
                          label: Text(item.label),
                          selected: _destination == item,
                          onSelected: (_) => _select(item),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: Theme(
                data: Theme.of(context),
                child: Material(
                  color: context.qestoColors.background,
                  child: _pageFor(_destination),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => _select(
          index == 0
              ? DesktopDestination.dashboard
              : DesktopProductSection.values[index - 1].landing,
        ),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            label: 'Обзор',
          ),
          for (final item in DesktopProductSection.values)
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }

  BudgetPeriod get _dashboardPeriod {
    if (_dashboardPeriodId case final selectedId?) {
      return widget.controller.periods.firstWhere(
        (item) => item.id == selectedId,
        orElse: () => widget.controller.periods.last,
      );
    }

    final active = widget.controller.periods.firstWhere(
      (item) => item.contains(widget.controller.referenceDate),
      orElse: () => widget.controller.periods.last,
    );
    if (widget.controller.transactionsFor(active).isNotEmpty ||
        widget.controller.transactions.isEmpty) {
      return active;
    }

    // On the first days of a month a 30-day bank sync mostly contains the
    // previous month. Do not present an empty Overview while those canonical
    // operations are already visible in the Transactions table.
    final newestTransaction = widget.controller.transactions.reduce(
      (left, right) => left.date.isAfter(right.date) ? left : right,
    );
    return widget.controller.periods.firstWhere(
      (item) => item.contains(newestTransaction.date),
      orElse: () => active,
    );
  }

  String? get _periodLabel => switch (_destination) {
    DesktopDestination.dashboard => capitalize(
      formatBudgetPeriod(
        _dashboardPeriod.month,
        _dashboardPeriod.year,
        includeYear: true,
      ),
    ),
    DesktopDestination.budget || DesktopDestination.cashFlow => capitalize(
      formatBudgetPeriod(
        widget.controller.referenceDate.month,
        widget.controller.referenceDate.year,
        includeYear: true,
      ),
    ),
    _ => null,
  };

  Widget _pageFor(DesktopDestination destination) => switch (destination) {
    DesktopDestination.dashboard => DesktopDashboardPage(
      controller: widget.controller,
      period: _dashboardPeriod,
      onOpenTransactions: () => _select(DesktopDestination.transactions),
      onOpenBudget: () => _select(DesktopDestination.budget),
      onOpenRecurring: () => _select(DesktopDestination.recurring),
      onOpenTransaction: _openTransaction,
    ),
    DesktopDestination.expenses => DesktopBudgetAnalysisPage(
      controller: widget.controller,
      section: StatisticsSection.expenses,
      statisticsController: _statistics,
    ),
    DesktopDestination.transactions => DesktopTransactionsPage(
      controller: widget.controller,
      requestedTransactionId: _requestedTransactionId,
      requestSerial: _transactionRequestSerial,
    ),
    DesktopDestination.budget => DesktopBudgetPage(
      controller: widget.controller,
    ),
    DesktopDestination.cashFlow => DesktopCashFlowPage(
      controller: widget.controller,
    ),
    DesktopDestination.rhythm => DesktopBudgetAnalysisPage(
      controller: widget.controller,
      section: StatisticsSection.rhythm,
      statisticsController: _statistics,
    ),
    DesktopDestination.merchants => DesktopBudgetAnalysisPage(
      controller: widget.controller,
      section: StatisticsSection.merchants,
      statisticsController: _statistics,
    ),
    DesktopDestination.categories => DesktopBudgetAnalysisPage(
      controller: widget.controller,
      section: StatisticsSection.categories,
      statisticsController: _statistics,
    ),
    DesktopDestination.accounts => DesktopAccountsPage(
      controller: widget.controller,
    ),
    DesktopDestination.recurring => DesktopRecurringPage(
      controller: widget.controller,
    ),
    DesktopDestination.liquidity => DesktopAccountsPage(
      controller: widget.controller,
    ),
    DesktopDestination.investments => DesktopInvestmentsPage(
      controller: widget.controller,
    ),
    DesktopDestination.debts => DesktopDebtsPage(controller: widget.controller),
    DesktopDestination.goals => DesktopGoalsPage(controller: widget.controller),
    DesktopDestination.insights => DesktopInsightsPage(
      controller: widget.controller,
    ),
    DesktopDestination.connections => DesktopBankConnectionsPage(
      controller: widget.controller,
      profileManager: widget.browserProfileManager,
      bankSyncScheduler: widget.bankSyncScheduler,
    ),
    DesktopDestination.benefits => DesktopBenefitsPage(
      coupons: widget.data.coupons,
      promotions: widget.data.promotions,
      trackedProducts: widget.data.financialData.trackedProducts,
    ),
    DesktopDestination.settings => DesktopSettingsPage(
      controller: widget.controller,
    ),
  };

  void _select(DesktopDestination destination) {
    if (destination == DesktopDestination.connections &&
        !widget.bankConnectionsAvailable) {
      return;
    }
    setState(() {
      _destination = destination;
      if (destination != DesktopDestination.transactions) {
        _requestedTransactionId = null;
      }
    });
  }

  void _openTransaction(String id) {
    setState(() {
      _destination = DesktopDestination.transactions;
      _requestedTransactionId = id;
      _transactionRequestSerial++;
    });
  }

  Future<void> _chooseDashboardPeriod() async {
    final selected = await showDialog<BudgetPeriod>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) => SimpleDialog(
        title: const Text('Период обзора'),
        children: [
          for (final period
              in widget.controller.periods.toList(growable: false).reversed)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(period),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: period.id == _dashboardPeriod.id
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: context.qestoColors.primary,
                          )
                        : null,
                  ),
                  Text(
                    capitalize(
                      formatBudgetPeriod(
                        period.month,
                        period.year,
                        includeYear: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _dashboardPeriodId = selected.id);
  }

  Future<void> _openGlobalSearch() async {
    final result = await showDialog<_SearchResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) => _GlobalSearchDialog(
        controller: widget.controller,
        bankConnectionsAvailable: widget.bankConnectionsAvailable,
      ),
    );
    if (result == null || !mounted) return;
    if (result.transactionId != null) {
      _openTransaction(result.transactionId!);
    } else if (result.destination != null) {
      _select(result.destination!);
    }
  }

  Future<void> _openAddData() async {
    final action = await showDialog<_AddDataAction>(
      context: context,
      builder: (context) =>
          _AddDataDialog(includeInbox: !widget.bankConnectionsAvailable),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _AddDataAction.manual:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => AddExpenseScreen(
              controller: widget.controller,
              period: widget.controller.periodForOrCreate(
                widget.controller.referenceDate,
              ),
            ),
          ),
        );
      case _AddDataAction.voice:
        await _openVoiceInput();
      case _AddDataAction.receipt:
        final message = await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(
            builder: (_) => ReceiptImportScreen(controller: widget.controller),
          ),
        );
        if (message != null) _showMessage(message);
      case _AddDataAction.screenshot:
        final message = await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(
            builder: (_) =>
                BankScreenshotImportScreen(controller: widget.controller),
          ),
        );
        if (message != null && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      case _AddDataAction.statement:
        final count = await Navigator.of(context).push<int>(
          MaterialPageRoute<int>(
            builder: (_) => StatementImportScreen(
              controller: widget.controller,
              pickerMode: StatementPickerMode.statement,
            ),
          ),
        );
        if (count != null) _showMessage('Добавлено операций: $count');
      case _AddDataAction.excel:
        final count = await Navigator.of(context).push<int>(
          MaterialPageRoute<int>(
            builder: (_) => StatementImportScreen(
              controller: widget.controller,
              pickerMode: StatementPickerMode.excel,
            ),
          ),
        );
        if (count != null) _showMessage('Добавлено операций: $count');
      case _AddDataAction.account:
        _select(DesktopDestination.liquidity);
      case _AddDataAction.inbox:
        await _openNotifications();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openVoiceInput() async {
    const androidRecognizer = AndroidVoiceSpeechRecognizer();
    if (androidRecognizer.isSupported) {
      try {
        final recognition = await androidRecognizer.recognize();
        if (recognition == null || !mounted) return;
        final draft = const VoiceTransactionParser().parse(
          text: recognition.text,
          categories: widget.controller.categories,
          accounts: widget.controller.accounts,
        );
        final added = await showVoiceTransactionConfirmation(
          context: context,
          controller: widget.controller,
          period: widget.controller.periodForOrCreate(
            widget.controller.referenceDate,
          ),
          draft: draft,
          recognizedOnDevice: recognition.onDevice,
        );
        if (added == true && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Операция добавлена')));
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error is VoiceSpeechException
                    ? error.message
                    : 'Не удалось распознать речь. Попробуйте ещё раз.',
              ),
            ),
          );
        }
      }
      return;
    }
    final result = await showDialog<_VoiceDraft>(
      context: context,
      builder: (context) => _VoiceInputDialog(controller: widget.controller),
    );
    if (result == null || !mounted) return;
    final candidateId = await widget.controller.addVoiceCandidate(
      transcript: result.transcript,
      amountMinor: result.amount * 100,
      currency: widget.controller.user.defaultCurrency,
      accountId: result.accountId,
      occurredAt: widget.controller.referenceDate,
      merchant: result.merchant,
      categoryId: result.categoryId,
      confidence: 0.72,
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтвердить распознавание?'),
        content: Text(
          '${result.merchant}\n${formatMoney(-result.amount, widget.controller.user.defaultCurrency)}\n${result.transcript}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.confirmVoiceCandidate(candidateId);
    }
  }

  Future<void> _openNotifications() async {
    await showQestoNotificationCenter(
      context,
      _statistics,
      onOpenInbox: _openNotificationInbox,
    );
  }

  Future<void> _openNotificationInbox() async {
    if (MediaQuery.sizeOf(context).width < 900 &&
        widget.onOpenNotificationInbox != null) {
      await widget.onOpenNotificationInbox!();
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NotificationImportScreen(
          controller: widget.controller,
          captureAvailable: false,
          onAllDataDeleted: widget.onAllDataDeleted,
        ),
      ),
    );
  }
}

String _badgeLabel(int count) => count > 99 ? '99+' : '$count';

enum _AddDataAction {
  inbox,
  manual,
  voice,
  receipt,
  screenshot,
  statement,
  excel,
  account,
}

class _AddDataDialog extends StatelessWidget {
  const _AddDataDialog({this.includeInbox = false});
  final bool includeInbox;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Добавить данные'),
    content: SizedBox(
      width: 470,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (includeInbox)
            const _AddDataTile(
              action: _AddDataAction.inbox,
              icon: Icons.sms_outlined,
              title: 'Уведомления и SMS',
              subtitle: 'Доступ к уведомлениям, вставка текста и проверка',
            ),
          _AddDataTile(
            action: _AddDataAction.manual,
            icon: Icons.edit_outlined,
            title: 'Расход вручную',
            subtitle: 'Сумма, категория, счёт и дата',
          ),
          _AddDataTile(
            action: _AddDataAction.voice,
            icon: Icons.mic_none_rounded,
            title: 'Голосом',
            subtitle: 'Распознать речь и проверить операцию',
          ),
          _AddDataTile(
            action: _AddDataAction.receipt,
            icon: Icons.receipt_long_outlined,
            title: 'Чек',
            subtitle: 'Изображение или QR',
          ),
          _AddDataTile(
            action: _AddDataAction.screenshot,
            icon: Icons.screenshot_monitor_outlined,
            title: 'Скриншоты банка',
            subtitle: 'OCR и проверка операций перед импортом',
          ),
          _AddDataTile(
            action: _AddDataAction.statement,
            icon: Icons.picture_as_pdf_outlined,
            title: 'Выписку',
            subtitle: 'PDF Сбербанка с просмотром перед импортом',
          ),
          _AddDataTile(
            action: _AddDataAction.excel,
            icon: Icons.table_view_rounded,
            title: 'Excel-таблицу',
            subtitle: 'XLSX или XLSM через универсальный адаптер',
          ),
          _AddDataTile(
            action: _AddDataAction.account,
            icon: Icons.account_balance_wallet_outlined,
            title: 'Счёт / актив / долг',
            subtitle: 'Добавить объект финансового состояния',
          ),
        ],
      ),
    ),
  );
}

class _AddDataTile extends StatelessWidget {
  const _AddDataTile({
    required this.action,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final _AddDataAction action;
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => ListTile(
    key: Key('add-data-${action.name}'),
    onTap: () => Navigator.pop(context, action),
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.qestoColors.primarySoft,
        borderRadius: QestoGeometry.control,
      ),
      child: Icon(icon, color: context.qestoColors.primary, size: 20),
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 10)),
    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
  );
}

class _VoiceDraft {
  const _VoiceDraft({
    required this.transcript,
    required this.amount,
    required this.merchant,
    required this.accountId,
    required this.categoryId,
  });
  final String transcript;
  final int amount;
  final String merchant;
  final String accountId;
  final String? categoryId;
}

class _VoiceInputDialog extends StatefulWidget {
  const _VoiceInputDialog({required this.controller});
  final BudgetController controller;
  @override
  State<_VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends State<_VoiceInputDialog> {
  static const _capture = VoiceCaptureService();
  static const _parser = VoiceTransactionDraftParser();
  final transcript = TextEditingController();
  final amount = TextEditingController();
  final merchant = TextEditingController();
  late String accountId = widget.controller.accounts.first.id;
  String? categoryId;
  var listening = false;
  String? voiceStatus;
  @override
  void dispose() {
    transcript.dispose();
    amount.dispose();
    merchant.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (listening || !_capture.isSupported) return;
    setState(() {
      listening = true;
      voiceStatus = 'Слушаю микрофон…';
    });
    try {
      final result = await _capture.capture();
      if (!mounted) return;
      final parsed = _parser.parse(result.transcript);
      transcript.text = parsed.transcript;
      if (parsed.amountRubles != null) {
        amount.text = parsed.amountRubles.toString();
      }
      if (parsed.merchant?.isNotEmpty == true) {
        merchant.text = parsed.merchant!;
      }
      setState(() {
        listening = false;
        categoryId = parsed.categoryId ?? categoryId;
        voiceStatus = 'Распознано Windows Speech · ${result.locale}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      setState(() {
        listening = false;
        voiceStatus = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Добавить голосом'),
    scrollable: true,
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: transcript,
            autofocus: !_capture.isSupported,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Расшифровка',
              hintText: 'Кофе 350 рублей в Surf Coffee',
              suffixIcon: _capture.isSupported
                  ? IconButton(
                      key: const Key('capture-voice-input'),
                      tooltip: 'Записать с микрофона',
                      onPressed: listening ? null : _listen,
                      icon: Icon(
                        listening ? Icons.hearing_rounded : Icons.mic_rounded,
                      ),
                    )
                  : null,
            ),
          ),
          if (voiceStatus != null) ...[
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                voiceStatus!,
                style: TextStyle(
                  color: voiceStatus!.startsWith('Распознано')
                      ? context.qestoColors.positive
                      : context.qestoColors.secondaryText,
                  fontSize: 10,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Сумма'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: merchant,
                  decoration: const InputDecoration(labelText: 'Merchant'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Счёт'),
            items: widget.controller.accounts
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.title)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => accountId = value);
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: categoryId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Предложенная категория',
            ),
            items: widget.controller.categories
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                )
                .toList(),
            onChanged: (value) => setState(() => categoryId = value),
          ),
          const SizedBox(height: 9),
          Text(
            'Операция сначала сохранится как Synoball candidate и не попадёт в расходы до подтверждения.',
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          final parsed = int.tryParse(amount.text);
          if (parsed == null ||
              parsed <= 0 ||
              merchant.text.trim().isEmpty ||
              transcript.text.trim().isEmpty) {
            return;
          }
          Navigator.pop(
            context,
            _VoiceDraft(
              transcript: transcript.text.trim(),
              amount: parsed,
              merchant: merchant.text.trim(),
              accountId: accountId,
              categoryId: categoryId,
            ),
          );
        },
        child: const Text('Распознать'),
      ),
    ],
  );
}

class _SearchResult {
  const _SearchResult({this.transactionId, this.destination});
  final String? transactionId;
  final DesktopDestination? destination;
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog({
    required this.controller,
    required this.bankConnectionsAvailable,
  });
  final BudgetController controller;
  final bool bankConnectionsAvailable;
  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final query = TextEditingController();
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = query.text.trim().toLowerCase();
    final transactions = widget.controller.transactions
        .where(
          (item) => [
            desktopTransactionTitle(item),
            desktopCategoryName(widget.controller, item),
            desktopAccountName(widget.controller, item),
          ].join(' ').toLowerCase().contains(value),
        )
        .take(6)
        .toList();
    final destinations = DesktopDestination.values
        .where(
          (item) =>
              widget.bankConnectionsAvailable ||
              item != DesktopDestination.connections,
        )
        .where((item) => item.label.toLowerCase().contains(value))
        .take(4)
        .toList();
    return Dialog(
      alignment: const Alignment(0, -0.55),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 620,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Транзакции, счета, категории, разделы…',
                  suffixIcon: Padding(
                    padding: EdgeInsets.all(10),
                    child: DesktopPill(
                      label: 'Esc',
                      color: context.qestoColors.secondaryText,
                      background: context.qestoColors.surfaceSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: value.isEmpty
                  ? const DesktopEmptyState(
                      title: 'Быстрый поиск',
                      message:
                          'Начните вводить merchant, категорию, счёт или название раздела.',
                      icon: Icons.search_rounded,
                    )
                  : ListView(
                      padding: const EdgeInsets.all(10),
                      children: [
                        if (transactions.isNotEmpty)
                          const _SearchGroupLabel('ТРАНЗАКЦИИ'),
                        for (final item in transactions)
                          ListTile(
                            onTap: () => Navigator.pop(
                              context,
                              _SearchResult(transactionId: item.id),
                            ),
                            leading: const Icon(
                              Icons.receipt_long_outlined,
                              size: 19,
                            ),
                            title: Text(
                              desktopTransactionTitle(item),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${desktopCategoryName(widget.controller, item)} · ${desktopAccountName(widget.controller, item)}',
                              style: const TextStyle(fontSize: 10),
                            ),
                            trailing: Text(
                              formatMoney(
                                desktopSignedAmount(item),
                                item.currency,
                                showSign: true,
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (destinations.isNotEmpty)
                          const _SearchGroupLabel('РАЗДЕЛЫ'),
                        for (final item in destinations)
                          ListTile(
                            onTap: () => Navigator.pop(
                              context,
                              _SearchResult(destination: item),
                            ),
                            leading: Icon(item.icon, size: 19),
                            title: Text(
                              item.label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 17,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchGroupLabel extends StatelessWidget {
  const _SearchGroupLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
    child: Text(
      label,
      style: TextStyle(
        color: context.qestoColors.secondaryText,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );
}
