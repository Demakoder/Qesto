import '../domain/bank_browser_models.dart';

/// Metadata-only observer. It never receives page HTML, DOM, form values or
/// network payloads.
abstract interface class PageObserver {
  Stream<PageObservation> get observations;
}
