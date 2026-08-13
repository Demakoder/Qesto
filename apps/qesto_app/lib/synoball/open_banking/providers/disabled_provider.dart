import '../api/cbr_2025_12_v2/accounts.dart';
import '../api/cbr_2025_12_v2/consent.dart';
import '../core/errors.dart';
import '../core/types.dart';
import 'provider.dart';

class DisabledOpenBankingProvider implements OpenBankingProvider {
  const DisabledOpenBankingProvider(this.profile);

  @override
  final OpenBankingProviderProfile profile;

  Future<T> _disabled<T>() => Future.error(
    const OpenBankingNotEnabledError(
      'No live bank provider is registered in this Qesto build.',
    ),
  );

  @override
  Future<CbrAccountConsentResource> createConsent(CbrAccountConsent consent) =>
      _disabled();

  @override
  Future<List<CbrRawAccount>> getAccounts(ConsentId consentId) => _disabled();

  @override
  Future<List<CbrRawBalance>> getBalances(
    ConsentId consentId, {
    String? accountId,
  }) => _disabled();

  @override
  Future<CbrAccountConsentResource> getConsent(ConsentId id) => _disabled();

  @override
  Future<List<CbrRawEntry>> getEntries(
    ConsentId consentId, {
    required String statementId,
  }) => _disabled();

  @override
  Future<List<CbrRawStatement>> getStatements(
    ConsentId consentId, {
    String? accountId,
  }) => _disabled();

  @override
  Future<CbrProviderAuthorizationSession> prepareAuthorization({
    required ConsentId consentId,
    required String stateHash,
    required String nonceHash,
  }) => _disabled();

  @override
  Future<void> revokeConsent(ConsentId id) => _disabled();
}
