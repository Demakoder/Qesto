import 'receipt_scanner_service_stub.dart'
    if (dart.library.io) 'receipt_scanner_service_native.dart'
    if (dart.library.js_interop) 'receipt_scanner_service_stub.dart'
    as platform;
import 'receipt_scanner_models.dart';

export 'receipt_scanner_models.dart';

class ReceiptScannerService {
  const ReceiptScannerService();

  bool get isSupported => platform.receiptScannerSupported;

  bool get canScanQr => platform.receiptQrScannerSupported;

  bool get canScanDocument => platform.receiptDocumentScannerSupported;

  Future<String?> scanQr() => platform.scanReceiptQr();

  Future<ExtractedReceiptDocument?> scanDocument() =>
      platform.scanReceiptDocument();
}
