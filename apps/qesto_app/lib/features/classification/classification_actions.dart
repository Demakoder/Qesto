import 'package:flutter/material.dart';

import '../../data/models/qesto_models.dart';
import '../budget/state/budget_controller.dart';
import '../budget/category_picker.dart';
import '../budget/widgets/budget_category_icon.dart';

const classificationColors = <int>[
  0xff3978ef,
  0xff14977c,
  0xff8b5cf6,
  0xffca6582,
  0xffb88126,
  0xff5d8399,
  0xffa95e39,
  0xff677282,
];
const classificationIcons = <String>[
  'cart',
  'cafe',
  'home',
  'transport',
  'car',
  'health',
  'shopping',
  'phone',
  'subscriptions',
  'fun',
  'gift',
  'family',
  'travel',
  'education',
  'pets',
  'business',
  'savings',
  'investment',
  'fitness',
  'music',
  'book',
  'camera',
];

void classificationError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is ArgumentError
            ? error.message.toString()
            : error is StateError
            ? error.message
            : 'Не удалось сохранить изменение. Повторите попытку.',
      ),
    ),
  );
}

Future<bool> confirmClassification(
  BuildContext context,
  String title,
  String message, {
  String action = 'Подтвердить',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<BudgetCategory?> editCategory(
  BuildContext context,
  BudgetController controller, {
  BudgetCategory? category,
}) => showDialog<BudgetCategory>(
  context: context,
  builder: (_) => _AppearanceEditor(controller: controller, category: category),
);

Future<UserTransactionTag?> editUserTag(
  BuildContext context,
  BudgetController controller, {
  UserTransactionTag? tag,
}) => showDialog<UserTransactionTag>(
  context: context,
  builder: (_) =>
      _AppearanceEditor(controller: controller, tag: tag, isTag: true),
);

class _AppearanceEditor extends StatefulWidget {
  const _AppearanceEditor({
    required this.controller,
    this.category,
    this.tag,
    this.isTag = false,
  });
  final BudgetController controller;
  final BudgetCategory? category;
  final UserTransactionTag? tag;
  final bool isTag;
  @override
  State<_AppearanceEditor> createState() => _AppearanceEditorState();
}

class _AppearanceEditorState extends State<_AppearanceEditor> {
  late final _name = TextEditingController(
    text: widget.tag?.name ?? widget.category?.name ?? '',
  );
  late String _icon = widget.category?.iconKey ?? 'cart';
  late int _color =
      widget.tag?.colorValue ??
      widget.category?.colorValue ??
      classificationColors.first;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      Object result;
      if (widget.isTag) {
        result = await widget.controller.saveUserTag(
          id: widget.tag?.id,
          name: _name.text,
          colorValue: _color,
        );
      } else if (widget.category == null) {
        result = await widget.controller.createCategory(
          name: _name.text,
          iconKey: _icon,
          colorValue: _color,
        );
      } else {
        await widget.controller.updateCategoryAppearance(
          categoryId: widget.category!.id,
          name: _name.text,
          iconKey: _icon,
          colorValue: _color,
        );
        result = widget.controller.categoryById(widget.category!.id);
      }
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ArgumentError
              ? e.message.toString()
              : 'Не удалось сохранить';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isTag ? 'Тег' : 'Категория'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Название',
                errorText: _error,
              ),
              onSubmitted: (_) {
                if (!_saving) _save();
              },
            ),
            const SizedBox(height: 16),
            const Text('Цвет'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in {...classificationColors, _color})
                  Semantics(
                    label: 'Цвет ${c.toRadixString(16)}',
                    selected: c == _color,
                    child: InkWell(
                      onTap: () => setState(() => _color = c),
                      borderRadius: BorderRadius.circular(20),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(c),
                        child: c == _color
                            ? const Icon(
                                Icons.check,
                                size: 22,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (!widget.isTag) ...[
              const SizedBox(height: 20),
              const Text('Иконка'),
              Wrap(
                children: [
                  for (final key in {...classificationIcons, _icon})
                    IconButton(
                      tooltip: key,
                      isSelected: key == _icon,
                      color: Color(_color),
                      onPressed: () => setState(() => _icon = key),
                      icon: Icon(budgetCategoryIcon(key)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
      ),
    ],
  );
}

Future<BudgetCategory?> pickCategory(
  BuildContext context,
  BudgetController controller, {
  String? exceptId,
}) => showBudgetCategoryPicker(
  context: context,
  categories: controller.categories.where((c) => c.id != exceptId).toList(),
  recentCategoryIds:
      (controller.transactions.toList()
            ..sort((a, b) => b.date.compareTo(a.date)))
          .map((t) => t.categoryId)
          .whereType<String>()
          .toSet()
          .take(3)
          .toList(),
  onCreate: () => editCategory(context, controller),
);

Future<void> changeCategory(
  BuildContext context,
  BudgetController controller,
  String id,
) async {
  final selected = await pickCategory(context, controller);
  if (selected == null || !context.mounted) return;
  final count = controller.similarTransactions(id).length;
  final canRule = controller.canCreateMerchantRule(id);
  final scope = await showDialog<CategoryChangeScope>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text('Категория: ${selected.name}'),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.pop(context, CategoryChangeScope.transaction),
          child: const ListTile(
            title: Text('Только эту операцию'),
            subtitle: Text('Ручной выбор сохранится при импорте'),
          ),
        ),
        if (canRule) ...[
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, CategoryChangeScope.history),
            child: ListTile(
              title: const Text('Все похожие прошлые операции'),
              subtitle: Text(
                '$count операций · тот же продавец и направление. Заменит их ручные категории.',
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, CategoryChangeScope.always),
            child: ListTile(
              title: const Text('Прошлые и будущие операции'),
              subtitle: Text(
                '$count операций сейчас + постоянное правило. Будущие ручные правки важнее правила.',
              ),
            ),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
  if (scope == null) return;
  try {
    final changed = await controller.changeTransactionCategory(
      id,
      selected.id,
      scope: scope,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Категория обновлена: $changed операций')),
      );
    }
  } catch (e) {
    if (context.mounted) classificationError(context, e);
  }
}

Future<void> editTransactionTags(
  BuildContext context,
  BudgetController controller,
  String id,
) => showDialog<void>(
  context: context,
  builder: (_) => _TagSelector(controller: controller, id: id),
);

class _TagSelector extends StatefulWidget {
  const _TagSelector({required this.controller, required this.id});
  final BudgetController controller;
  final String id;
  @override
  State<_TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends State<_TagSelector> {
  late final selected = widget.controller
      .tagsForTransaction(
        widget.controller.transactions.firstWhere((t) => t.id == widget.id),
      )
      .map((t) => t.id)
      .toSet();
  String query = '';
  bool saving = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Теги операции'),
    content: SizedBox(
      width: 420,
      height: 340,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Найти тег',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (s) => setState(() => query = s),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final t in widget.controller.classification.tags.where(
                  (t) => t.name.toLowerCase().contains(query.toLowerCase()),
                ))
                  CheckboxListTile(
                    value: selected.contains(t.id),
                    title: Text('#${t.name}'),
                    activeColor: Color(t.colorValue),
                    onChanged: (value) => setState(
                      () => value == true
                          ? selected.add(t.id)
                          : selected.remove(t.id),
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final tag = await editUserTag(context, widget.controller);
              if (tag != null && mounted) setState(() => selected.add(tag.id));
            },
            icon: const Icon(Icons.add),
            label: const Text('Создать тег'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                setState(() => saving = true);
                try {
                  await widget.controller.setTransactionTags(
                    widget.id,
                    selected,
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) {
                    setState(() => saving = false);
                    if (context.mounted) classificationError(context, e);
                  }
                }
              },
        child: const Text('Сохранить'),
      ),
    ],
  );
}

class TransactionClassificationFields extends StatelessWidget {
  const TransactionClassificationFields({
    required this.controller,
    required this.id,
    super.key,
  });
  final BudgetController controller;
  final String id;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final t = controller.transactions.where((t) => t.id == id).firstOrNull;
      if (t == null) return const SizedBox.shrink();
      final category = controller.categories
          .where((c) => c.id == t.categoryId)
          .firstOrNull;
      final tags = controller.tagsForTransaction(t);
      final rule = controller.ruleForTransaction(id);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Категория'),
            subtitle: Text(category?.name ?? 'Без категории'),
            trailing: const Icon(Icons.chevron_right),
            leading: category == null
                ? null
                : BudgetCategoryIcon(
                    iconKey: category.iconKey,
                    color: Color(category.colorValue),
                    size: 36,
                  ),
            onTap: () => changeCategory(context, controller, id),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final tag in tags)
                ActionChip(
                  label: Text('#${tag.name}'),
                  avatar: Icon(
                    Icons.label,
                    size: 16,
                    color: Color(tag.colorValue),
                  ),
                  onPressed: () => editTransactionTags(context, controller, id),
                ),
            ],
          ),
          TextButton.icon(
            onPressed: () => editTransactionTags(context, controller, id),
            icon: const Icon(Icons.label_outline),
            label: const Text('Добавить тег'),
          ),
          if (rule != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Правило: ${rule.merchantLabel} → ${controller.categoryById(rule.categoryId).name}\nРучной выбор операции имеет приоритет.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      );
    },
  );
}

class TransactionQuickActions extends StatelessWidget {
  const TransactionQuickActions({
    required this.controller,
    required this.id,
    required this.onEdit,
    super.key,
  });
  final BudgetController controller;
  final String id;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Действия с операцией',
    icon: const Icon(Icons.more_horiz),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'category', child: Text('Изменить категорию')),
      PopupMenuItem(value: 'tags', child: Text('Добавить тег')),
      PopupMenuItem(value: 'edit', child: Text('Редактировать')),
      PopupMenuItem(value: 'delete', child: Text('Удалить операцию')),
    ],
    onSelected: (action) async {
      if (action == 'category') await changeCategory(context, controller, id);
      if (action == 'tags' && context.mounted) {
        await editTransactionTags(context, controller, id);
      }
      if (action == 'edit') onEdit();
      if (action == 'delete' &&
          context.mounted &&
          await confirmClassification(
            context,
            'Переместить в корзину?',
            'Операция исчезнет из статистики. Её можно будет восстановить в корзине.',
            action: 'Удалить',
          )) {
        try {
          await controller.deleteTransaction(id);
        } catch (e) {
          if (context.mounted) classificationError(context, e);
        }
      }
    },
  );
}
