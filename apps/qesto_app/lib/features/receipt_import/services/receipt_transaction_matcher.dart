import '../../../data/models/qesto_models.dart';
import '../domain/receipt_models.dart';

class ReceiptTransactionMatcher {
  const ReceiptTransactionMatcher();

  List<BudgetTransaction> findMatches({
    required Iterable<BudgetTransaction> transactions,
    required ParsedFiscalReceipt receipt,
  }) {
    final expectedType = receipt.kind == FiscalReceiptKind.refund
        ? TransactionType.refund
        : TransactionType.expense;
    final receiptDay = _day(receipt.purchasedAt);
    final matches = transactions.where((transaction) {
      if (transaction.type != expectedType ||
          transaction.amount.abs() != receipt.roundedRubles ||
          transaction.tags.contains(receipt.transactionTag)) {
        return false;
      }
      final distance = _day(
        transaction.date,
      ).difference(receiptDay).inDays.abs();
      return distance <= 3;
    }).toList();

    matches.sort((left, right) {
      final leftDistance = _day(left.date).difference(receiptDay).inDays.abs();
      final rightDistance = _day(
        right.date,
      ).difference(receiptDay).inDays.abs();
      final byDistance = leftDistance.compareTo(rightDistance);
      return byDistance != 0 ? byDistance : right.date.compareTo(left.date);
    });
    return matches;
  }

  bool isImported({
    required Iterable<BudgetTransaction> transactions,
    required ParsedFiscalReceipt receipt,
  }) => transactions.any(
    (transaction) => transaction.tags.contains(receipt.transactionTag),
  );

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
}
