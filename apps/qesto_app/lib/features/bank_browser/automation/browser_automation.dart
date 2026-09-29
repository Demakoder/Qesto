import '../domain/bank_browser_models.dart';

/// Future parser boundary. The browser MVP intentionally has no implementation.
abstract interface class BrowserAutomation {
  Stream<PageObservation> get observations;

  Future<void> attach(String profileId);

  Future<void> detach();
}
