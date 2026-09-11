import 'dart:async';

import '../domain/bank_browser_models.dart';
import '../runtime/browser_controller.dart';
import 'sber_auth_manager.dart';
import 'sber_account_history_mapper.dart';
import 'sber_connector_models.dart';
import 'sber_extractors.dart';
import 'sber_navigator.dart';
import 'sber_page_detector.dart';
import 'sber_readiness.dart';

class SberConnector extends Stream<SberSyncReport> {
  SberConnector({
    required this.browser,
    this.authManager = const SberAuthManager(),
    this.detector = const SberPageDetector(),
    this.extractors = const SberExtractors(),
    this.navigator = const SberNavigator(),
  });

  final BrowserController browser;
  final SberAuthManager authManager;
  final SberPageDetector detector;
  final SberExtractors extractors;
  final SberNavigator navigator;
  final _events = StreamController<SberSyncReport>.broadcast();
  var _running = false;

  bool get isRunning => _running;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<SberSyncReport> listen(
    void Function(SberSyncReport)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  Future<SberSyncReport> sync({SberSyncRange? range}) async {
    if (_running) {
      return const SberSyncReport(
        state: SberConnectorState.error,
        message: 'Синхронизация Сбера уже выполняется.',
      );
    }
    _running = true;
    try {
      _emit(const SberSyncReport(state: SberConnectorState.checkingAuth));
      final auth = await authManager.ensureAuthenticated(browser, detector);
      if (auth.state != SberConnectorState.authenticated) {
        _emit(auth);
        return auth;
      }

      final warnings = <String>[];
      final selectedRange = range ?? SberSyncRange.currentMonth();

      // Always begin with a complete dashboard observation. Sber lazy-loads
      // lower widgets, so walking away as soon as the first product or history
      // row appears loses data that renders roughly a second later.
      var pageType = await _currentPageType();
      if (pageType != SberPageType.dashboard) {
        final opened = await navigator.openDashboard(browser);
        if (opened) {
          await _waitForPage(browser);
          pageType = await _currentPageType();
        }
      }
      List<SberAccountFact> dashboardAccounts = const [];
      List<SberTransactionFact> dashboardTransactions = const [];
      if (pageType == SberPageType.dashboard) {
        await extractors.hydratePage(browser);
        dashboardAccounts = await _readAccountsWithRetry(browser);
        dashboardTransactions = await extractors.visibleTransactions(
          browser,
          range: selectedRange,
        );
      } else {
        warnings.add(
          'DASHBOARD_NAVIGATION_FAILED: главная страница не была распознана.',
        );
      }

      _emit(const SberSyncReport(state: SberConnectorState.syncingProducts));
      final accountsOpened = await navigator.openAccounts(browser);
      if (accountsOpened) {
        await _waitForPage(browser);
        pageType = await _currentPageType();
      }
      List<SberAccountFact> accounts = const [];
      if (pageType == SberPageType.accounts) {
        await extractors.hydratePage(browser);
        accounts = await _readAccountsWithRetry(browser);
      }
      if (accounts.isEmpty) {
        accounts = dashboardAccounts;
        if (dashboardAccounts.isNotEmpty) {
          warnings.add(
            'PRODUCTS_PARTIAL: использованы счета с главной страницы.',
          );
        }
      }
      accounts = extractors.mergeAccounts([...dashboardAccounts, ...accounts]);

      _emit(
        const SberSyncReport(state: SberConnectorState.syncingTransactions),
      );
      // The wallet route does not expose the full-history link. Return to the
      // already hydrated dashboard before opening operations; this preserves
      // the intentional dashboard -> accounts -> operations order.
      if (pageType != SberPageType.dashboard) {
        final dashboardReopened = await navigator.openDashboard(browser);
        if (dashboardReopened) {
          await _waitForPage(browser);
          pageType = await _currentPageType();
        }
      }
      final historyOpened = pageType == SberPageType.dashboard
          ? await navigator.openTransactions(browser)
          : false;
      if (historyOpened) {
        await _waitForPage(browser);
        pageType = await _currentPageType();
      }
      List<SberTransactionFact> transactions = const [];
      var historyExtraction = const SberTransactionExtraction();
      if (pageType == SberPageType.transactions) {
        historyExtraction = await extractors.transactions(
          browser,
          range: selectedRange,
        );
        transactions = historyExtraction.transactions;
      }
      if (transactions.isEmpty && dashboardTransactions.isNotEmpty) {
        transactions = dashboardTransactions;
        if (historyExtraction.rawRowsSeen > 0) {
          warnings.add(
            'HISTORY_NORMALIZATION_FAILED: в истории найдено '
            '${historyExtraction.rawRowsSeen} строк, но они не прошли нормализацию.',
          );
        }
        warnings.add(
          'TRANSACTIONS_PARTIAL: использован только список операций с главной.',
        );
      }
      if (historyExtraction.hasMoreRows &&
          !historyExtraction.rangeBoundaryReached) {
        warnings.add(
          'HISTORY_RANGE_PARTIAL: история остановилась до начала выбранного '
          'периода, на странице остались более старые операции.',
        );
      }
      if (historyExtraction.rejectedRows > 0) {
        warnings.add(
          'HISTORY_ROWS_REJECTED: не распознано '
          '${historyExtraction.rejectedRows} строк истории.',
        );
      }
      // The all-products history remains the completeness authority. Product
      // histories add exact ownership evidence; they never replace the global
      // list or manufacture a balance from cash flow.
      if (transactions.any((t) => t.accountId.isEmpty)) {
        final mapper = SberAccountHistoryMapper();
        final budget = Stopwatch()..start();
        for (final account in accounts) {
          if (budget.elapsed > const Duration(seconds: 90)) break;
          for (final resource in account.historyResources) {
            final opened = await navigator
                .openProductHistory(browser, resource, [
                  if (account.lastFour != null) account.lastFour!,
                  ...account.linkedCardLastFours,
                ]);
            if (!opened) continue;
            final scoped = await extractors.transactions(
              browser,
              range: selectedRange,
              maxScrolls: 40,
              maxDuration: Duration(
                seconds: (90 - budget.elapsed.inSeconds).clamp(1, 35),
              ),
            );
            final knownIds = {account.id, ...account.sourceAliases};
            mapper.observe(
              account.id,
              scoped.transactions.where((t) => knownIds.contains(t.accountId)),
            );
            if (budget.elapsed > const Duration(seconds: 90)) break;
          }
        }
        transactions = mapper.apply(transactions);
        if (mapper.conflicts > 0) {
          warnings.add(
            'ACCOUNT_MAPPING_CONFLICT: conflicting product histories',
          );
        }
      }
      final dates = transactions.map((item) => item.date).toList()..sort();
      final finalPage = await detector.inspect(browser);
      final finalReadiness = await const SberReadiness().probe(browser);
      if (finalReadiness == 'blocked') {
        warnings.add(
          'BANK_USER_ACTION_REQUIRED: банк запросил проверку безопасности. '
          'Откройте Сбер и пройдите её самостоятельно; автоматические действия остановлены.',
        );
      } else if (finalReadiness == 'auth') {
        warnings.add(
          'BANK_AUTH_REQUIRED: сессия банка закончилась, требуется вход.',
        );
      } else if (finalReadiness != 'ready') {
        warnings.add(
          'BANK_LOADING_TIMEOUT: банк не закончил загрузку за время ожидания. '
          'Полученные данные сохранены, история может быть неполной.',
        );
      }
      final snapshot = SberSyncSnapshot(
        connectionId: browser.profile.id,
        observedAt: DateTime.now(),
        accounts: accounts,
        transactions: transactions,
        oldestTransaction: dates.isEmpty ? null : dates.first,
        newestTransaction: dates.isEmpty ? null : dates.last,
        pendingCount: transactions
            .where((item) => item.status == 'PENDING')
            .length,
        pageType: finalPage == null
            ? SberPageType.unknown
            : detector.detect(finalPage),
        historyRowsSeen: historyExtraction.rawRowsSeen,
        historyRowsAccepted: historyExtraction.transactions.length,
        historyRowsRejected: historyExtraction.rejectedRows,
        historyScrollSteps: historyExtraction.scrollSteps,
        historyLoadMoreClicks: historyExtraction.loadMoreClicks,
        historyRewardRows: historyExtraction.rewardRows,
        historyServiceRows: historyExtraction.serviceRows,
        historyLoyaltyRewards: historyExtraction.loyaltyRewards,
        historyRangeBoundaryReached: historyExtraction.rangeBoundaryReached,
        historyHasMoreRows: historyExtraction.hasMoreRows,
        historyRowsOutsidePeriod: historyExtraction.outsidePeriodRows,
        historyDiagnostics: historyExtraction.diagnostics,
      );
      if (accounts.isEmpty) {
        warnings.add(
          'PRODUCTS_PARSER_MISMATCH: не удалось распознать счета и продукты.',
        );
      }
      if (transactions.isEmpty && !historyExtraction.hasVerifiedEmptyHistory) {
        warnings.add(
          'TRANSACTIONS_PARSER_MISMATCH: не удалось распознать историю операций.',
        );
      }
      final report = SberSyncReport(
        state: warnings.isEmpty
            ? SberConnectorState.syncComplete
            : SberConnectorState.syncPartial,
        snapshot: snapshot,
        message: warnings.isEmpty ? null : warnings.join(' '),
        failureCode: warnings.isEmpty
            ? null
            : warnings.map((warning) => warning.split(':').first).join(', '),
        pinAttempted: auth.pinAttempted,
      );
      _emit(report);
      return report;
    } on Object catch (error) {
      final report = SberSyncReport(
        state: SberConnectorState.error,
        message: 'Синхронизация Сбера остановлена: $error',
      );
      _emit(report);
      return report;
    } finally {
      _running = false;
    }
  }

  void _emit(SberSyncReport report) {
    if (!_events.isClosed) _events.add(report);
  }

  Future<void> _waitForPage(BrowserController browser) async {
    try {
      await browser
          .waitForLoadState(BankBrowserLoadState.finished)
          .timeout(const Duration(seconds: 12));
    } on Object {
      // A client-side route can finish before CEF emits a new load event. The
      // extractor still gets a bounded chance to read the rendered DOM.
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await const SberReadiness().wait(browser);
  }

  Future<SberPageType> _currentPageType() async {
    final page = await detector.inspect(browser);
    return page == null ? SberPageType.unknown : detector.detect(page);
  }

  Future<List<SberAccountFact>> _readAccountsWithRetry(
    BrowserController browser,
  ) async {
    if (!await const SberReadiness().wait(browser)) return const [];
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < const Duration(seconds: 30)) {
      final accounts = await extractors.accounts(browser);
      if (accounts.isNotEmpty) return accounts;
      final state = await const SberReadiness().probe(browser);
      if (state == 'auth' || state == 'blocked') break;
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    return const [];
  }

  Future<void> dispose() => _events.close();
}
