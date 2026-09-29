import '../../../mocks/fixtures/budget_categories.dart';
import '../../../data/models/qesto_models.dart';
import '../../../synoball/core/models.dart';
import '../../../synoball/adapters/qesto_legacy_bridge.dart';
import '../../budget/state/budget_controller.dart';
import '../../budget/services/cash_flow_calculation_service.dart';
import '../domain/ai_export_models.dart';
import '../../../synoball/analytics/canonical_snapshot.dart';
import '../../../synoball/analytics/qesto_read_model.dart';

AiExportSnapshot captureAiExportSnapshot(
  BudgetController controller, {
  DateTime? now,
}) {
  // No await: import commits and UI mutations cannot interleave this capture.
  final state = controller.synoballState;
  final entityId = const QestoLegacyBridge().entityIdFor(controller.user.id);
  final displayed = {for (final row in controller.transactions) row.id: row};
  final capturedAt = now ?? DateTime.now();
  final canonicalContext = const CanonicalSnapshotResolver().resolve(
    state,
    entityId,
    periodStart: DateTime(1),
    periodEnd: DateTime(9999),
  );
  final rows = <AiExportTransactionSnapshot>[];
  for (final canonical in state.transactions.where(
    (r) => r.entityId == entityId,
  )) {
    final app = displayed[canonical.id];
    final tags = {...canonical.tags, ...?app?.tags};
    AiExportExclusion? reason;
    if (canonical.status == CanonicalTransactionStatus.deleted) {
      reason = AiExportExclusion.deleted;
    } else if (canonical.status == CanonicalTransactionStatus.reversed ||
        tags.contains('status-cancelled') ||
        tags.contains('sber-status-cancelled')) {
      reason = AiExportExclusion.cancelled;
    } else if (canonical.status == CanonicalTransactionStatus.pending ||
        tags.contains('status-pending') ||
        tags.contains('sber-status-pending')) {
      reason = AiExportExclusion.pending;
    } else if (canonical.eventType != FinancialEventType.observed) {
      reason = AiExportExclusion.nonObserved;
    } else if (tags.contains('qesto-non-cash') ||
        tags.contains('sber-loyalty-only')) {
      reason = AiExportExclusion.nonMonetary;
    } else if (tags.contains('qesto-unconfirmed') ||
        app?.isConfirmed == false) {
      reason = AiExportExclusion.unconfirmed;
    } else if (app == null) {
      reason = AiExportExclusion.unavailable;
    }
    // Excluded rows retain only date/reason so raw descriptions never enter snapshot.
    rows.add(
      AiExportTransactionSnapshot(
        id: canonical.id,
        accountId: canonical.accountId.isEmpty ? null : canonical.accountId,
        categoryId: app?.categoryId?.isEmpty == true ? null : app?.categoryId,
        occurredAt: canonical.occurredAt,
        name: reason == null ? (app!.title ?? app.merchant ?? 'Операция') : '',
        amount: canonical.amount,
        type: app?.type ?? TransactionType.expense,
        direction: canonical.direction,
        cashFlowTreatment: app == null
            ? CashFlowTreatment.ignored
            : controller.cashFlowTreatment(app),
        exclusion: reason,
      ),
    );
  }
  final v2ReadModel = const QestoReadModelService().build(
    SynoballState(
      accounts: state.accounts,
      transactions: canonicalContext.transactions.values.toList(),
    ),
  );
  final v2App = {for (final t in v2ReadModel.transactions) t.id: t};
  final mergedIds = canonicalContext.aliases.entries
      .where((e) => e.key != e.value)
      .map((e) => e.value)
      .toSet();
  final v2Rows = <AiExportTransactionSnapshot>[];
  for (final row in rows) {
    final canonical = canonicalContext.transactions[row.id];
    if (canonical == null) {
      // Excluded lifecycle rows remain available to preview exclusion counts.
      if (canonicalContext.aliases[row.id] == null) v2Rows.add(row);
      continue;
    }
    final fact = canonicalContext.facts[row.id]!;
    final isResolvedGroup = mergedIds.contains(row.id);
    final app = isResolvedGroup ? v2App[row.id]! : displayed[row.id];
    if (app == null) continue;
    final original = v2App[fact.refundOriginalId];
    final category =
        fact.refundStatus == 'matched' &&
            fact.categorySource != 'user' &&
            original?.categoryId != null
        ? original!.categoryId
        : app.categoryId;
    v2Rows.add(
      AiExportTransactionSnapshot(
        id: row.id,
        accountId: canonical.accountId.isEmpty ? null : canonical.accountId,
        categoryId: category?.isEmpty == true ? null : category,
        occurredAt: canonical.occurredAt,
        name: app.title ?? app.merchant ?? 'Операция',
        amount: canonical.amount,
        type: app.type,
        direction: canonical.direction,
        cashFlowTreatment: controller.cashFlowTreatment(app),
        exclusion: row.exclusion,
      ),
    );
  }
  final accountDetails = <String, AiExportAccountDetails>{};
  for (final a in state.accounts.where((a) => a.entityId == entityId)) {
    final debts = controller.debts
        .where(
          (d) =>
              d.linkedAccountId == a.id &&
              d.userId == controller.user.id &&
              d.currency == a.currency &&
              !d.id.startsWith('legacy-debt-'),
        )
        .toList();
    final investments = controller.investmentAccounts
        .where(
          (i) =>
              i.linkedAccountId == a.id &&
              i.userId == controller.user.id &&
              i.currency == a.currency &&
              !i.id.startsWith('legacy-investment-'),
        )
        .toList();
    if (debts.length == 1) {
      final debt = debts.single;
      final balances =
          controller.debtBalanceSnapshots
              .where(
                (b) =>
                    b.debtId == debt.id &&
                    b.totalBalance * 100 == a.balance.minorUnits.abs(),
              )
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      accountDetails[a.id] = AiExportAccountDetails(
        capturedAt: balances.isEmpty ? null : balances.first.date,
        mortgage: debt.type == DebtType.mortgage,
        estimated: debt.dataQuality == DebtDataQuality.estimated,
        stale: debt.dataQuality == DebtDataQuality.stale,
        outstandingPrincipal: debt.currentPrincipal == null
            ? null
            : Money(
                minorUnits: debt.currentPrincipal! * 100,
                currency: debt.currency,
              ),
        nextPayment: debt.monthlyPayment == null
            ? null
            : Money(
                minorUnits: debt.monthlyPayment! * 100,
                currency: debt.currency,
              ),
        nextPaymentDate: debt.nextPaymentDate,
        interestRate: debt.interestRate,
      );
    } else if (investments.length == 1) {
      final investment = investments.single;
      accountDetails[a.id] = AiExportAccountDetails(
        capturedAt: investment.lastBalanceUpdateAt,
        estimated: investment.source == InvestmentDataSource.calculated,
      );
    }
  }
  return AiExportSnapshot(
    profileScope: entityId,
    capturedAt: capturedAt,
    referenceDate: controller.referenceDate,
    accounts: state.accounts
        .where((a) => a.entityId == entityId)
        .map(
          (a) => AiExportAccountSnapshot(
            id: a.id,
            name: a.name,
            type: a.type,
            isVirtual: a.isVirtual,
            balance: a.balance,
          ),
        ),
    transactions: rows,
    categoryNames: {for (final c in controller.categories) c.id: c.name},
    standardCategoryNames: {for (final c in budgetCategories) c.id: c.name},
    canonical: canonicalContext.metadataOnly(),
    v2Transactions: v2Rows,
    accountDetails: Map.unmodifiable(accountDetails),
  );
}
