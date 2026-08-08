import 'dart:convert';
import 'dart:js_interop';

import 'bank_statement_file_models.dart';

@JS('qestoPickAndExtractPdf')
external JSPromise<JSString?> _pickAndExtractPdf();

Future<ExtractedStatementFile?> pickStatementPdf() async {
  final encoded = await _pickAndExtractPdf().toDart;
  if (encoded == null) return null;

  final decoded = jsonDecode(encoded.toDart);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Не удалось прочитать результат обработки PDF');
  }

  final fileName = decoded['fileName'];
  final text = decoded['text'];
  if (fileName is! String || text is! String || text.trim().isEmpty) {
    throw const FormatException('PDF не содержит доступного текста');
  }
  return ExtractedStatementFile(fileName: fileName, text: text);
}
