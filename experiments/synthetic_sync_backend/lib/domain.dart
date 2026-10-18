import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'protocol.dart';

class CommandIds extends SynoballIdFactory {
  CommandIds(this.changeId);
  final String changeId;
  int sequence = 0;
  @override
  String next(String prefix) => 'synthetic-$changeId-$prefix-${++sequence}';
}

SynoballState syntheticState(String owner) {
  final time = DateTime.utc(2026, 10, 11);
  return SynoballCore(
    initialState: SynoballState(
      transactions: [
        for (var i = 0; i < 2; i++)
          CanonicalTransaction(
            id: 'synthetic-tx-$i',
            entityId: owner,
            accountId: 'synthetic-account-$i',
            status: CanonicalTransactionStatus.posted,
            amount: Money(
              minorUnits: i == 0 ? 486122 : 1500025,
              currency: i == 0 ? 'RUB' : 'USD',
            ),
            direction: i == 0
                ? FinancialDirection.outflow
                : FinancialDirection.inflow,
            occurredAt: time,
            rawDescription: 'Synthetic fixture $i',
            normalizedDescription: 'synthetic fixture $i',
            userCategoryOverride: 'QA-category-$i',
            tags: const ['user:synthetic'],
            eventType: FinancialEventType.observed,
            createdAt: time,
            updatedAt: time,
            fieldTrust: SourceTrustLevel.userConfirmed,
          ),
      ],
    ),
  ).state;
}

SynoballState applyNote(
  SynoballState state,
  NoteCommand command,
  String owner,
  DateTime now,
) {
  final core = SynoballCore(
    initialState: state,
    ids: CommandIds(command.changeId),
    clock: () => now,
  );
  final transaction = core.transactionById(command.target);
  if (transaction == null || transaction.entityId != owner)
    throw const ApiError(404, 'TRANSACTION_NOT_FOUND');
  if (transaction.status == CanonicalTransactionStatus.deleted)
    throw const ApiError(409, 'TRANSACTION_DELETED');
  core.updateTransaction(
    transaction.copyWith(userNote: command.note),
    actorId: owner,
    purpose: 'Synthetic sync transaction.set_note',
  );
  return core.state;
}

// Complete canonical transaction, with explicit integer minor units on the wire.
Map<String, dynamic> transactionWire(CanonicalTransaction t) => {
  ...t.toJson(),
  'amount': {
    'minor_units': '${t.amount.minorUnits}',
    'currency': t.amount.currency,
    'scale': 2,
  },
};
