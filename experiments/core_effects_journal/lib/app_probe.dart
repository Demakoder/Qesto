import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto/features/transaction_import/services/sber_transaction_projection.dart';
import 'package:qesto/synoball/analytics/qesto_read_model.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as wire;
import 'package:qesto_synoball_core/qesto_synoball_core.dart';

/// Test seam, not an alternate executor. Calls the existing app bridge and full
/// projections. Never publishes to controller, storage or sync coordinator.
CoreJournalPreparation prepareNote(
  UserFinancialData data,
  String id,
  String note,
  CoreEffectsBinding binding,
  DateTime time, {
  CoreJournalPreparation? prior,
}) {
  if (!data.user.id.startsWith('synthetic-4a-'))
    throw StateError('Synthetic only');
  if (binding.kind != 'transaction.set_note' ||
      binding.target != id ||
      binding.policyFingerprint != wire.digest(data.classification.toJson())) {
    throw StateError(
      'Unsupported command or changed policy: full path required',
    );
  }
  final displayed = data.transactions.where((t) => t.id == id).firstOrNull;
  if (displayed == null) throw StateError('Visible target required');
  Object? execute(SynoballCore core) {
    if (!applyQestoTransactionEdit(
      core,
      displayed.copyWith(comment: note),
      actorId: data.user.id,
      displayed: displayed,
    )) {
      throw StateError('Target required');
    }
    return null;
  }

  final ids = CommandIds(binding.commandId);
  return prior == null
      ? CoreJournalPreparation.fromState(
          initialState: data.synoballState!,
          policy: data.classification.policy,
          binding: binding,
          ids: ids,
          clock: () => time,
          execute: execute,
        )
      : prior.prepareNext(
          binding: binding,
          ids: ids,
          clock: () => time,
          execute: execute,
        );
}

UserFinancialData project(UserFinancialData before, SynoballState state) {
  final read = const QestoReadModelService().build(state);
  return before.copyWith(
    synoballState: state,
    accounts: read.accounts,
    transactions: projectSberTransactions(
      read.transactions,
      before.classification.policy,
    ).toList(),
  );
}
