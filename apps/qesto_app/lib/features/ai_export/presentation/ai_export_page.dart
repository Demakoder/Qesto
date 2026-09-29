import 'package:flutter/material.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../design_system/qesto_silver.dart';
import '../../../design_system/qesto_window.dart';
import '../../budget/state/budget_controller.dart';
import '../data/ai_export_file.dart';
import '../data/ai_export_service.dart';
import '../data/ai_export_snapshot.dart';
import 'ai_export_dialog.dart';

class AiExportPage extends StatefulWidget {
  const AiExportPage({required this.controller, this.onExport, super.key});
  final BudgetController controller;
  final AiExportAction? onExport;
  @override
  State<AiExportPage> createState() => _AiExportPageState();
}

class _AiExportPageState extends State<AiExportPage> {
  bool _dialogOpen = false;
  Future<void> _open() async {
    if (_dialogOpen) return;
    setState(() => _dialogOpen = true);
    try {
      final snapshot = captureAiExportSnapshot(widget.controller);
      final generation = widget.controller.dataGeneration;
      final result = await showDialog<AiExportFileResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AiExportDialog(
          snapshot: snapshot,
          onExport: (selection) {
            if (generation != widget.controller.dataGeneration) {
              throw const AiExportFileException(
                'Данные профиля изменились. Закройте окно и подготовьте новый экспорт.',
              );
            }
            return (widget.onExport ?? AiExportService().export)(selection);
          },
        ),
      );
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == AiExportFileResult.downloadRequested
                ? 'Скачивание передано браузеру. Проверьте список загрузок.'
                : 'JSON-файл сохранён',
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось подготовить экспорт. Повторите попытку.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: QestoPrimaryButton(
          key: const Key('ai-export-open'),
          label: 'Экспорт для ИИ',
          icon: Icons.file_download_outlined,
          onPressed: _dialogOpen ? null : _open,
        ),
      ),
      const SizedBox(height: 24),
      QestoWindow(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 36,
                color: context.qestoColors.secondaryText,
              ),
              const SizedBox(height: 20),
              Text(
                'ИИ-помощник Qesto',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              const Text(
                'Здесь появится персональный финансовый помощник.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Пока вы можете экспортировать данные Qesto\nдля анализа во внешнем ИИ.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.qestoColors.secondaryText),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
