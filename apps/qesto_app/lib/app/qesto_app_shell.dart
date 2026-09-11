import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/platform/qesto_command_line.dart';

import '../data/models/qesto_models.dart';
import '../data/repositories/qesto_repository.dart';
import '../desktop/desktop_app_shell.dart';
import '../features/bank_browser/data/browser_profile_manager.dart';
import '../features/bank_browser/sync/bank_sync_config.dart';
import '../features/bank_browser/sync/bank_sync_manager.dart';
import '../features/bank_browser/sync/bank_sync_scheduler.dart';
import '../features/bank_browser/sync/sber_background_sync_runner.dart';

import '../features/budget/state/budget_controller.dart';

import '../features/notification_import/data/notification_capture_service.dart';
import '../features/notification_import/presentation/notification_import_screen.dart';
import '../features/notification_import/services/automatic_notification_importer.dart';

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
  late final BudgetController _budgetController;
  late final NotificationCaptureService _notificationCaptureService;
  late final AutomaticNotificationImporter _automaticNotificationImporter;
  late final BrowserProfileManager _browserProfileManager;
  late final BankSyncManager _bankSyncManager;
  late final BankSyncScheduler _bankSyncScheduler;
  StreamSubscription<void>? _notificationEvents;

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
    _browserProfileManager = BrowserProfileManager();
    const bankSyncConfig = BankSyncConfig();
    _bankSyncManager = BankSyncManager(
      profileManager: _browserProfileManager,
      config: bankSyncConfig,
      runners: [
        SberBackgroundSyncRunner(
          profileManager: _browserProfileManager,
          budgetController: _budgetController,
          config: bankSyncConfig,
        ),
      ],
    );
    _bankSyncScheduler = BankSyncScheduler(
      profileManager: _browserProfileManager,
      manager: _bankSyncManager,
      config: bankSyncConfig,
    );
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_drainNotificationInbox());
      if (_supportsBackgroundBankBrowser) {
        unawaited(_bankSyncScheduler.start());
      }
    });
  }

  bool get _supportsBackgroundBankBrowser =>
      !kIsWeb &&
      (kReleaseMode ||
          hasQestoCommandLineArgument('--qesto-bank-background-sync')) &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _drainNotificationInbox() async {
    await _automaticNotificationImporter.drain();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainNotificationInbox());
      if (_supportsBackgroundBankBrowser) {
        unawaited(_bankSyncScheduler.runDueNow());
      }
    }
  }

  Future<void> _saveFinancialData() => widget.repository.saveUserFinancialData(
    _budgetController.mergeInto(widget.data.financialData),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_notificationEvents?.cancel());
    _bankSyncScheduler.dispose();
    _bankSyncManager.dispose();
    _budgetController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) => DesktopAppShell(
    data: widget.data,
    controller: _budgetController,
    onAllDataDeleted: widget.onAllDataDeleted,
    browserProfileManager: _browserProfileManager,
    bankSyncScheduler: _bankSyncScheduler,
    bankConnectionsAvailable:
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux),
    onOpenNotificationInbox: _openNotifications,
  );
}
