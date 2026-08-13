import '../intelligence/financial_state.dart';

enum AiContextPurpose {
  purchaseDecision,
  budgetAnalysis,
  financialSummary,
  expenseOptimization,
  subscriptionAnalysis,
}

class AiFinancialContext {
  const AiFinancialContext({
    required this.purpose,
    required this.entityId,
    required this.generatedAt,
    required this.facts,
    required this.dataQuality,
    required this.warnings,
  });

  final AiContextPurpose purpose;
  final String entityId;
  final DateTime generatedAt;
  final Map<String, dynamic> facts;
  final double dataQuality;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
    'purpose': purpose.name,
    'entityId': entityId,
    'generatedAt': generatedAt.toIso8601String(),
    'facts': facts,
    'dataQuality': dataQuality,
    'warnings': warnings,
  };
}

class AiContextService {
  const AiContextService();

  AiFinancialContext build({
    required AiContextPurpose purpose,
    required FinancialState state,
    int? proposedPurchaseMinor,
  }) {
    final base = <String, dynamic>{
      'currency': state.liquidMoney.currency,
      'monthlyIncome': state.monthlyIncome.value,
      'monthlyExpenses': state.monthlyExpenses.value,
      'mandatoryExpenses': state.mandatoryExpenses.value,
      'freeCashflow': state.freeCashflow.value,
      'liquidAssets': state.liquidMoney.value,
      'expectedExpenses30d':
          state.upcomingEvents.fold<int>(
            0,
            (total, item) => total + item.amount.minorUnits,
          ) ~/
          100,
    };
    switch (purpose) {
      case AiContextPurpose.purchaseDecision:
        base['proposedPurchase'] = proposedPurchaseMinor == null
            ? null
            : (proposedPurchaseMinor / 100).toStringAsFixed(2);
        base['liquidAfterPurchase'] = proposedPurchaseMinor == null
            ? null
            : ((state.liquidMoney.minorUnits - proposedPurchaseMinor) / 100)
                  .toStringAsFixed(2);
      case AiContextPurpose.budgetAnalysis:
        base['plannedExpenses'] = state.plannedExpenses.value;
      case AiContextPurpose.financialSummary:
        base['assets'] = state.assets.value;
        base['debts'] = state.debts.value;
        base['investments'] = state.investments.value;
      case AiContextPurpose.expenseOptimization:
        base['recurringObligations'] = state.recurringObligations
            .map(
              (item) => {
                'title': item.title,
                'amount': item.typicalAmount.value,
                'confidence': item.confidence,
              },
            )
            .toList();
      case AiContextPurpose.subscriptionAnalysis:
        base['subscriptions'] = state.recurringObligations
            .map(
              (item) => {
                'title': item.title,
                'amount': item.typicalAmount.value,
                'nextExpectedAt': item.nextExpectedAt.toIso8601String(),
                'confidence': item.confidence,
              },
            )
            .toList();
    }
    return AiFinancialContext(
      purpose: purpose,
      entityId: state.entityId,
      generatedAt: DateTime.now(),
      facts: base,
      dataQuality: state.dataQuality.overall,
      warnings: state.dataQuality.warnings,
    );
  }
}
