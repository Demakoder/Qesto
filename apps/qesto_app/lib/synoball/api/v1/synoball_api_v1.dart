import '../../ai/context.dart';
import '../../analytics/read_models.dart';
import '../../core/models.dart';
import '../../core/synoball_core.dart';
import '../../intelligence/financial_state.dart';

class SynoballApiV1 {
  const SynoballApiV1({
    required this.core,
    this.financialStates = const FinancialStateService(),
    this.analytics = const SynoballAnalyticsReadService(),
    this.aiContexts = const AiContextService(),
  });

  final SynoballCore core;
  final FinancialStateService financialStates;
  final SynoballAnalyticsReadService analytics;
  final AiContextService aiContexts;

  List<SynoballEntity> entities() => core.state.entities;
  List<Institution> institutions() => core.state.institutions;
  List<SynoballConnection> connections({String? entityId}) => core
      .state
      .connections
      .where((item) => entityId == null || item.entityId == entityId)
      .toList(growable: false);
  List<SynoballConsent> consents({String? entityId}) => core.state.consents
      .where((item) => entityId == null || item.entityId == entityId)
      .toList(growable: false);
  List<SynoballAccount> accounts(String entityId) => core.state.accounts
      .where((item) => item.entityId == entityId)
      .toList(growable: false);
  List<CanonicalTransaction> transactions(String entityId) => core.transactions
      .where((item) => item.entityId == entityId)
      .toList(growable: false);
  List<RecurringStream> recurringStreams(String entityId) => core
      .state
      .recurringStreams
      .where((item) => item.entityId == entityId)
      .toList(growable: false);

  FinancialState financialState({
    required String entityId,
    required DateTime asOf,
    String currency = 'RUB',
    int plannedExpensesMinor = 0,
  }) => financialStates.calculate(
    state: core.state,
    entityId: entityId,
    asOf: asOf,
    currency: currency,
    plannedExpensesMinor: plannedExpensesMinor,
  );

  AiFinancialContext aiContext({
    required String entityId,
    required DateTime asOf,
    required AiContextPurpose purpose,
    String currency = 'RUB',
    int? proposedPurchaseMinor,
  }) => aiContexts.build(
    purpose: purpose,
    state: financialState(entityId: entityId, asOf: asOf, currency: currency),
    proposedPurchaseMinor: proposedPurchaseMinor,
  );
}
