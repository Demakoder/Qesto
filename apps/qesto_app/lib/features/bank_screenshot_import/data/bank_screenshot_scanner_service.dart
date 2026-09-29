import 'bank_screenshot_scanner_service_stub.dart'
    if (dart.library.io) 'bank_screenshot_scanner_service_native.dart'
    if (dart.library.js_interop) 'bank_screenshot_scanner_service_stub.dart'
    as platform;
import '../domain/bank_screenshot_models.dart';

abstract interface class BankScreenshotScannerGateway {
  bool get isSupported;
  Future<List<ExtractedBankScreenshot>> pickAndRecognize();
}

class BankScreenshotScannerService implements BankScreenshotScannerGateway {
  const BankScreenshotScannerService();

  @override
  bool get isSupported => platform.bankScreenshotScannerSupported;

  @override
  Future<List<ExtractedBankScreenshot>> pickAndRecognize() =>
      platform.pickAndRecognizeBankScreenshots();
}
