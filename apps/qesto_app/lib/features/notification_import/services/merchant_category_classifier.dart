import '../domain/parsed_bank_transaction.dart';
import '../../transaction_import/services/transaction_category_resolver.dart';

class MerchantCategoryClassifier {
  const MerchantCategoryClassifier({
    this.resolver = const TransactionCategoryResolver(),
  });

  final TransactionCategoryResolver resolver;

  CategorySuggestion classify(String merchant) {
    final resolved = resolver.resolve(merchant);
    return CategorySuggestion(
      categoryId: resolved.categoryId,
      subcategoryId: resolved.subcategoryId,
    );
  }
}
