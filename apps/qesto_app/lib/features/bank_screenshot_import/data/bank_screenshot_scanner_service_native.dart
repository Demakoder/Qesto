import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/bank_screenshot_models.dart';

const _channel = MethodChannel('ru.qesto.qesto/bank_screenshots');
final _runningInFlutterTester = Platform.resolvedExecutable
    .toLowerCase()
    .contains('flutter_tester');
final _forceWindowsBridge =
    Platform.environment['QESTO_FORCE_WINDOWS_BRIDGE'] == '1';
final bankScreenshotScannerSupported =
    Platform.isAndroid || Platform.isWindows || _runningInFlutterTester;

Future<List<ExtractedBankScreenshot>> pickAndRecognizeBankScreenshots() async {
  if (Platform.isWindows && (!_runningInFlutterTester || _forceWindowsBridge)) {
    return _pickWindowsScreenshots();
  }
  final raw = await _channel.invokeListMethod<Object?>('pickAndRecognize');
  return (raw ?? const [])
      .whereType<Map>()
      .map(
        (value) =>
            ExtractedBankScreenshot.fromMap(Map<Object?, Object?>.from(value)),
      )
      .toList(growable: false);
}

Future<List<ExtractedBankScreenshot>> _pickWindowsScreenshots() async {
  const script = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
$configured = $env:QESTO_BANK_SCREENSHOT_PATHS
if ([string]::IsNullOrWhiteSpace($configured)) {
  $dialog = [System.Windows.Forms.OpenFileDialog]::new()
  $dialog.Title = 'Выберите скриншоты операций'
  $dialog.Filter = 'Изображения (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp'
  $dialog.Multiselect = $true
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Output 'QESTO_CANCEL'
    exit 0
  }
  $paths = @($dialog.FileNames)
} else {
  $paths = @($configured -split '\|') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
}
if ($paths.Count -gt 10) { throw 'Можно выбрать не более 10 скриншотов' }
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
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) { throw 'Windows OCR недоступен для языков пользователя' }
$documents = @()
foreach ($path in $paths) {
  $info = [System.IO.FileInfo]::new($path)
  if ($info.Length -gt 20MB) { throw 'Скриншот больше 20 МБ' }
  $file = Await-Result ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
  $stream = Await-Result ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await-Result ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap = Await-Result ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $result = Await-Result ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  $lines = @()
  foreach ($line in $result.Lines) {
    $words = @($line.Words)
    if ($words.Count -gt 0) {
      $left = ($words | ForEach-Object { $_.BoundingRect.X } | Measure-Object -Minimum).Minimum
      $top = ($words | ForEach-Object { $_.BoundingRect.Y } | Measure-Object -Minimum).Minimum
      $right = ($words | ForEach-Object { $_.BoundingRect.X + $_.BoundingRect.Width } | Measure-Object -Maximum).Maximum
      $bottom = ($words | ForEach-Object { $_.BoundingRect.Y + $_.BoundingRect.Height } | Measure-Object -Maximum).Maximum
      $lines += [ordered]@{ text=$line.Text; left=$left; top=$top; right=$right; bottom=$bottom }
    } elseif (![string]::IsNullOrWhiteSpace($line.Text)) {
      $lines += [ordered]@{ text=$line.Text }
    }
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $hash = ($sha.ComputeHash([System.IO.File]::ReadAllBytes($path)) | ForEach-Object { $_.ToString('x2') }) -join '' }
  finally { $sha.Dispose(); $stream.Dispose() }
  $documents += [ordered]@{
    imageHash=$hash
    capturedAt=$info.LastWriteTimeUtc.ToString('O')
    width=[double]$decoder.PixelWidth
    height=[double]$decoder.PixelHeight
    lines=$lines
  }
}
$json = ConvertTo-Json -Compress -Depth 7 -InputObject @($documents)
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
Write-Output ('QESTO_RESULT:' + $encoded)
''';
  final result = await Process.run(
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
  if (result.exitCode != 0) {
    final error = result.stderr.toString().trim();
    throw PlatformException(
      code: 'bank_screenshot_ocr_failed',
      message: error.isEmpty ? 'Не удалось распознать скриншоты' : error,
    );
  }
  final output = result.stdout.toString();
  if (output.contains('QESTO_CANCEL')) return const [];
  final marker = output
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.startsWith('QESTO_RESULT:'))
      .lastOrNull;
  if (marker == null) {
    throw PlatformException(
      code: 'bank_screenshot_ocr_failed',
      message: 'Windows OCR не вернул данные',
    );
  }
  final decoded = jsonDecode(
    utf8.decode(base64Decode(marker.substring('QESTO_RESULT:'.length))),
  );
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (value) =>
            ExtractedBankScreenshot.fromMap(Map<Object?, Object?>.from(value)),
      )
      .toList(growable: false);
}

List<int> _utf16Le(String value) => [
  for (final unit in value.codeUnits) ...[unit & 0xff, unit >> 8],
];
