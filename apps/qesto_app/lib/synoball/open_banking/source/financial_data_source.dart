import '../api/cbr_2025_12_v2/accounts.dart';
import '../core/types.dart';
import '../providers/provider.dart';

enum FinancialDataSourceType {
  manual,
  voice,
  receipt,
  statementFile,
  androidNotification,
  cbrOpenApi,
}

class FinancialDataSourceCapabilities {
  const FinancialDataSourceCapabilities({
    this.accounts = false,
    this.balances = false,
    this.entries = false,
    this.offline = true,
  });

  final bool accounts;
  final bool balances;
  final bool entries;
  final bool offline;
}

class FinancialDataSourceDescriptor {
  const FinancialDataSourceDescriptor({
    required this.type,
    required this.capabilities,
    required this.enabled,
  });

  final FinancialDataSourceType type;
  final FinancialDataSourceCapabilities capabilities;
  final bool enabled;
}

class FinancialDataSourceRequest {
  const FinancialDataSourceRequest({required this.entityId, this.consentId});

  final String entityId;
  final ConsentId? consentId;
}

class FinancialDataSourceSnapshot {
  const FinancialDataSourceSnapshot({
    this.accounts = const [],
    this.balances = const [],
    this.statements = const [],
    this.entries = const [],
  });

  final List<CbrRawAccount> accounts;
  final List<CbrRawBalance> balances;
  final List<CbrRawStatement> statements;
  final List<CbrRawEntry> entries;
}

abstract interface class FinancialDataSource {
  FinancialDataSourceDescriptor get descriptor;

  Future<FinancialDataSourceSnapshot> read(FinancialDataSourceRequest request);
}

class CbrOpenApiFinancialDataSource implements FinancialDataSource {
  const CbrOpenApiFinancialDataSource(this.provider);

  final OpenBankingProvider provider;

  @override
  FinancialDataSourceDescriptor get descriptor =>
      const FinancialDataSourceDescriptor(
        type: FinancialDataSourceType.cbrOpenApi,
        capabilities: FinancialDataSourceCapabilities(
          accounts: true,
          balances: true,
          entries: true,
          offline: false,
        ),
        enabled: false,
      );

  @override
  Future<FinancialDataSourceSnapshot> read(
    FinancialDataSourceRequest request,
  ) async {
    final consentId = request.consentId;
    if (consentId == null) {
      throw ArgumentError.value(
        consentId,
        'consentId',
        'CBR Open API requires an authorised consent.',
      );
    }
    final accounts = await provider.getAccounts(consentId);
    final balances = await provider.getBalances(consentId);
    final statements = await provider.getStatements(consentId);
    return FinancialDataSourceSnapshot(
      accounts: accounts,
      balances: balances,
      statements: statements,
    );
  }
}

abstract final class FinancialDataSourceCatalog {
  static const manual = FinancialDataSourceDescriptor(
    type: FinancialDataSourceType.manual,
    capabilities: FinancialDataSourceCapabilities(),
    enabled: true,
  );
  static const voice = FinancialDataSourceDescriptor(
    type: FinancialDataSourceType.voice,
    capabilities: FinancialDataSourceCapabilities(entries: true),
    enabled: true,
  );
  static const receipt = FinancialDataSourceDescriptor(
    type: FinancialDataSourceType.receipt,
    capabilities: FinancialDataSourceCapabilities(entries: true),
    enabled: true,
  );
  static const statementFile = FinancialDataSourceDescriptor(
    type: FinancialDataSourceType.statementFile,
    capabilities: FinancialDataSourceCapabilities(
      accounts: true,
      balances: true,
      entries: true,
    ),
    enabled: true,
  );
  static const androidNotification = FinancialDataSourceDescriptor(
    type: FinancialDataSourceType.androidNotification,
    capabilities: FinancialDataSourceCapabilities(entries: true),
    enabled: true,
  );
  static const cbrOpenApi = FinancialDataSourceDescriptor(
    type: FinancialDataSourceType.cbrOpenApi,
    capabilities: FinancialDataSourceCapabilities(
      accounts: true,
      balances: true,
      entries: true,
      offline: false,
    ),
    enabled: false,
  );

  static const all = [
    manual,
    voice,
    receipt,
    statementFile,
    androidNotification,
    cbrOpenApi,
  ];
}
