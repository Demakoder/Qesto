import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/fixtures/budget_categories.dart';
import '../../mocks/fixtures/empty_user_financial_data.dart';
import '../models/qesto_models.dart';
import '../persistence/user_financial_data_codec.dart';
import '../../features/benefits/data/deals_api_client.dart';
import '../../features/benefits/data/deals_cache.dart';
import 'qesto_repository.dart';

class LocalQestoRepository extends QestoRepository {
  LocalQestoRepository({
    this.codec = const UserFinancialDataCodec(),
    DealsApiClient? dealsApiClient,
  }) : dealsApiClient = dealsApiClient ?? DealsApiClient();

  static const _financialDataKey = 'qesto.user-financial-data.v1';
  final UserFinancialDataCodec codec;
  final DealsApiClient dealsApiClient;
  Future<void> _pendingSave = Future<void>.value();
  Future<List<Deal>>? _dealsFuture;

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
  Future<List<Deal>> getCoupons() async => (await _loadDeals())
      .where((deal) => deal.kind == DealKind.coupon)
      .toList(growable: false);

  @override
  Future<List<Deal>> getPromotions() async => (await _loadDeals())
      .where((deal) => deal.kind == DealKind.promotion)
      .toList(growable: false);

  Future<List<Deal>> _loadDeals() => _dealsFuture ??= _fetchOrReadCachedDeals();

  @override
  void resetPublicDeals() => _dealsFuture = null;

  Future<List<Deal>> _fetchOrReadCachedDeals() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final source = await dealsApiClient.fetchOffersJson();
      await preferences.setString(publicDealsCacheKey, source);
      return dealsApiClient.decodeOffers(source);
    } on Object {
      final cached = preferences.getString(publicDealsCacheKey);
      if (cached == null) return const [];
      try {
        return dealsApiClient.decodeOffers(cached);
      } on Object {
        return const [];
      }
    }
  }
}
