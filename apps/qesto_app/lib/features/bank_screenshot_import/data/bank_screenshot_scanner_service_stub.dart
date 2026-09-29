import '../domain/bank_screenshot_models.dart';

const bankScreenshotScannerSupported = false;

Future<List<ExtractedBankScreenshot>> pickAndRecognizeBankScreenshots() {
  throw UnsupportedError('Импорт скриншотов на этой платформе недоступен');
}
