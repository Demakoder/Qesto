import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'ai_export_file_result.dart';

const _channel = MethodChannel('ru.qesto.qesto/ai_export');

Future<AiExportFileResult> saveAiExportFile(
  String json,
  String fileName,
) async {
  try {
    if (Platform.isWindows) return await saveWindowsAiExport(json, fileName);
    if (Platform.isAndroid) {
      return await saveAndroidAiExport(json, fileName);
    }
    throw const AiExportFileException(
      'Сохранение JSON на этой платформе пока не поддерживается.',
    );
  } on AiExportFileException {
    rethrow;
  } on Object {
    // Never surface OS errors containing paths, channel arguments or JSON.
    throw const AiExportFileException(
      'Не удалось сохранить JSON. Проверьте доступ к выбранной папке и повторите попытку.',
    );
  }
}

Future<AiExportFileResult> saveAndroidAiExport(
  String json,
  String fileName,
) async {
  final saved = await _channel.invokeMethod<bool>('saveJson', {
    'fileName': fileName,
    'bytes': Uint8List.fromList(utf8.encode(json)),
  });
  if (saved == null) {
    throw const AiExportFileException(
      'Система не подтвердила сохранение файла.',
    );
  }
  return saved ? AiExportFileResult.saved : AiExportFileResult.cancelled;
}

Future<AiExportFileResult> saveWindowsAiExport(
  String json,
  String fileName, {
  Future<String?> Function(String)? choosePath,
  Future<void> Function(String, String)? writeFile,
}) async {
  final path = await (choosePath ?? _chooseWindowsPath)(fileName);
  if (path == null) return AiExportFileResult.cancelled;
  await (writeFile ?? _writeAtomically)(path, json);
  return AiExportFileResult.saved;
}

Future<void> _writeAtomically(String path, String json) async {
  final target = File(path);
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final temporary = File(
    '${target.parent.path}${Platform.pathSeparator}.qesto-export-$suffix.tmp',
  );
  await temporary.create(exclusive: true);
  try {
    await temporary.writeAsString(json, encoding: utf8, flush: true);
    await temporary.rename(target.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<String?> _chooseWindowsPath(String fileName) async {
  // The shell only chooses a path. Financial content never reaches its args/env/stdout.
  const script = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
$qestoDialog = [System.Windows.Forms.SaveFileDialog]::new()
$qestoDialog.Title = 'Сохранить экспорт для ИИ'
$qestoDialog.Filter = 'JSON (*.json)|*.json'
$qestoDialog.DefaultExt = 'json'
$qestoDialog.AddExtension = $true
$qestoDialog.OverwritePrompt = $true
$qestoDialog.FileName = $env:QESTO_AI_EXPORT_FILENAME
if ($qestoDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
  Write-Output 'QESTO_CANCEL'
} else {
  Write-Output ('QESTO_RESULT:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($qestoDialog.FileName)))
}
$qestoDialog.Dispose()
''';
  final encodedScript = base64Encode([
    for (final c in script.codeUnits) ...[c & 255, c >> 8],
  ]);
  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-STA',
      '-WindowStyle',
      'Hidden',
      '-EncodedCommand',
      encodedScript,
    ],
    environment: {'QESTO_AI_EXPORT_FILENAME': fileName},
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw const AiExportFileException(
      'Не удалось открыть окно сохранения файла.',
    );
  }
  final lines = result.stdout
      .toString()
      .split(RegExp(r'[\r\n]+'))
      .map((v) => v.trim());
  if (lines.contains('QESTO_CANCEL')) return null;
  final answer = lines.where((v) => v.startsWith('QESTO_RESULT:')).toList();
  if (answer.length != 1) {
    throw const AiExportFileException('Окно сохранения не вернуло результат.');
  }
  return utf8.decode(
    base64Decode(answer.single.substring('QESTO_RESULT:'.length)),
  );
}
