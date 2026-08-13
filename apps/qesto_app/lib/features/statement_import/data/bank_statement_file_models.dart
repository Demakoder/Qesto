import 'dart:typed_data';

enum StatementFileKind { pdf, text, excel }

enum StatementPickerMode { all, statement, excel }

class ExtractedStatementFile {
  const ExtractedStatementFile({
    required this.fileName,
    required this.kind,
    this.text = '',
    this.bytes,
  });

  final String fileName;
  final StatementFileKind kind;
  final String text;
  final Uint8List? bytes;
}
