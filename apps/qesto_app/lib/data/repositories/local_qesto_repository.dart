import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/fixtures/budget_categories.dart';
import '../../mocks/fixtures/empty_user_financial_data.dart';
import '../models/qesto_models.dart';
import '../persistence/user_financial_data_codec.dart';
import 'qesto_repository.dart';

class LocalQestoRepository extends QestoRepository {
  LocalQestoRepository({this.codec = const UserFinancialDataCodec()});

  static const _financialDataKey = 'qesto.user-financial-data.v1';

  final UserFinancialDataCodec codec;
  Future<void> _pendingSave = Future<void>.value();

  @override
  Future<BudgetConfiguration> getBudgetConfiguration() async =>
      budgetConfiguration;

  @override
  Future<UserFinancialData> getUserFinancialData() async {
    final preferences = await SharedPreferences.getInstance();
    final source = preferences.getString(_financialDataKey);
    if (source == null) return emptyUserFinancialData;
    try {
      return codec.decode(source);
    } on Object {
      return emptyUserFinancialData;
    }
  }

  @override
  Future<void> saveUserFinancialData(UserFinancialData data) {
    final encoded = codec.encode(data);
    final previousSave = _pendingSave;
    _pendingSave = () async {
      try {
        await previousSave;
      } on Object {
        // A later valid snapshot should still be allowed to replace a failed one.
      }
      await _write(encoded);
    }();
    return _pendingSave;
  }

  Future<void> _write(String encoded) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_financialDataKey, encoded);
    if (!saved) throw StateError('Could not save user financial data');
  }

  @override
  Future<List<Deal>> getCoupons() async => const [];

  @override
  Future<List<Deal>> getPromotions() async => const [];
}
