import 'ai_export_file_result.dart';

Future<AiExportFileResult> saveAiExportFile(
  String json,
  String fileName,
) async => throw const AiExportFileException(
  'Сохранение JSON на этой платформе пока не поддерживается.',
);
