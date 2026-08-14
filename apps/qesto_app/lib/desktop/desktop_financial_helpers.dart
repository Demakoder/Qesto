import 'package:flutter/material.dart';

import '../core/theme/qesto_theme.dart';
import '../data/models/qesto_models.dart';
import '../features/budget/state/budget_controller.dart';
import '../synoball/core/models.dart';

String desktopTransactionTitle(BudgetTransaction transaction) =>
    transaction.merchant ??
    transaction.title ??
    transaction.description ??
    'Без названия';

int desktopSignedAmount(BudgetTransaction transaction) =>
    switch (transaction.type) {
      TransactionType.income || TransactionType.refund => transaction.amount,
      TransactionType.transfer =>
        transaction.transferDirection == TransferDirection.incoming
            ? transaction.amount
            : -transaction.amount,
      _ => -transaction.amount,
    };

Color desktopAmountColor(BudgetTransaction transaction) =>
    desktopSignedAmount(transaction) > 0
    ? QestoColors.positive
    : QestoColors.text;

String desktopCategoryName(
  BudgetController controller,
  BudgetTransaction transaction,
) {
  final id = transaction.categoryId;
  if (id == null) return 'Без категории';
  for (final category in controller.categories) {
    if (category.id == id) return category.shortName ?? category.name;
  }
  if (id == 'income') return 'Доход';
  return id;
}

String desktopAccountName(
  BudgetController controller,
  BudgetTransaction transaction,
) {
  for (final account in controller.accounts) {
    if (account.id == transaction.accountId) return account.title;
  }
  return 'Неизвестный счёт';
}

List<SourceEvidence> desktopEvidenceFor(
  BudgetController controller,
  String transactionId,
) => controller.synoballState.evidence
    .where((evidence) => evidence.transactionId == transactionId)
    .toList(growable: false);

String desktopSourceLabel(BudgetController controller, String transactionId) {
  final evidence = desktopEvidenceFor(controller, transactionId);
  if (evidence.length > 1) return '${evidence.length} источника';
  if (evidence.isEmpty) return 'Synoball';
  return desktopSourceTypeLabel(evidence.single.sourceType);
}

String desktopSourceTypeLabel(SynoballSourceType type) => switch (type) {
  SynoballSourceType.legacy => 'Миграция',
  SynoballSourceType.manual => 'Вручную',
  SynoballSourceType.manualVoice => 'Голос',
  SynoballSourceType.androidNotification => 'Уведомление',
  SynoballSourceType.receipt => 'Чек',
  SynoballSourceType.statement => 'Выписка',
  SynoballSourceType.regulatedApi => 'Open Finance',
  SynoballSourceType.directApi => 'Банковский API',
  SynoballSourceType.modelInference => 'Модель',
};

IconData desktopSourceIcon(SynoballSourceType type) => switch (type) {
  SynoballSourceType.legacy => Icons.history_rounded,
  SynoballSourceType.manual => Icons.edit_outlined,
  SynoballSourceType.manualVoice => Icons.mic_none_rounded,
  SynoballSourceType.androidNotification => Icons.notifications_none_rounded,
  SynoballSourceType.receipt => Icons.receipt_long_outlined,
  SynoballSourceType.statement => Icons.picture_as_pdf_outlined,
  SynoballSourceType.regulatedApi ||
  SynoballSourceType.directApi => Icons.account_balance_outlined,
  SynoballSourceType.modelInference => Icons.auto_awesome_outlined,
};

bool desktopNeedsReview(BudgetTransaction transaction) =>
    !transaction.isConfirmed ||
    transaction.isPotentialDuplicate ||
    transaction.classificationConfidence < 0.8;
