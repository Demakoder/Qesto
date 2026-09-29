import '../domain/bank_screenshot_models.dart';

abstract interface class BankScreenshotParser {
  String get parserId;
  double confidenceFor(ExtractedBankScreenshot document);
  BankScreenshotParseResult parse(ExtractedBankScreenshot document);
}
