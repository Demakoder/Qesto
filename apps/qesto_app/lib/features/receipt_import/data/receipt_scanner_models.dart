class ReceiptTextLine {
  const ReceiptTextLine({
    required this.text,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  final String text;
  final int? left;
  final int? top;
  final int? right;
  final int? bottom;

  factory ReceiptTextLine.fromMap(Map<Object?, Object?> map) {
    return ReceiptTextLine(
      text: map['text']?.toString() ?? '',
      left: map['left'] as int?,
      top: map['top'] as int?,
      right: map['right'] as int?,
      bottom: map['bottom'] as int?,
    );
  }
}

class ExtractedReceiptDocument {
  const ExtractedReceiptDocument({required this.text, required this.lines});

  final String text;
  final List<ReceiptTextLine> lines;

  factory ExtractedReceiptDocument.fromMap(Map<Object?, Object?> map) {
    final rawLines = map['lines'];
    return ExtractedReceiptDocument(
      text: map['text']?.toString() ?? '',
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map(
                  (line) =>
                      ReceiptTextLine.fromMap(Map<Object?, Object?>.from(line)),
                )
                .where((line) => line.text.trim().isNotEmpty)
                .toList()
          : const [],
    );
  }
}
