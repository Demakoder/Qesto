import 'dart:convert';

import '../../data/models/qesto_models.dart';
import '../core/models.dart';
import 'transaction_inputs.dart';

class QestoLegacyBridge {
  const QestoLegacyBridge();

  String entityIdFor(String userId) => 'ent-$userId';

  LegacyInput buildInput(UserFinancialData data) {
    final entityId = entityIdFor(data.user.id);
    final accounts = data.accounts.isEmpty
        ? [
            SynoballAccount(
              id: 'local-default-account',
              entityId: entityId,
              name: 'Основной счёт',
              type: SynoballAccountType.other,
              currency: data.user.defaultCurrency,
              balance: Money(
                minorUnits: 0,
                currency: data.user.defaultCurrency,
              ),
              isVirtual: true,
            ),
          ]
        : data.accounts.map((value) => _account(value, entityId)).toList();
    return LegacyInput(
      entityId: entityId,
      receivedAt: data.referenceDate,
      rawPayload: jsonEncode({
        'legacySchema': 'qesto.user-financial-data.v1',
        'accounts': data.accounts
            .map(
              (value) => {
                'id': value.id,
                'title': value.title,
                'balance': value.balance,
                'currency': value.currency,
                'type': value.type.name,
              },
            )
            .toList(),
        'transactions': data.transactions
            .map(
              (value) => {
                'id': value.id,
                'accountId': value.accountId,
                'date': value.date.toIso8601String(),
                'amount': value.amount,
                'currency': value.currency,
                'type': value.type.name,
                'categoryId': value.categoryId,
                'subcategoryId': value.subcategoryId,
                'merchant': value.merchant,
                'title': value.title,
                'description': value.description,
                'comment': value.comment,
                'normalizedMerchant': value.normalizedMerchant,
                'isRecurring': value.isRecurring,
                'isConfirmed': value.isConfirmed,
                'isPotentialDuplicate': value.isPotentialDuplicate,
                'classificationConfidence': value.classificationConfidence,
                'originalCategoryId': value.originalCategoryId,
                'transferDirection': value.transferDirection?.name,
                'tags': value.tags,
                'receiptId': value.receipt?.id,
              },
            )
            .toList(),
      }),
      entity: SynoballEntity(
        id: entityId,
        type: SynoballEntityType.person,
        displayName: data.user.name,
      ),
      accounts: accounts,
      transactions: data.transactions
          .map((value) => _transaction(value, entityId))
          .toList(growable: false),
      receipts: data.transactions
          .map((value) => _receipt(value))
          .whereType<LegacyReceiptSeed>()
          .toList(growable: false),
    );
  }

  SynoballAccount accountFromQesto(QestoAccount value) =>
      _account(value, entityIdFor(value.userId));

  CanonicalTransaction canonicalFromQesto(
    BudgetTransaction value, {
    required CanonicalTransaction previous,
  }) {
    final seed = _transaction(value, previous.entityId);
    return previous.copyWith(
      accountId: seed.accountId,
      amount: seed.amount,
      direction: seed.direction,
      occurredAt: seed.occurredAt,
      rawDescription: seed.description,
      normalizedDescription: _normalize(seed.description),
      merchantName: seed.merchant,
      providerCategory: seed.providerCategory,
      synoballCategory: seed.category,
      userCategoryOverride: value.categoryId,
      categoryConfidence: value.classificationConfidence,
      subcategoryId: seed.subcategoryId,
      transferDirection: seed.transferDirection,
      receiptId: seed.receiptId,
      tags: seed.tags,
      updatedAt: DateTime.now(),
      fieldTrust: SourceTrustLevel.userConfirmed,
    );
  }

  SynoballAccount _account(QestoAccount value, String entityId) =>
      SynoballAccount(
        id: value.id,
        entityId: entityId,
        name: value.title,
        type: switch (value.type) {
          AccountType.cash => SynoballAccountType.cash,
          AccountType.bankCard => SynoballAccountType.card,
          AccountType.savings => SynoballAccountType.savings,
          AccountType.deposit => SynoballAccountType.deposit,
          AccountType.investment => SynoballAccountType.investment,
          AccountType.liability => SynoballAccountType.loan,
          _ => SynoballAccountType.other,
        },
        currency: value.currency,
        balance: Money(
          minorUnits: value.balance * 100,
          currency: value.currency,
        ),
        isVirtual: value.id == 'local-default-account',
      );

  TransactionSeed _transaction(BudgetTransaction value, String entityId) {
    final direction = switch (value.type) {
      TransactionType.income ||
      TransactionType.refund => FinancialDirection.inflow,
      TransactionType.transfer =>
        value.transferDirection == null
            ? FinancialDirection.neutral
            : value.transferDirection == TransferDirection.incoming
            ? FinancialDirection.inflow
            : FinancialDirection.outflow,
      _ => FinancialDirection.outflow,
    };
    final receipt = value.receipt;
    return TransactionSeed(
      canonicalId: value.id,
      accountId: value.accountId,
      amount: Money(
        minorUnits: value.amount.abs() * 100,
        currency: value.currency,
      ),
      direction: direction,
      occurredAt: value.date,
      description:
          value.description ??
          value.comment ??
          value.title ??
          value.merchant ??
          '',
      merchant: value.normalizedMerchant ?? value.merchant ?? value.title,
      providerCategory: value.originalCategoryId,
      category: value.categoryId,
      subcategoryId: value.subcategoryId,
      providerTransactionId: value.id,
      receiptId: receipt?.id,
      transferDirection: value.transferDirection?.name,
      tags: {
        ...value.tags.where(
          (tag) =>
              !tag.startsWith('legacy-type-') &&
              tag != 'qesto-potential-duplicate' &&
              tag != 'qesto-large-purchase' &&
              tag != 'qesto-unconfirmed' &&
              tag != 'qesto-recurring',
        ),
        'legacy-type-${value.type.name}',
        if (value.isPotentialDuplicate) 'qesto-potential-duplicate',
        if (value.isLargePurchase) 'qesto-large-purchase',
        if (!value.isConfirmed) 'qesto-unconfirmed',
        if (value.isRecurring) 'qesto-recurring',
      }.toList(),
      confidence: value.classificationConfidence,
    );
  }

  LegacyReceiptSeed? _receipt(BudgetTransaction transaction) {
    final value = transaction.receipt;
    if (value == null) return null;
    return LegacyReceiptSeed(
      id: value.id,
      purchasedAt: value.purchasedAt,
      total: Money(
        minorUnits: value.totalMinor,
        currency: transaction.currency,
      ),
      fiscalFingerprint:
          '${value.fiscalDriveNumber}:'
          '${value.fiscalDocumentNumber}:${value.fiscalSign}',
      rawText: transaction.comment ?? transaction.description ?? '',
      merchant: value.merchant,
      items: value.items
          .map(
            (item) => ReceiptItem(
              name: item.name,
              quantity: item.quantity,
              unitPrice: item.unitPriceMinor == null
                  ? null
                  : Money(
                      minorUnits: item.unitPriceMinor!,
                      currency: transaction.currency,
                    ),
              total: Money(
                minorUnits: item.totalMinor,
                currency: transaction.currency,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .trim();
