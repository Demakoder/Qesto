import 'package:flutter/services.dart';

import 'receipt_scanner_models.dart';

const _channel = MethodChannel('ru.qesto.qesto/receipts');

const receiptScannerSupported = true;

Future<String?> scanReceiptQr() =>
    _channel.invokeMethod<String>('scanReceiptQr');

Future<ExtractedReceiptDocument?> scanReceiptDocument() async {
  final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
    'scanReceiptDocument',
  );
  return raw == null ? null : ExtractedReceiptDocument.fromMap(raw);
}
