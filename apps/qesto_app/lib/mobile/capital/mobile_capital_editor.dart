import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../data/models/qesto_models.dart';
import '../../data/persistence/user_financial_data_codec.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../core/safety/financial_write_guard.dart';

/// UI command boundary for legacy commands that mutate memory before awaiting
/// persistence. On failure, retry the existing persistence callback, not CRUD.
/// Compound actions resume at the failed step. This never invents rollback.
class CapitalWriteQueue {
  CapitalWriteQueue(this.controller) : _generation = controller.dataGeneration;
  final BudgetController controller;
  final int _generation;
  void _check() {
    FinancialWriteGuard.check();
    if (controller.dataGeneration != _generation) {
      throw StateError('Financial data replaced while editing');
    }
  }

  List<Future<void> Function()>? _steps;
  var _index = 0;
  bool _pendingPersistence = false;
  bool hasApplied = false;
  String _fingerprint() => const UserFinancialDataCodec().encode(
    controller.mergeInto(
      UserFinancialData(
        user: controller.user,
        referenceDate: controller.referenceDate,
      ),
    ),
  );
  Future<void> run(List<Future<void> Function()> steps) async {
    _check();
    _steps ??= steps;
    while (_index < _steps!.length) {
      _check();
      if (_pendingPersistence) {
        await controller.onChanged?.call();
        _check();
        controller.refreshLocalReadModel();
        _pendingPersistence = false;
        _index++;
        continue;
      }
      final before = _fingerprint();
      try {
        await _steps![_index]();
        hasApplied = hasApplied || _fingerprint() != before;
        _index++;
      } catch (_) {
        _pendingPersistence = _fingerprint() != before;
        hasApplied = hasApplied || _pendingPersistence;
        if (!hasApplied) _steps = null;
        rethrow;
      }
    }
  }
}

enum CapitalInput { text, whole, positive, rate, day, choice, toggle, date }

class CapitalField {
  const CapitalField(
    this.id,
    this.label, {
    this.kind = CapitalInput.text,
    this.required = false,
    this.options = const {},
    this.enabled = true,
    this.allowNegative = false,
    this.visibleWhen,
  });
  final String id, label;
  final CapitalInput kind;
  final bool required, enabled, allowNegative;
  final Map<String, String> options;
  final bool Function(Map<String, String>)? visibleWhen;
}

int capitalWhole(String value) {
  final cleaned = value.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  final match = RegExp(r'^(-?\d+)(?:\.0{1,2})?$').firstMatch(cleaned);
  if (match == null) throw const FormatException('Целая сумма без округления');
  return int.parse(match.group(1)!);
}

int? capitalOptionalWhole(String? value) =>
    value == null || value.trim().isEmpty ? null : capitalWhole(value);
DateTime? capitalDate(String? value) => DateTime.tryParse(value ?? '');
bool capitalBool(Map<String, String> d, String id) => d[id] == 'true';

class MobileCapitalEditor extends StatefulWidget {
  const MobileCapitalEditor({
    required this.controller,
    required this.title,
    required this.fields,
    required this.initial,
    required this.save,
    this.validate,
    this.onDraftChanged,
    this.saveKey = 'capital-save',
    this.saveLabel = 'Сохранить',
    this.note,
    super.key,
  });
  final BudgetController controller;
  final String title, saveKey, saveLabel;
  final String? note;
  final List<CapitalField> fields;
  final Map<String, String> initial;
  final String? Function(Map<String, String>)? validate;
  final void Function(Map<String, String>, String)? onDraftChanged;
  final Future<String?> Function(Map<String, String>, CapitalWriteQueue) save;
  @override
  State<MobileCapitalEditor> createState() => _MobileCapitalEditorState();
}

