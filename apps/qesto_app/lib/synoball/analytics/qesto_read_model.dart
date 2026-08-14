import '../../data/models/qesto_models.dart';
import '../core/models.dart';

class QestoFinancialReadModel {
  const QestoFinancialReadModel({
    required this.accounts,
    required this.transactions,
  });

  final List<QestoAccount> accounts;
  final List<BudgetTransaction> transactions;
}

class QestoReadModelService {
  const QestoReadModelService();

  QestoFinancialReadModel build(SynoballState state) {
    final receipts = {for (final value in state.receipts) value.id: value};
    return QestoFinancialReadModel(
      accounts: state.accounts.map(_account).toList(growable: false),
      transactions: state.transactions
          .where((item) => item.status == CanonicalTransactionStatus.posted)
          .map((item) => _transaction(item, receipts[item.receiptId]))
          .toList(growable: false),
    );
  }

  QestoAccount _account(SynoballAccount value) => QestoAccount(
    id: value.id,
    userId: _userId(value.entityId),
    title: value.name,
    balance: _roundedMajor(value.balance.minorUnits),
    currency: value.currency,
    type: switch (value.type) {
      SynoballAccountType.cash => AccountType.cash,
      SynoballAccountType.card ||
      SynoballAccountType.checking => AccountType.bankCard,
      SynoballAccountType.savings => AccountType.savings,
      SynoballAccountType.deposit => AccountType.deposit,
      SynoballAccountType.brokerage ||
      SynoballAccountType.investment => AccountType.investment,
      SynoballAccountType.credit ||
      SynoballAccountType.loan => AccountType.liability,
      _ => AccountType.other,
    },
  );

  BudgetTransaction _transaction(
    CanonicalTransaction value,
    SynoballReceipt? receipt,
  ) => BudgetTransaction(
    id: value.id,
    userId: _userId(value.entityId),
    accountId: value.accountId,
    date: value.occurredAt,
    amount: _roundedMajor(value.amount.minorUnits.abs()),
    currency: value.amount.currency,
    type: _transactionType(value),
    categoryId: value.effectiveCategory,
    subcategoryId: value.subcategoryId,
    merchant: value.merchantName,
    title: value.merchantName ?? value.normalizedDescription,
    description: value.rawDescription,
    comment: value.rawDescription,
    isLargePurchase: value.tags.contains('qesto-large-purchase'),
    normalizedMerchant: value.merchantName?.toLowerCase(),
    isRecurring: value.isRecurring || value.tags.contains('qesto-recurring'),
    isConfirmed: !value.tags.contains('qesto-unconfirmed'),
    isPotentialDuplicate: value.tags.contains('qesto-potential-duplicate'),
    classificationConfidence:
        value.categoryConfidence ?? value.merchantConfidence ?? 1,
    originalCategoryId: value.providerCategory,
    transferDirection: value.transferDirection == null
        ? null
        : TransferDirection.values.byName(value.transferDirection!),
    tags: value.tags,
    receipt: receipt == null ? null : _receipt(receipt),
  );

  TransactionType _transactionType(CanonicalTransaction value) {
    for (final type in TransactionType.values) {
      if (value.tags.contains('legacy-type-${type.name}')) return type;
    }
    if (value.tags.contains('refund')) return TransactionType.refund;
    if (value.transferDirection != null ||
        value.direction == FinancialDirection.neutral) {
      return TransactionType.transfer;
    }
    return value.direction == FinancialDirection.inflow
        ? TransactionType.income
        : TransactionType.expense;
  }

  TransactionReceiptDetails _receipt(SynoballReceipt value) {
    final fiscal = value.fiscalFingerprint.split(':');
    return TransactionReceiptDetails(
      id: value.id,
      purchasedAt: value.purchasedAt,
      totalMinor: value.total.minorUnits,
      fiscalDriveNumber: fiscal.isEmpty ? '' : fiscal[0],
      fiscalDocumentNumber: fiscal.length < 2 ? '' : fiscal[1],
      fiscalSign: fiscal.length < 3 ? '' : fiscal[2],
      merchant: value.merchant,
      items: value.items
          .map(
            (item) => TransactionReceiptItem(
              name: item.name,
              quantity: item.quantity,
              unitPriceMinor: item.unitPrice?.minorUnits,
              totalMinor: item.total.minorUnits,
            ),
          )
          .toList(growable: false),
    );
  }
}

int _roundedMajor(int minor) => (minor + 50) ~/ 100;
String _userId(String entityId) =>
    entityId.startsWith('ent-') ? entityId.substring(4) : entityId;
