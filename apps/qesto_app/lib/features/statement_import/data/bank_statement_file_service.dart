import 'package:flutter/services.dart';

class ExtractedStatementFile {
  const ExtractedStatementFile({required this.fileName, required this.text});

  final String fileName;
  final String text;
}

class BankStatementFileService {
  const BankStatementFileService();

  static const _channel = MethodChannel('ru.qesto.qesto/statements');

  Future<ExtractedStatementFile?> pickPdf() async {
    final value = await _channel.invokeMapMethod<String, Object?>('pickPdf');
    if (value == null) return null;

    final fileName = value['fileName'];
    final text = value['text'];
    if (fileName is! String || text is! String || text.trim().isEmpty) {
      throw const FormatException('PDF не содержит доступного текста');
    }
    return ExtractedStatementFile(fileName: fileName, text: text);
  }
}
