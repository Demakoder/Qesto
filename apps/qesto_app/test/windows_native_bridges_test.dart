import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/receipt_import/data/receipt_scanner_service.dart';
import 'package:qesto/features/statement_import/data/bank_statement_file_service.dart';
import 'package:qesto/features/statement_import/services/sberbank_statement_parser.dart';
import 'package:qesto/features/voice_input/data/voice_capture_service.dart';

void main() {
  final enabled =
      Platform.isWindows &&
      Platform.environment['QESTO_FORCE_WINDOWS_BRIDGE'] == '1';

  test(
    'Windows opens and extracts a real statement PDF',
    () async {
      final file = await const BankStatementFileService().pickPdf();
      expect(file, isNotNull);
      expect(file!.text, contains('Выписка по платёжному счёту'));
      final statement = const SberbankStatementParser().parse(file.text);
      expect(statement.transactions, isNotEmpty);
      final expectedCount = int.tryParse(
        Platform.environment['QESTO_EXPECTED_STATEMENT_TRANSACTIONS'] ?? '',
      );
      if (expectedCount != null) {
        expect(statement.transactions, hasLength(expectedCount));
      }
    },
    skip: enabled ? false : 'native bridge verification is opt-in',
  );

  test(
    'Windows OCR reads a real receipt image',
    () async {
      final document = await const ReceiptScannerService().scanDocument();
      expect(document, isNotNull);
      expect(document!.text.toUpperCase(), contains('МАГАЗИН'));
      expect(document.text, contains('89,99'));
    },
    skip: enabled ? false : 'native bridge verification is opt-in',
  );

  test(
    'offline Whisper recognizes an actual wave stream',
    () async {
      final result = await const VoiceCaptureService().capture();
      expect(result.transcript.trim(), isNotEmpty);
      expect(result.locale, isNotEmpty);
    },
    skip: enabled ? false : 'native bridge verification is opt-in',
  );
}
