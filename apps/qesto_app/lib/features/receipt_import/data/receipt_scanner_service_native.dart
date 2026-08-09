import 'package:flutter/services.dart';

const _channel = MethodChannel('ru.qesto.qesto/receipts');

const receiptScannerSupported = true;

Future<String?> scanReceiptQr() =>
    _channel.invokeMethod<String>('scanReceiptQr');
