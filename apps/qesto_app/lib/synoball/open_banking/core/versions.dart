enum SecurityStandardVersion {
  fapiSec1_6_2024('FAPI.SEC-1.6-2024'),
  fapiPaok1_0_2024('FAPI.PAOK-1.0-2024');

  const SecurityStandardVersion(this.wireName);

  final String wireName;
}

enum ApiStandardVersion {
  cbrOpenApi2025_12V2('CBR-OAPI-2025-12-v2');

  const ApiStandardVersion(this.wireName);

  final String wireName;
}

class OpenBankingVersionProfile {
  const OpenBankingVersionProfile({
    this.security = SecurityStandardVersion.fapiSec1_6_2024,
    this.backchannelAuthentication = SecurityStandardVersion.fapiPaok1_0_2024,
    this.api = ApiStandardVersion.cbrOpenApi2025_12V2,
  });

  final SecurityStandardVersion security;
  final SecurityStandardVersion backchannelAuthentication;
  final ApiStandardVersion api;
}
