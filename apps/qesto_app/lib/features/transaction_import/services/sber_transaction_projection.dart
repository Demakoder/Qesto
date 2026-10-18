import '../../../data/models/qesto_models.dart';
import '../../../synoball/enrichment/category_policy.dart';
import '../../budget/services/cash_flow_calculation_service.dart';
import 'transaction_category_resolver.dart';

// Existing BudgetController projection, moved unchanged for worker reuse.
Iterable<BudgetTransaction> projectSberTransactions(
  Iterable<BudgetTransaction> transactions,
  CategoryPolicy policy,
) sync* {
  const resolver = TransactionCategoryResolver();
  for (final transaction in transactions) {
    if (!transaction.tags.contains('sberbank')) {
      yield transaction;
      continue;
    }
    var compatible = transaction;
    final normalizedTransferText =
        '${transaction.merchant ?? ''} ${transaction.title ?? ''} '
                '${transaction.description ?? ''} '
                '${transaction.comment ?? ''} '
                '${transaction.originalCategoryId ?? ''}'
            .toLowerCase()
            .replaceAll('ё', 'е');
    final ownAccountMovement = RegExp(
      r'между\s+(?:своими|собственными)|на\s+сво[юий]\s+(?:карт|счет)|со\s+своего\s+(?:счета|карт)',
    ).hasMatch(normalizedTransferText);
    final cashMovement =
        normalizedTransferText.contains('внесение наличных') ||
        normalizedTransferText.contains('выдача наличных');
    final hasTransferSemantics =
        transaction.type == TransactionType.transfer ||
        transaction.tags.contains(qestoInternalTransferTag) ||
        transaction.tags.contains(qestoExternalTransferTag);
    if (hasTransferSemantics &&
        !transaction.tags.contains('user-field:type') &&
        !transaction.tags.contains('sber-classification:v2')) {
      final tags = transaction.tags.toSet();
      if (ownAccountMovement || cashMovement) {
        tags
          ..remove(qestoExternalTransferTag)
          ..add(qestoInternalTransferTag);
        compatible = compatible.copyWith(
          type: TransactionType.transfer,
          tags: tags.toList(growable: false),
        );
      } else {
        tags
          ..remove(qestoInternalTransferTag)
          ..add(qestoExternalTransferTag);
        compatible = compatible.copyWith(
          type:
              transaction.transferDirection == TransferDirection.incoming ||
                  transaction.type == TransactionType.income
              ? TransactionType.income
              : TransactionType.expense,
          tags: tags.toList(growable: false),
        );
      }
    }
    if (!transaction.tags.contains(qestoManualCategoryTag) &&
        !transaction.tags.any((t) => t.startsWith(userCategoryRulePrefix))) {
      final resolved = compatible.type == TransactionType.income
          ? const ResolvedTransactionCategory(
              categoryId: 'business',
              confidence: 0.95,
            )
          : resolver.resolve(
              '${transaction.merchant ?? ''} ${transaction.title ?? ''} '
              '${transaction.description ?? ''} '
              '${transaction.originalCategoryId ?? ''}',
            );
      compatible = compatible.copyWith(
        categoryId: policy.resolve(resolved.categoryId),
        subcategoryId: resolved.subcategoryId,
        classificationConfidence: resolved.confidence,
      );
    }
    if (compatible.tags.contains('sber-status-refund') &&
        !transaction.tags.contains('user-field:type') &&
        compatible.type != TransactionType.refund) {
      yield compatible.copyWith(type: TransactionType.refund);
      continue;
    }
    yield compatible;
  }
}
