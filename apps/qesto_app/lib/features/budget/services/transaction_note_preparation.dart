import '../../../data/models/qesto_models.dart';
import '../../../synoball/core/synoball_core.dart';
import '../../../synoball/ingestion/adapter.dart';
import '../../../synoball/adapters/qesto_legacy_bridge.dart';
import '../../../synoball/analytics/qesto_read_model.dart';
import 'cash_flow_calculation_service.dart';
import '../../transaction_import/services/sber_transaction_projection.dart';

/// The existing controller edit, shared with staged preparation. No persistence.
bool applyQestoTransactionEdit(
  SynoballCore core,
  BudgetTransaction transaction, {
  required String actorId,
  BudgetTransaction? displayed,
}) {
  final canonical = core.transactionById(transaction.id);
  if (canonical == null) return false;
  final categoryChanged =
      transaction.categoryId !=
      (displayed?.categoryId ?? canonical.effectiveCategory);
  final updated = categoryChanged
      ? transaction.copyWith(
          tags: {
            ...transaction.tags.where((tag) => tag != qestoAutoCategoryTag),
            qestoManualCategoryTag,
          }.toList(),
        )
      : transaction;
  core.updateTransaction(
    const QestoLegacyBridge().canonicalFromQesto(
      updated,
      previous: canonical,
      categoryWasEdited: categoryChanged,
    ),
    actorId: actorId,
  );
  return true;
}

class PreparedTransactionNote {
  const PreparedTransactionNote(this.data, this.core);
  final UserFinancialData data;
  final SynoballCore core;
}

/// Runs only on an already canonical profile. Legacy ingestion is not migration.
PreparedTransactionNote prepareTransactionNote(
  UserFinancialData before,
  String transactionId,
  String note, {
  SynoballIdFactory? ids,
  DateTime Function()? clock,
}) {
  final state = before.synoballState;
  if (state == null) throw StateError('Canonical profile required');
  final core = SynoballCore(
    initialState: state,
    categoryPolicy: before.classification.policy,
    ids: ids,
    clock: clock,
  );
  final displayed = before.transactions
      .where((t) => t.id == transactionId)
      .firstOrNull;
  if (displayed == null) throw StateError('Visible transaction required');
  applyQestoTransactionEdit(
    core,
    displayed.copyWith(comment: note),
    actorId: before.user.id,
    displayed: displayed,
  );
  final readModel = const QestoReadModelService().build(core.state);
  return PreparedTransactionNote(
    before.copyWith(
      accounts: readModel.accounts,
      transactions: projectSberTransactions(
        readModel.transactions,
        before.classification.policy,
      ).toList(),
      synoballState: core.state,
    ),
    core,
  );
}
