import '../data/models/qesto_models.dart';
import '../data/repositories/qesto_repository.dart';
import 'fixtures/budget_categories.dart';
import 'fixtures/empty_user_financial_data.dart';

class MockQestoRepository extends QestoRepository {
  const MockQestoRepository({
    this.delay = const Duration(milliseconds: 220),
    this.financialData,
    this.coupons = const [],
    this.promotions = const [],
  });

  final Duration delay;
  final UserFinancialData? financialData;
  final List<Deal> coupons;
  final List<Deal> promotions;

  Future<T> _respond<T>(T value) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return value;
  }

  @override
  Future<BudgetConfiguration> getBudgetConfiguration() =>
      _respond(budgetConfiguration);

  @override
  Future<UserFinancialData> getUserFinancialData() =>
      _respond(financialData ?? emptyUserFinancialData);

  @override
  Future<List<Deal>> getCoupons() => _respond(coupons);

  @override
  Future<List<Deal>> getPromotions() => _respond(promotions);
}
