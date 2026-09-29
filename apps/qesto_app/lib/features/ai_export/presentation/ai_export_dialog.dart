import 'package:flutter/material.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../design_system/qesto_silver.dart';
import '../../statistics/domain/models/statistics_models.dart';
import '../../statistics/domain/services/statistics_period_range.dart';
import '../data/ai_export_file.dart';
import '../data/ai_export_ids.dart';
import '../data/ai_export_service.dart';
import '../domain/ai_export_models.dart';

class AiExportDialog extends StatefulWidget {
  const AiExportDialog({
    required this.snapshot,
    required this.onExport,
    super.key,
  });
  final AiExportSnapshot snapshot;
  final AiExportAction onExport;
  @override
  State<AiExportDialog> createState() => _AiExportDialogState();
}

class _AiExportDialogState extends State<AiExportDialog> {
  static const presets = {
    StatisticsPeriodPreset.last30Days: 'Последние 30 дней',
    StatisticsPeriodPreset.threeMonths: '3 месяца',
    StatisticsPeriodPreset.sixMonths: '6 месяцев',
    StatisticsPeriodPreset.last12Months: '12 месяцев',
    StatisticsPeriodPreset.allTime: 'Всё время',
    StatisticsPeriodPreset.custom: 'Произвольный период',
  };
  var _preset = StatisticsPeriodPreset.last30Days;
  var _version = AiExportVersion.v2;
  var _detailLevel = AiExportDetailLevel.compact;
  late StatisticsDateRange _period;
  late AiExportSelection _selection;
  bool _hideTransactions = true, _hideAccounts = true, _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _period = _range(_preset)!;
    _select();
  }

  StatisticsDateRange? _range(StatisticsPeriodPreset preset) {
    final result = statisticsPeriodRange(
      preset: preset,
      reference: widget.snapshot.referenceDate,
      transactionDates: widget.snapshot.transactions.map((t) => t.occurredAt),
    );
    // A future-only imported history must not produce a reversed all-time
    // interval. Presets end at the reference day, just as in statistics.
    if (result != null && result.start.isAfter(result.end)) {
      return StatisticsDateRange(result.end, result.end);
    }
    return result;
  }

  void _select() {
    _selection = AiExportSelection(
      widget.snapshot,
      AiExportSettings(
        period: _period,
        hideTransactionNames: _hideTransactions,
        hideAccountNames: _hideAccounts,
        version: _version,
        detailLevel: _detailLevel,
      ),
    );
    _message = null;
  }

  Future<void> _changePeriod(StatisticsPeriodPreset? preset) async {
    if (preset == null || _busy) return;
    StatisticsDateRange? period;
    if (preset == StatisticsPeriodPreset.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31),
        initialDateRange: DateTimeRange(start: _period.start, end: _period.end),
        helpText: 'Период экспорта',
        cancelText: 'Отмена',
        confirmText: 'Выбрать',
        saveText: 'Выбрать',
      );
      if (!mounted || picked == null) return;
      period = StatisticsDateRange(picked.start, picked.end);
    } else {
      period = _range(preset);
    }
    if (period == null) return;
    setState(() {
      _period = period!;
      _preset = preset;
      _select();
    });
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.onExport(_selection);
      if (!mounted) return;
      if (result == AiExportFileResult.cancelled) {
        setState(() {
          _message = 'Сохранение отменено. Файл не создан.';
        });
      } else {
        // PopScope must be re-enabled before completing this route.
        setState(() => _busy = false);
        Navigator.of(context).pop(result);
      }
    } on AiExportFileException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on AiExportKeyException catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } on Object {
      if (mounted) {
        setState(
          () => _message =
              'Не удалось подготовить JSON. Файл не сохранён. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      key: const Key('ai-export-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Экспорт для ИИ'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AiExportVersion>(
                key: const Key('ai-export-version'),
                initialValue: _version,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Формат JSON'),
                items: const [
                  DropdownMenuItem(
                    value: AiExportVersion.v2,
                    child: Text('v2 — финансовый контекст'),
                  ),
                  DropdownMenuItem(
                    value: AiExportVersion.v1,
                    child: Text('v1 — совместимость'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _version = v!;
                        _select();
                      }),
              ),
              const SizedBox(height: 12),
              if (_version == AiExportVersion.v2) ...[
                DropdownButtonFormField<AiExportDetailLevel>(
                  key: const Key('ai-export-detail-level'),
                  initialValue: _detailLevel,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Формат данных'),
                  items: const [
                    DropdownMenuItem(
                      value: AiExportDetailLevel.compact,
                      child: Text('Лёгкий'),
                    ),
                    DropdownMenuItem(
                      value: AiExportDetailLevel.diagnostic,
                      child: Text('Полный'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _detailLevel = v!;
                          _select();
                        }),
                ),
                const SizedBox(height: 6),
                Text(
                  _detailLevel == AiExportDetailLevel.compact
                      ? 'Основные финансовые данные для анализа в ИИ. Меньше размер файла и расход контекста.'
                      : 'Расширенный файл с качеством распознавания, происхождением данных и информацией дедупликации.',
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<StatisticsPeriodPreset>(
                key: ValueKey('ai-export-period-${_preset.name}'),
                initialValue: _preset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Период'),
                items: [
                  for (final e in presets.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _busy ? null : _changePeriod,
              ),
              const SizedBox(height: 10),
              Text(
                '${_date(_period.start)} — ${_date(_period.end)}',
                key: const Key('ai-export-range'),
              ),
              if (_preset == StatisticsPeriodPreset.custom)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _changePeriod(StatisticsPeriodPreset.custom),
                  child: const Text('Изменить даты'),
                ),
              const SizedBox(height: 14),
              CheckboxListTile(
                key: const Key('ai-export-hide-transactions'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Скрыть названия операций и получателей'),
                value: _hideTransactions,
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _hideTransactions = v!;
                        _select();
                      }),
              ),
              CheckboxListTile(
                key: const Key('ai-export-hide-accounts'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Скрыть названия счетов и карт'),
                value: _hideAccounts,
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _hideAccounts = v!;
                        _select();
                      }),
              ),
              const SizedBox(height: 14),
              const Text('Будет экспортировано'),
              if (_version == AiExportVersion.v2 &&
                  _selection.transactions.any(
                    (t) =>
                        widget
                            .snapshot
                            .canonical
                            ?.facts[t.id]
                            ?.deduplicationStatus ==
                        'possible_duplicate',
                  ))
                const Text(
                  'Есть возможные дубли: они сохранены с отметками качества.',
                ),
              Text(
                'Операций: ${_selection.transactions.length} · Счетов: ${_selection.accounts.length} · Категорий: ${_selection.categoryIds.length}',
                key: const Key('ai-export-counts'),
              ),
              if (_selection.transactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'В этом периоде нет проведённых операций. Можно сохранить файл со счетами или выбрать другой период.',
                  ),
                ),
              if (_selection.excluded.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Исключено записей: ${_selection.excluded.values.fold(0, (a, b) => a + b)}. Они не входят в количество операций.',
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Снимок данных зафиксирован при открытии окна. Балансы — последние известные, не на конец периода. Полнота банковской истории не проверяется.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.qestoColors.secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Файл содержит финансовую информацию и не зашифрован. Qesto не отправляет его автоматически во внешние сервисы.',
              ),
              const SizedBox(height: 6),
              Text(
                'Скрытие названий не делает данные анонимными. Идентификаторы позволяют сопоставлять ваши повторные экспорты.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.qestoColors.secondaryText,
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(
                    key: Key('ai-export-progress'),
                  ),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_message!, key: const Key('ai-export-message')),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ai-export-cancel'),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        QestoPrimaryButton(
          key: const Key('ai-export-save'),
          label: _busy ? 'Подготовка…' : 'Экспортировать JSON',
          onPressed: _busy ? null : _export,
        ),
      ],
    ),
  );
}