class _MobileCapitalEditorState extends State<MobileCapitalEditor> {
  final _form = GlobalKey<FormState>();
  late final _writer = CapitalWriteQueue(widget.controller);
  late final _draft = Map<String, String>.of(widget.initial);
  late final _texts = {
    for (final f in widget.fields)
      f.id: TextEditingController(text: _draft[f.id] ?? ''),
  };
  bool _busy = false, _saved = false;
  String? _error;
  bool get _dirty => widget.fields.any(
    (f) => (_draft[f.id] ?? '') != (widget.initial[f.id] ?? ''),
  );
  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _back() async {
    if (_busy) return;
    if (!_dirty && !_writer.hasApplied) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _writer.hasApplied ? 'Закрыть редактор?' : 'Отменить изменения?',
        ),
        content: Text(
          _writer.hasApplied
              ? 'Часть изменений уже применена в памяти. Закрытие не отменяет их. Лучше повторить сохранение.'
              : 'Несохранённые изменения будут потеряны.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Продолжить'),
          ),
          TextButton(
            key: const Key('capital-discard-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Закрыть без сохранения'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _saved = true);
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    if (_busy || _saved) return;
    final mountedValid = _form.currentState!.validate();
    // Lazy form children may be off-screen. Validate the complete draft too.
    for (final f in widget.fields.where(
      (f) => f.visibleWhen?.call(_draft) ?? true,
    )) {
      final error = _validate(f, _draft[f.id]);
      if (error != null) {
        setState(() => _error = '${f.label}: $error');
        return;
      }
    }
    if (!mountedValid) return;
    final validation = widget.validate?.call(_draft);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.save(Map.of(_draft), _writer);
      if (mounted) {
        setState(() => _saved = true);
        Navigator.pop(context, result);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _writer.hasApplied
              ? 'Изменения применены в памяти, запись не завершена. Повторите сохранение — действие не будет добавлено второй раз.'
              : 'Не удалось сохранить. Проверьте данные и повторите.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(CapitalField f, String? text) {
    final v = text?.trim() ?? '';
    if (v.isEmpty) return f.required ? 'Заполните поле' : null;
    if (f.kind == CapitalInput.choice && !f.options.containsKey(v)) {
      return 'Выберите значение';
    }
    if (f.kind == CapitalInput.date && capitalDate(v) == null) {
      return 'Укажите дату';
    }
    if (f.kind == CapitalInput.whole ||
        f.kind == CapitalInput.positive ||
        f.kind == CapitalInput.day) {
      int amount;
      try {
        amount = capitalWhole(v);
      } catch (_) {
        return 'Модель хранит целые единицы. Дробная сумма не будет округлена; укажите целую.';
      }
      if (f.kind == CapitalInput.day && (amount < 1 || amount > 31)) {
        return 'День от 1 до 31';
      }
      if (!f.allowNegative && amount < 0) {
        return 'Сумма не может быть отрицательной';
      }
      if (f.kind == CapitalInput.positive && amount <= 0) {
        return 'Сумма должна быть больше нуля';
      }
    }
    if (f.kind == CapitalInput.rate &&
        ((double.tryParse(v.replaceAll(',', '.')) ?? -1) < 0 ||
            !double.parse(v.replaceAll(',', '.')).isFinite)) {
      return 'Укажите неотрицательную ставку';
    }
    return null;
  }

  Widget _field(CapitalField f) {
    final enabled = !_busy && !_writer.hasApplied && f.enabled;
    final value = _draft[f.id] ?? '';
    void change(String v) => setState(() {
      _draft[f.id] = v;
      widget.onDraftChanged?.call(_draft, f.id);
      for (final entry in _draft.entries) {
        if (entry.key != f.id && _texts[entry.key]?.text != entry.value) {
          _texts[entry.key]?.text = entry.value;
        }
      }
    });
    if (f.kind == CapitalInput.toggle) {
      return SwitchListTile.adaptive(
        key: Key(f.id),
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: value == 'true',
        onChanged: enabled ? (v) => change('$v') : null,
      );
    }
    if (f.kind == CapitalInput.choice) {
      return DropdownButtonFormField<String>(
        key: Key(f.id),
        isExpanded: true,
        initialValue: value.isEmpty ? null : value,
        decoration: InputDecoration(labelText: f.label),
        items: [
          for (final e in f.options.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(
                e.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: enabled
            ? (v) {
                if (v != null) change(v);
              }
            : null,
        validator: f.required
            ? (v) => v == null || v.isEmpty ? 'Выберите значение' : null
            : null,
      );
    }
    if (f.kind == CapitalInput.date) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            key: Key(f.id),
            onPressed: enabled
                ? () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          capitalDate(value) ?? widget.controller.referenceDate,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200),
                    );
                    if (picked != null && mounted) {
                      change(picked.toIso8601String());
                    }
                  }
                : null,
            child: Text(
              '${f.label}: ${capitalDate(value) == null ? 'не задана' : formatDate(capitalDate(value)!, includeYear: true)}',
            ),
          ),
          if (!f.required && value.isNotEmpty)
            TextButton(
              onPressed: enabled ? () => change('') : null,
              child: const Text('Убрать дату'),
            ),
        ],
      );
    }
    return TextFormField(
      key: Key(f.id),
      controller: _texts[f.id],
      enabled: enabled,
      keyboardType: f.kind == CapitalInput.text
          ? TextInputType.text
          : TextInputType.numberWithOptions(
              decimal: true,
              signed: f.allowNegative,
            ),
      decoration: InputDecoration(labelText: f.label),
      validator: (v) => _validate(f, v),
      onChanged: change,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _saved || (!_dirty && !_busy && !_writer.hasApplied),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _form,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(widget.note!),
                ),
              for (final f in widget.fields.where(
                (f) => f.visibleWhen?.call(_draft) ?? true,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _field(f),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    key: const Key('capital-save-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                key: Key(widget.saveKey),
                onPressed: _busy ? null : _save,
                child: Text(
                  _busy
                      ? 'Сохранение…'
                      : _error == null
                      ? widget.saveLabel
                      : 'Повторить сохранение',
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}
