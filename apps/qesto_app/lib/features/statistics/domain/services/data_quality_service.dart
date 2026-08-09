import '../../../../data/models/qesto_models.dart';
import '../models/statistics_models.dart';

class DataQualityService {
  const DataQualityService({this.weights = const {}});

  final Map<DataQualityIssueType, int> weights;

  int _weight(DataQualityIssueType type, int fallback) =>
      weights[type] ?? fallback;

  DataQualityReport evaluate({
    required Iterable<BudgetTransaction> transactions,
    required Set<String> accountIds,
    Set<String> ignoredIssueIds = const {},
  }) {
    final issues = <DataQualityIssue>[];
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.expense &&
          transaction.categoryId == null) {
        issues.add(
          DataQualityIssue(
            id: 'uncategorized-${transaction.id}',
            type: DataQualityIssueType.uncategorized,
            title: 'Нет категории',
            description: transaction.title ?? 'Операция ${transaction.id}',
            weight: _weight(DataQualityIssueType.uncategorized, 7),
            transactionId: transaction.id,
          ),
        );
      }
      final merchant = transaction.normalizedMerchant ?? transaction.merchant;
      if (transaction.type == TransactionType.expense &&
          (merchant == null || merchant.startsWith('Неизвестн'))) {
        issues.add(
          DataQualityIssue(
            id: 'merchant-${transaction.id}',
            type: DataQualityIssueType.unknownMerchant,
            title: 'Неизвестный продавец',
            description: transaction.title ?? 'Нужно проверить получателя',
            weight: _weight(DataQualityIssueType.unknownMerchant, 4),
            transactionId: transaction.id,
          ),
        );
      }
      if (transaction.isPotentialDuplicate && !transaction.isConfirmed) {
        issues.add(
          DataQualityIssue(
            id: 'duplicate-${transaction.id}',
            type: DataQualityIssueType.potentialDuplicate,
            title: 'Возможный дубль',
            description: transaction.title ?? 'Похожая операция уже существует',
            weight: _weight(DataQualityIssueType.potentialDuplicate, 10),
            transactionId: transaction.id,
            isCritical: true,
          ),
        );
      }
      if (!transaction.isConfirmed && !transaction.isPotentialDuplicate) {
        issues.add(
          DataQualityIssue(
            id: 'confirmation-${transaction.id}',
            type: DataQualityIssueType.unconfirmedOperation,
            title: 'Требуется подтверждение',
            description: transaction.title ?? 'Проверьте тип операции',
            weight: _weight(DataQualityIssueType.unconfirmedOperation, 5),
            transactionId: transaction.id,
          ),
        );
      }
      if (transaction.type != TransactionType.transfer &&
          transaction.classificationConfidence < 0.6) {
        issues.add(
          DataQualityIssue(
            id: 'confidence-${transaction.id}',
            type: DataQualityIssueType.lowConfidence,
            title: 'Низкая уверенность распознавания',
            description: transaction.title ?? 'Проверьте категорию и продавца',
            weight: _weight(DataQualityIssueType.lowConfidence, 4),
            transactionId: transaction.id,
          ),
        );
      }
      if (!accountIds.contains(transaction.accountId)) {
        issues.add(
          DataQualityIssue(
            id: 'account-${transaction.id}',
            type: DataQualityIssueType.missingAccount,
            title: 'Не найден счёт',
            description: 'Операция ссылается на неизвестный счёт',
            weight: _weight(DataQualityIssueType.missingAccount, 12),
            transactionId: transaction.id,
            isCritical: true,
          ),
        );
      }
    }
    final visible = issues
        .where((issue) => !ignoredIssueIds.contains(issue.id))
        .toList(growable: false);
    final penalty = visible.fold<int>(0, (sum, issue) => sum + issue.weight);
    return DataQualityReport(
      score: (100 - penalty).clamp(0, 100),
      issues: visible,
    );
  }
}
