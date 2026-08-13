import 'http.dart';

/// Boundary for DTOs that will be generated from a pinned official CBR schema.
/// No approximate financial fields are introduced at this layer.
abstract class CbrRawResource {
  const CbrRawResource(this.raw);

  final Map<String, Object?> raw;
}

class CbrRawAccount extends CbrRawResource {
  const CbrRawAccount(super.raw);
}

class CbrRawAccountDetails extends CbrRawResource {
  const CbrRawAccountDetails(super.raw);
}

class CbrRawServicer extends CbrRawResource {
  const CbrRawServicer(super.raw);
}

class CbrRawOwner extends CbrRawResource {
  const CbrRawOwner(super.raw);
}

class CbrRawBalance extends CbrRawResource {
  const CbrRawBalance(super.raw);
}

class CbrRawStatement extends CbrRawResource {
  const CbrRawStatement(super.raw);
}

class CbrRawEntry extends CbrRawResource {
  const CbrRawEntry(super.raw);
}

class CbrRawDebtor extends CbrRawResource {
  const CbrRawDebtor(super.raw);
}

class CbrRawDebtorAgent extends CbrRawResource {
  const CbrRawDebtorAgent(super.raw);
}

class CbrRawDebtorAgentAccount extends CbrRawResource {
  const CbrRawDebtorAgentAccount(super.raw);
}

class CbrRawDebtorAccount extends CbrRawResource {
  const CbrRawDebtorAccount(super.raw);
}

class CbrRawUltimateDebtor extends CbrRawResource {
  const CbrRawUltimateDebtor(super.raw);
}

class CbrRawIntermediaryAgent extends CbrRawResource {
  const CbrRawIntermediaryAgent(super.raw);
}

class CbrRawIntermediaryAgentAccount extends CbrRawResource {
  const CbrRawIntermediaryAgentAccount(super.raw);
}

class CbrRawCreditor extends CbrRawResource {
  const CbrRawCreditor(super.raw);
}

class CbrRawCreditorAccount extends CbrRawResource {
  const CbrRawCreditorAccount(super.raw);
}

class CbrRawCreditorAgent extends CbrRawResource {
  const CbrRawCreditorAgent(super.raw);
}

class CbrRawCreditorAgentAccount extends CbrRawResource {
  const CbrRawCreditorAgentAccount(super.raw);
}

class CbrRawUltimateCreditor extends CbrRawResource {
  const CbrRawUltimateCreditor(super.raw);
}

class CbrRawCardTransaction extends CbrRawResource {
  const CbrRawCardTransaction(super.raw);
}

class CbrRawRemittanceInformation extends CbrRawResource {
  const CbrRawRemittanceInformation(super.raw);
}

class CbrAccountInformationEndpoints {
  const CbrAccountInformationEndpoints({
    required this.participantPathPrefix,
    required this.version,
  });

  final String participantPathPrefix;
  final String version;

  CbrResourcePath accounts([String? accountId]) =>
      _path(resource: 'accounts', resourceId: accountId);

  CbrResourcePath balances([String? accountId]) => accountId == null
      ? _path(resource: 'balances')
      : _path(
          resource: 'accounts',
          resourceId: accountId,
          subResource: 'balances',
        );

  CbrResourcePath statements({String? accountId, String? statementId}) {
    if (accountId != null) {
      return _path(
        resource: 'accounts',
        resourceId: accountId,
        subResource: 'statements',
      );
    }
    return _path(resource: 'statements', resourceId: statementId);
  }

  CbrResourcePath _path({
    required String resource,
    String? resourceId,
    String? subResource,
  }) => CbrResourcePath(
    participantPathPrefix: participantPathPrefix,
    version: version,
    resourceGroup: CbrResourcePath.individualAccountsResourceGroup,
    resource: resource,
    resourceId: resourceId,
    subResource: subResource,
  );
}
