import 'dart:async';

import '../../budget/state/budget_controller.dart';
import '../config/bank_connector_registry.dart';
import '../data/browser_profile_manager.dart';
import '../domain/bank_browser_models.dart';
import '../domain/bank_sync_models.dart';
import '../runtime/browser_controller.dart';
import '../sber/sber_auth_manager.dart';
import '../sber/sber_connector.dart';
import '../sber/sber_connector_models.dart';
import 'bank_sync_config.dart';
import 'bank_sync_manager.dart';

class SberBackgroundSyncRunner
    implements
        CancellableBankBackgroundSyncRunner,
        RangedBankBackgroundSyncRunner {
  SberBackgroundSyncRunner({
    required this.profileManager,
    required this.budgetController,
    this.config = const BankSyncConfig(),
  });

  @override
  String get bankId => 'sber';

  final BrowserProfileManager profileManager;
  final BudgetController budgetController;
  final BankSyncConfig config;
  final Map<String, BrowserController> _activeBrowsers = {};

  @override
  Future<BankSyncRunResult> run(BankProfile profile) async {
    return runForRange(
      profile,
      SberSyncRange.sinceLastSync(profile.syncMetadata.lastHistorySyncThrough),
    );
  }

  @override
  Future<BankSyncRunResult> runForRange(
    BankProfile profile,
    SberSyncRange range,
  ) async {
    final startedAt = DateTime.now();
    final generation = budgetController.dataGeneration;
    final browser = BrowserController(
      profile: profile,
      bank: profile.bankId == bankId
          ? BankConnectorRegistry.sber
          : throw StateError('Unexpected bank profile'),
      profileManager: profileManager,
      onNotice: (_) {},
    );
    _activeBrowsers[profile.id] = browser;
    SberConnector? connector;
    try {
      await browser
          .open(presentationMode: BrowserPresentationMode.background)
          .timeout(config.browserStartupTimeout);
      if (!browser.isRuntimeReady) {
        return const BankSyncRunResult(
          result: BankSyncResult.bankUnavailable,
          failureReason: 'CEF_STARTUP_FAILED',
        );
      }
      try {
        await browser
            .waitForLoadState(BankBrowserLoadState.finished)
            .timeout(config.pageLoadTimeout);
      } on TimeoutException {
        // A SPA can already be usable despite a missing/late CEF load event.
        // The same bounded DOM readiness check as visible sync is authoritative.
      }
      if (browser.hasCertificateProblem) {
        return const BankSyncRunResult(
          result: BankSyncResult.bankUnavailable,
          failureReason: 'BANK_CERTIFICATE_ERROR',
        );
      }
      connector = SberConnector(
        browser: browser,
        // Same bounded quick-login flow as a manual sync. A missing/rejected
        // PIN or full-login challenge returns authRequired and stops retries.
        authManager: const SberAuthManager(),
      );
      final report = await connector
          .sync(range: range)
          .timeout(config.syncScenarioTimeout);
      if (report.state == SberConnectorState.pinRequired ||
          report.state == SberConnectorState.fullLoginRequired) {
        return const BankSyncRunResult(
          result: BankSyncResult.authRequired,
          failureReason: 'USER_AUTHENTICATION_REQUIRED',
        );
      }
      if (report.state == SberConnectorState.error) {
        return BankSyncRunResult(
          result: BankSyncResult.bankUnavailable,
          failureReason: report.failureCode ?? 'SBER_CONNECTOR_ERROR',
        );
      }
      final snapshot = report.snapshot;
      if (snapshot == null ||
          (snapshot.accounts.isEmpty && snapshot.transactions.isEmpty) ||
          (snapshot.historyRowsSeen > 0 &&
              snapshot.transactions.isEmpty &&
              !snapshot.hasVerifiedEmptyHistory)) {
        return const BankSyncRunResult(
          result: BankSyncResult.parserError,
          failureReason: 'EMPTY_OR_INVALID_BANK_SNAPSHOT',
        );
      }
      final imported = await budgetController.importSberSnapshot(
        snapshot,
        expectedGeneration: generation,
      );
      final newest = snapshot.transactions.isEmpty
          ? null
          : snapshot.transactions
                .map((item) => item.date)
                .reduce((left, right) => left.isAfter(right) ? left : right);
      return BankSyncRunResult(
        result:
            report.state == SberConnectorState.syncPartial ||
                imported.unresolvedCount > 0 ||
                imported.unassignedAccountCount > 0
            ? BankSyncResult.partial
            : BankSyncResult.success,
        failureReason: report.importFailureReason(imported),
        importedCount: imported.newCount,
        updatedCount: imported.updatedCount + imported.accountsUpdated,
        deduplicatedCount: imported.unchangedCount,
        lastImportedTransactionAt: newest,
        historySyncedThrough: range.verifiedThrough(startedAt),
      );
    } on TimeoutException {
      return const BankSyncRunResult(
        result: BankSyncResult.timeout,
        failureReason: 'SBER_SYNC_SCENARIO_TIMEOUT',
      );
    } finally {
      try {
        await connector?.dispose();
        // Give CEF a bounded moment to flush its persistent RequestContext.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await browser.disposeEnvironment();
      } finally {
        _activeBrowsers.remove(profile.id);
        browser.dispose();
      }
    }
  }

  @override
  Future<void> cancel(String profileId) async {
    final browser = _activeBrowsers.remove(profileId);
    if (browser == null) return;
    await browser.disposeEnvironment();
    browser.dispose();
  }
}
