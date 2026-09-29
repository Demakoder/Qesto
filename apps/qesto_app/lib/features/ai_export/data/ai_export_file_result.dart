enum AiExportFileResult { saved, cancelled, downloadRequested }

class AiExportFileException implements Exception {
  const AiExportFileException(this.message);
  final String message;
  @override
  String toString() => message;
}
