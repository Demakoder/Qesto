import '../core/models.dart';

class SourceTrustPolicy {
  const SourceTrustPolicy();

  int rank(SourceTrustLevel value) => switch (value) {
    SourceTrustLevel.modelInference => 0,
    SourceTrustLevel.androidNotification => 1,
    SourceTrustLevel.receipt => 2,
    SourceTrustLevel.bankStatement => 3,
    SourceTrustLevel.directApi => 4,
    SourceTrustLevel.regulatedApi => 5,
    SourceTrustLevel.userConfirmed => 6,
  };

  bool shouldReplace({
    required SourceTrustLevel current,
    required SourceTrustLevel incoming,
  }) => rank(incoming) > rank(current);
}
