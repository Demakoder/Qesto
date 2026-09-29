import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../domain/ai_export_mapper.dart';
import '../domain/ai_export_models.dart';
import 'ai_export_file.dart';
import 'ai_export_ids.dart';
import '../domain/ai_export_v2.dart';

typedef AiExportSaver =
    Future<AiExportFileResult> Function(String json, String fileName);
typedef AiExportAction =
    Future<AiExportFileResult> Function(AiExportSelection selection);

class AiExportService {
  AiExportService({AiExportIdStore? ids, AiExportSaver? save})
    : _ids = ids ?? AiExportIdStore.instance,
      _save = save ?? saveAiExportFile;
  final AiExportIdStore _ids;
  final AiExportSaver _save;
  Future<AiExportFileResult> export(AiExportSelection selection) async {
    final ids = await _ids.forProfile(selection.snapshot.profileScope);
    final Map<String, Object?> document;
    final generatedAt = DateTime.now();
    if (selection.settings.version == AiExportVersion.v1) {
      document = (await const AIExportV1Builder().build(
        selection,
        ids,
        generatedAt: generatedAt,
      )).toJson();
    } else {
      document = (await const AIExportV2Builder().build(
        selection,
        ids,
        generatedAt: generatedAt,
      )).toJson();
    }
    final json = await compute(_encode, document);
    return _save(json, 'qesto-ai-export-${aiExportDate(generatedAt)}.json');
  }
}

String _encode(Map<String, Object?> data) =>
    const JsonEncoder.withIndent('  ').convert(data);
