import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'receipt_scanner_models.dart';

const _channel = MethodChannel('ru.qesto.qesto/receipts');

final _runningInFlutterTester = Platform.resolvedExecutable
    .toLowerCase()
    .contains('flutter_tester');
final _forceWindowsBridge =
    Platform.environment['QESTO_FORCE_WINDOWS_BRIDGE'] == '1';
final receiptQrScannerSupported = Platform.isAndroid || _runningInFlutterTester;
final receiptDocumentScannerSupported =
    Platform.isAndroid || Platform.isWindows || _runningInFlutterTester;
final receiptScannerSupported =
    receiptQrScannerSupported || receiptDocumentScannerSupported;

Future<String?> scanReceiptQr() {
  if (!Platform.isAndroid && !_runningInFlutterTester) {
    throw UnsupportedError('На Windows введите строку из QR-кода вручную');
  }
  return _channel.invokeMethod<String>('scanReceiptQr');
}

Future<ExtractedReceiptDocument?> scanReceiptDocument() async {
  if (Platform.isWindows && (!_runningInFlutterTester || _forceWindowsBridge)) {
    return _scanWindowsReceiptDocument();
  }
  final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
    'scanReceiptDocument',
  );
  return raw == null ? null : ExtractedReceiptDocument.fromMap(raw);
}

Future<ExtractedReceiptDocument?> _scanWindowsReceiptDocument() async {
  const script = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
$path = $env:QESTO_RECEIPT_IMAGE_PATH
if ([string]::IsNullOrWhiteSpace($path)) {
  $dialog = [System.Windows.Forms.OpenFileDialog]::new()
  $dialog.Title = 'Выберите фотографию чека'
  $dialog.Filter = 'Изображения (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp'
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Output 'QESTO_CANCEL'
    exit 0
  }
  $path = $dialog.FileName
}
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime]
$asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and
  $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Await-Result($operation, [Type]$resultType) {
  $task = $asTaskMethod.MakeGenericMethod($resultType).Invoke($null, @($operation))
  $task.Wait()
  return $task.Result
}
$file = Await-Result ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
$stream = Await-Result ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await-Result ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await-Result ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) { throw 'Windows OCR недоступен для языков пользователя' }
$result = Await-Result ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
$text = ($result.Lines | ForEach-Object { $_.Text }) -join "`n"
if ([string]::IsNullOrWhiteSpace($text)) { throw 'На изображении не найден текст' }
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
Write-Output ('QESTO_RESULT:' + $encoded)
''';
  final result = await _runPowerShell(script);
  if (result.exitCode != 0) {
    throw PlatformException(
      code: 'receipt_ocr_failed',
      message: _powerShellError(result),
    );
  }
  final line = _resultLine(result.stdout);
  if (line == 'QESTO_CANCEL') return null;
  if (line == null || !line.startsWith('QESTO_RESULT:')) {
    throw PlatformException(
      code: 'receipt_ocr_failed',
      message: 'Windows OCR не вернул текст чека',
    );
  }
  final text = utf8.decode(
    base64Decode(line.substring('QESTO_RESULT:'.length)),
  );
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .map((value) => ReceiptTextLine(text: value))
      .toList(growable: false);
  return ExtractedReceiptDocument(text: text, lines: lines);
}

Future<ProcessResult> _runPowerShell(String script) => Process.run(
  'powershell.exe',
  [
    '-NoProfile',
    '-NonInteractive',
    '-STA',
    '-EncodedCommand',
    base64Encode(_utf16Le(script)),
  ],
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

List<int> _utf16Le(String value) => [
  for (final unit in value.codeUnits) ...[unit & 0xff, unit >> 8],
];

String? _resultLine(Object? output) {
  final matches = output
      ?.toString()
      .split(RegExp(r'[\r\n]+'))
      .map((value) => value.trim())
      .where(
        (value) => value == 'QESTO_CANCEL' || value.startsWith('QESTO_RESULT:'),
      )
      .toList();
  return matches == null || matches.isEmpty ? null : matches.last;
}

String _powerShellError(ProcessResult result) {
  final error = result.stderr.toString().trim();
  return error.isEmpty ? 'Не удалось распознать изображение чека' : error;
}
