import '../models/qesto_models.dart';

abstract class QestoRepository {
  const QestoRepository();

  Future<BudgetConfiguration> getBudgetConfiguration();
  Future<UserFinancialData> getUserFinancialData();
  Future<List<Deal>> getCoupons();
  Future<List<Deal>> getPromotions();
  Future<void> saveUserFinancialData(UserFinancialData data) async {}

  Future<QestoAppData> loadAppData() async {
    final values = await Future.wait<Object>([
      getBudgetConfiguration(),
      getUserFinancialData(),
      getCoupons(),
      getPromotions(),
    ]);

    return QestoAppData(
      budgetConfiguration: values[0] as BudgetConfiguration,
      financialData: values[1] as UserFinancialData,
      coupons: values[2] as List<Deal>,
      promotions: values[3] as List<Deal>,
    );
  }
}
