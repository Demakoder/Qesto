import '../../mocks/fixtures/budget_categories.dart';
import '../../mocks/fixtures/empty_user_financial_data.dart';
import '../models/qesto_models.dart';
import '../persistence/user_financial_data_codec.dart';
import '../persistence/encrypted_local_key_value_store.dart';
import '../persistence/local_key_value_store.dart';
import '../../features/benefits/data/deals_api_client.dart';
import '../../features/benefits/data/deals_cache.dart';
import 'qesto_repository.dart';

class LocalQestoRepository extends QestoRepository {
  LocalQestoRepository({
    this.codec = const UserFinancialDataCodec(),
    LocalKeyValueStore? store,
    LocalKeyValueStore? publicStore,
    DealsApiClient? dealsApiClient,
  }) : store = store ?? EncryptedLocalKeyValueStore(),
       publicStore = publicStore ?? store ?? const LocalKeyValueStore(),
       dealsApiClient = dealsApiClient ?? DealsApiClient();

  static const _financialDataKey = 'qesto.user-financial-data.v1';
  final UserFinancialDataCodec codec;
  final LocalKeyValueStore store;
  final LocalKeyValueStore publicStore;
  final DealsApiClient dealsApiClient;
  Future<void> _pendingSave = Future<void>.value();
  bool _loadFailed = false;
  Future<List<Deal>>? _dealsFuture;

  @override
  Future<BudgetConfiguration> getBudgetConfiguration() async =>
      budgetConfiguration;

  @override
  Future<UserFinancialData> getUserFinancialData() async {
    try {
      final source = await store.readString(_financialDataKey);
      if (source == null) {
        _loadFailed = false;
        return emptyUserFinancialData;
      }
      final restored = codec.decode(source);
      _loadFailed = false;
      final now = DateTime.now();
      // referenceDate is the application's "today", not part of the user's
      // financial history. Persisting it verbatim made analytics remain on the
      // day/month of the previous launch while newly synced operations were
      // correctly stored with their real dates.
      return restored.copyWith(
        referenceDate: DateTime(now.year, now.month, now.day),
      );
    } on Object {
      _loadFailed = true;
      rethrow;
    }
  }

  @override
  Future<void> saveUserFinancialData(UserFinancialData data) {
    if (_loadFailed) {
      return Future.error(
        StateError('Financial data requires recovery before saving'),
      );
    }
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
    if (_loadFailed) {
      throw StateError('Financial data requires recovery before saving');
    }
    await store.writeString(_financialDataKey, encoded);
  }

  @override
  Future<void> deleteUserFinancialData() async {
    try {
      await _pendingSave;
    } on Object {
      // Deletion remains authoritative even if a previous save failed.
    }
    await store.remove(_financialDataKey);
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
    try {
      final source = await dealsApiClient.fetchOffersJson();
      await publicStore.writeString(publicDealsCacheKey, source);
      return dealsApiClient.decodeOffers(source);
    } on Object {
      final cached = await publicStore.readString(publicDealsCacheKey);
      if (cached == null) return const [];
      try {
        return dealsApiClient.decodeOffers(cached);
      } on Object {
        return const [];
      }
    }
  }
}
