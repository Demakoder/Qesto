import 'package:flutter/material.dart';

import '../../data/models/qesto_models.dart';
import '../../desktop/desktop_destination.dart';
import '../../desktop/pages/desktop_statistics_page.dart';
import '../../desktop/pages/desktop_transactions_page.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/classification/category_manager_screen.dart';
import '../../features/history/action_history_screen.dart';
import '../../features/statistics/domain/models/statistics_models.dart';
import '../../features/trash/transaction_trash_screen.dart';
import '../navigation/mobile_root.dart';
import '../transactions/mobile_transaction_detail.dart';
import '../analytics/mobile_overview_page.dart';
import '../analytics/mobile_budget_page.dart';
import '../analytics/mobile_analysis_page.dart';
import '../analytics/mobile_upcoming_page.dart';
import '../capital/mobile_capital_pages.dart';
import '../capital/mobile_investment_pages.dart';
import '../capital/mobile_debt_pages.dart';
import '../capital/mobile_goal_pages.dart';

/// Wires mobile analytics and preserved pages to the single financial controller. The adapter owns
/// neither financial data nor persistence, and does not create budget periods.
class MobilePageAdapters {
  const MobilePageAdapters({
    required this.controller,
    required this.legacyPageBuilder,
  });

  final BudgetController controller;
  final Widget Function(DesktopDestination) legacyPageBuilder;

  Widget root({
    required MobileRoot destination,
    required BudgetPeriod overviewPeriod,
    required ValueChanged<DesktopDestination> onOpenDestination,
    required ValueChanged<String> onOpenTransaction,
    required ValueChanged<List<String>> onOpenFilteredTransactions,
  }) => switch (destination) {
    MobileRoot.dashboard => MobileOverviewPage(
      controller: controller,
      period: overviewPeriod,
      onOpenDestination: onOpenDestination,
      onOpenTransaction: onOpenTransaction,
      onOpenFilteredTransactions: onOpenFilteredTransactions,
    ),
    MobileRoot.transactions => transactions(
      onOpenTransaction: onOpenTransaction,
    ),
    MobileRoot.budget => MobileBudgetPage(
      controller: controller,
      onOpenFilteredTransactions: onOpenFilteredTransactions,
    ),
    MobileRoot.capital => MobileCapitalLanding(
      controller: controller,
      onOpenFilteredTransactions: onOpenFilteredTransactions,
    ),
  };

  Widget transactions({
    required ValueChanged<String> onOpenTransaction,
    List<String>? ids,
  }) => DesktopTransactionsPage(
    controller: controller,
    initialTransactionIds: ids,
    onOpenTransaction: onOpenTransaction,
  );

  Widget? transaction(String id) {
    final transaction = controller.transactions
        .where((item) => item.id == id)
        .firstOrNull;
    if (transaction == null) return null;
    return MobileTransactionDetail(controller: controller, transactionId: id);
  }

  Widget secondary(
    DesktopDestination destination, {
    ValueChanged<List<String>>? onOpenFilteredTransactions,
  }) {
    switch (destination) {
      case DesktopDestination.accounts:
        return MobileAccountsPage(
          controller: controller,
          onOpenFilteredTransactions: onOpenFilteredTransactions ?? (_) {},
        );
      case DesktopDestination.liquidity:
        return MobileLiquidityPage(controller: controller);
      case DesktopDestination.investments:
        return MobileInvestmentsPage(controller: controller);
      case DesktopDestination.debts:
        return MobileDebtsPage(controller: controller);
      case DesktopDestination.goals:
        return MobileGoalsPage(controller: controller);
      default:
        break;
    }
    if (destination == DesktopDestination.recurring) {
      // A mobile route, not a callback into hidden desktop selection.
      return MobileUpcomingPage(
        controller: controller,
        onOpenFilteredTransactions: onOpenFilteredTransactions ?? (_) {},
      );
    }
    // Each analytical route owns its existing *UI* StatisticsController.
    // Sharing the desktop instance would overwrite the section of retained
    // routes. BudgetController and all calculations remain shared/unchanged.
    final section = switch (destination) {
      DesktopDestination.expenses => StatisticsSection.expenses,
      DesktopDestination.rhythm => StatisticsSection.rhythm,
      DesktopDestination.cashFlow => StatisticsSection.cashFlow,
      DesktopDestination.merchants => StatisticsSection.merchants,
      DesktopDestination.categories => StatisticsSection.categories,
      _ => null,
    };
    if (section != null) {
      if (section == StatisticsSection.expenses ||
          section == StatisticsSection.cashFlow ||
          section == StatisticsSection.rhythm) {
        return MobileAnalysisPage(
          controller: controller,
          section: section,
          onOpenFilteredTransactions: onOpenFilteredTransactions ?? (_) {},
        );
      }
      return DesktopBudgetAnalysisPage(
        controller: controller,
        section: section,
      );
    }
    return legacyPageBuilder(destination);
  }

  Widget history() => ActionHistoryScreen(controller: controller);
  Widget trash() => TransactionTrashScreen(controller: controller);
  Widget categories() => CategoryManagerScreen(controller: controller);
}
