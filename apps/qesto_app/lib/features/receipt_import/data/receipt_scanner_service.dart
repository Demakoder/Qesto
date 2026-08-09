import 'receipt_scanner_service_stub.dart'
    if (dart.library.io) 'receipt_scanner_service_native.dart'
    if (dart.library.js_interop) 'receipt_scanner_service_stub.dart'
    as platform;

class ReceiptScannerService {
  const ReceiptScannerService();

  bool get isSupported => platform.receiptScannerSupported;

  Future<String?> scanQr() => platform.scanReceiptQr();
}
