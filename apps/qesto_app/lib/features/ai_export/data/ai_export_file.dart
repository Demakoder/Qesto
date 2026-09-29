import 'ai_export_file_result.dart';
import 'ai_export_file_stub.dart'
    if (dart.library.io) 'ai_export_file_native.dart'
    if (dart.library.js_interop) 'ai_export_file_web.dart'
    as platform;
export 'ai_export_file_result.dart';

Future<AiExportFileResult> saveAiExportFile(String json, String fileName) =>
    platform.saveAiExportFile(json, fileName);
