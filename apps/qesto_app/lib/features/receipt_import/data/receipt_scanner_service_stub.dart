import 'receipt_scanner_models.dart';

const receiptScannerSupported = false;
const receiptQrScannerSupported = false;
const receiptDocumentScannerSupported = false;

Future<String?> scanReceiptQr() => throw UnsupportedError(
  'Сканирование QR-кода чека доступно только в Android-приложении',
);

Future<ExtractedReceiptDocument?> scanReceiptDocument() =>
    throw UnsupportedError(
      'Распознавание бумажного чека доступно только в Android-приложении',
    );
