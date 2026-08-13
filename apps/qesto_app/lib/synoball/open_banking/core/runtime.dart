import 'errors.dart';
import 'types.dart';

class OpenBankingFeatureConfig {
  const OpenBankingFeatureConfig._({required this.enabled, required this.mode});

  static const disabled = OpenBankingFeatureConfig._(
    enabled: false,
    mode: OpenBankingRuntimeMode.disabled,
  );

  factory OpenBankingFeatureConfig.fromEnvironment({
    required bool enabled,
    required OpenBankingRuntimeMode mode,
  }) {
    if (enabled || mode != OpenBankingRuntimeMode.disabled) {
      throw const OpenBankingNotEnabledError(
        'Only enabled=false and mode=disabled are accepted by this build.',
      );
    }
    return disabled;
  }

  /// In-memory fixtures only. This never permits external network access.
  factory OpenBankingFeatureConfig.mockForTests() =>
      const OpenBankingFeatureConfig._(
        enabled: false,
        mode: OpenBankingRuntimeMode.mock,
      );

  final bool enabled;
  final OpenBankingRuntimeMode mode;
}

abstract interface class ExternalIoGuard {
  Never assertExternalIoAllowed();
}

class DenyAllExternalIoGuard implements ExternalIoGuard {
  const DenyAllExternalIoGuard();

  @override
  Never assertExternalIoAllowed() => throw const OpenBankingNotEnabledError();
}

Never assertExternalIoAllowed() =>
    const DenyAllExternalIoGuard().assertExternalIoAllowed();
