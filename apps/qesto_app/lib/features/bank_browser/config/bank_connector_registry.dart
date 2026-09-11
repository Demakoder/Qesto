import '../domain/bank_browser_models.dart';

abstract final class BankConnectorRegistry {
  static final sber = BankConnectorConfig(
    bankId: 'sber',
    displayName: 'СберБанк Онлайн',
    startUrl: Uri.https('online.sberbank.ru', '/'),
    allowedOrigins: const {'https://online.sberbank.ru'},
    authOrigins: const {'https://id.sber.ru'},
    supportsBackgroundSync: true,
  );

  static final Map<String, BankConnectorConfig> _byId = {sber.bankId: sber};

  static List<BankConnectorConfig> get all => List.unmodifiable(_byId.values);

  static BankConnectorConfig? byId(String id) => _byId[id];
}
