import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'bank_statement_file_models.dart';

const _channel = MethodChannel('ru.qesto.qesto/statements');

Future<ExtractedStatementFile?> pickStatementFile(
  StatementPickerMode mode,
) async {
  if (Platform.isWindows && (!_runningInFlutterTester || _forceWindowsBridge)) {
    return _pickWindowsStatement(mode);
  }
  // Keep the established channel method for backwards-compatible native
  // bridges; its result now also carries XLSX/XLSM bytes.
  final value = await _channel.invokeMapMethod<String, Object?>('pickPdf', {
    'mode': mode.name,
  });
  if (value == null) return null;

  final fileName = value['fileName'];
  if (fileName is! String) {
    throw const FormatException('Не удалось прочитать выбранный файл');
  }
  final declaredKind = value['kind'];
  final kind = declaredKind is String
      ? declaredKind
      : fileName.toLowerCase().endsWith('.xlsx') ||
            fileName.toLowerCase().endsWith('.xlsm')
      ? 'excel'
      : 'pdf';
  if (kind == 'excel') {
    final bytes = value['bytes'];
    final normalizedBytes = bytes is Uint8List
        ? bytes
        : bytes is List<int>
        ? Uint8List.fromList(bytes)
        : null;
    if (normalizedBytes == null || normalizedBytes.isEmpty) {
      throw const FormatException('Excel-файл пуст');
    }
    return ExtractedStatementFile(
      fileName: fileName,
      kind: StatementFileKind.excel,
      bytes: normalizedBytes,
    );
  }
  final text = value['text'];
  if (text is! String || text.trim().isEmpty) {
    throw const FormatException('Выписка не содержит доступного текста');
  }
  return ExtractedStatementFile(
    fileName: fileName,
    kind: kind == 'text' ? StatementFileKind.text : StatementFileKind.pdf,
    text: text,
  );
}

bool get _runningInFlutterTester =>
    Platform.resolvedExecutable.toLowerCase().contains('flutter_tester');
bool get _forceWindowsBridge =>
    Platform.environment['QESTO_FORCE_WINDOWS_BRIDGE'] == '1';

Future<ExtractedStatementFile?> _pickWindowsStatement(
  StatementPickerMode mode,
) async {
  final path = await _pickWindowsStatementPath(mode);
  if (path == null) return null;
  final file = File(path);
  if (!await file.exists()) {
    throw PlatformException(
      code: 'statement_read_failed',
      message: 'Выбранный файл выписки не найден',
    );
  }
  try {
    final extension = path.toLowerCase();
    if (extension.endsWith('.xlsx') || extension.endsWith('.xlsm')) {
      return ExtractedStatementFile(
        fileName: file.uri.pathSegments.last,
        kind: StatementFileKind.excel,
        bytes: await file.readAsBytes(),
      );
    }
    final isText = extension.endsWith('.txt');
    final text = isText ? await file.readAsString() : _extractPdfText(path);
    if (text.trim().isEmpty) {
      throw const FormatException('Выписка не содержит доступного текста');
    }
    return ExtractedStatementFile(
      fileName: file.uri.pathSegments.last,
      kind: isText ? StatementFileKind.text : StatementFileKind.pdf,
      text: text,
    );
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw PlatformException(
      code: 'statement_read_failed',
      message: 'Не удалось извлечь текст из PDF: $error',
    );
  }
}

String _extractPdfText(String path) {
  final document = PdfDocument.open(File(path).readAsBytesSync());
  if (document.pageCount <= 0) {
    throw const FormatException('PDF не содержит страниц');
  }
  return [
    for (var page = 0; page < document.pageCount; page++)
      PdfTextExtractor.reflowPage(document, page).text,
  ].join('\n\f\n');
}

Future<String?> _pickWindowsStatementPath(StatementPickerMode mode) async {
  const script = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$path = $env:QESTO_STATEMENT_PATH
if ([string]::IsNullOrWhiteSpace($path)) {
  Add-Type -AssemblyName System.Windows.Forms
  $dialog = [System.Windows.Forms.OpenFileDialog]::new()
  if ($env:QESTO_STATEMENT_PICKER_MODE -eq 'excel') {
    $dialog.Title = 'Выберите Excel-таблицу'
    $dialog.Filter = 'Excel (*.xlsx;*.xlsm)|*.xlsx;*.xlsm'
  } elseif ($env:QESTO_STATEMENT_PICKER_MODE -eq 'statement') {
    $dialog.Title = 'Выберите банковскую выписку'
    $dialog.Filter = 'Выписка (*.pdf;*.txt)|*.pdf;*.txt|PDF (*.pdf)|*.pdf|Текст (*.txt)|*.txt'
  } else {
    $dialog.Title = 'Выберите выписку или таблицу операций'
    $dialog.Filter = 'Финансовые данные (*.pdf;*.xlsx;*.xlsm;*.txt)|*.pdf;*.xlsx;*.xlsm;*.txt|Excel (*.xlsx;*.xlsm)|*.xlsx;*.xlsm|PDF (*.pdf)|*.pdf|Текст (*.txt)|*.txt'
  }
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Output 'QESTO_CANCEL'
    exit 0
  }
  $path = $dialog.FileName
}
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($path))
Write-Output ('QESTO_RESULT:' + $encoded)
''';
  final result = await _runPowerShell(
    script,
    environment: {'QESTO_STATEMENT_PICKER_MODE': mode.name},
  );
  if (result.exitCode != 0) {
    throw PlatformException(
      code: 'statement_read_failed',
      message: _powerShellError(result),
    );
  }
  final line = _resultLine(result.stdout);
  if (line == 'QESTO_CANCEL') return null;
  if (line == null || !line.startsWith('QESTO_RESULT:')) {
    throw PlatformException(
      code: 'statement_read_failed',
      message: 'Windows не вернул путь к выписке',
    );
  }
  return utf8.decode(base64Decode(line.substring('QESTO_RESULT:'.length)));
}

Future<ProcessResult> _runPowerShell(
  String script, {
  Map<String, String>? environment,
}) => Process.run(
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
  environment: environment,
);

List<int> _utf16Le(String value) => [
  for (final unit in value.codeUnits) ...[unit & 0xff, unit >> 8],
];

String? _resultLine(Object? output) {
  final matches = output
      ?.toString()
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where(
        (line) => line == 'QESTO_CANCEL' || line.startsWith('QESTO_RESULT:'),
      )
      .toList();
  return matches == null || matches.isEmpty ? null : matches.last;
}

String _powerShellError(ProcessResult result) {
  final error = result.stderr.toString().trim();
  return error.isEmpty ? 'Не удалось выбрать выписку' : error;
}
