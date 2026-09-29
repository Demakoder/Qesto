import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_screenshot_import/data/bank_screenshot_scanner_service.dart';
import 'package:qesto/features/bank_screenshot_import/services/bank_screenshot_import_service.dart';

void main() {
  final configured = Platform.environment['QESTO_BANK_SCREENSHOT_PATHS'];
  final enabled =
      Platform.isWindows &&
      Platform.environment['QESTO_FORCE_WINDOWS_BRIDGE'] == '1' &&
      configured != null &&
      configured.isNotEmpty;

  test(
    'Windows OCR bridge recognizes a configured real bank screenshot',
    () async {
      final documents = await const BankScreenshotScannerService()
          .pickAndRecognize();
      expect(documents, isNotEmpty);
      expect(documents.single.lines, isNotEmpty);
      final parsed = const BankScreenshotImportService().parseAll(documents);
      expect(parsed.candidates, hasLength(4));
      expect(
        parsed.candidates.any((candidate) => candidate.amountMinor == 70000),
        isTrue,
      );
      expect(
        parsed.candidates.any((candidate) => candidate.amountMinor == 134900),
        isTrue,
      );
    },
    skip: enabled ? false : 'Requires an explicit local screenshot fixture',
  );
}
