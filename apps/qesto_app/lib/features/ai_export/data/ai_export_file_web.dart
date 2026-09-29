import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'ai_export_file_result.dart';

Future<AiExportFileResult> saveAiExportFile(
  String json,
  String fileName,
) async {
  try {
    final blob = web.Blob(
      [json.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    try {
      web.document.body!.appendChild(anchor);
      anchor.click();
    } finally {
      anchor.remove();
      Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
    }
    // Browser APIs cannot confirm that the user saved the download to disk.
    return AiExportFileResult.downloadRequested;
  } on Object {
    throw const AiExportFileException(
      'Браузер не смог начать скачивание JSON.',
    );
  }
}
