import 'package:flutter/material.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import 'widgets/budget_category_icon.dart';

Future<BudgetCategory?> showBudgetCategoryPicker({
  required BuildContext context,
  required List<BudgetCategory> categories,
  required List<String> recentCategoryIds,
  Future<BudgetCategory?> Function()? onCreate,
}) => showModalBottomSheet<BudgetCategory>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: context.qestoColors.background,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.86,
    child: _CategoryPicker(
      categories: categories,
      recentCategoryIds: recentCategoryIds,
      onCreate: onCreate,
    ),
  ),
);

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({
    required this.categories,
    required this.recentCategoryIds,
    this.onCreate,
  });
  final List<BudgetCategory> categories;
  final List<String> recentCategoryIds;
  final Future<BudgetCategory?> Function()? onCreate;
  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  String query = '';
  bool creating = false;
  Widget tile(BudgetCategory category) => ListTile(
    leading: BudgetCategoryIcon(
      iconKey: category.iconKey,
      color: Color(category.colorValue),
      size: 36,
    ),
    title: Text(category.name),
    onTap: () => Navigator.pop(context, category),
  );
  @override
  Widget build(BuildContext context) {
    final filtered = widget.categories
        .where((c) => c.name.toLowerCase().contains(query.trim().toLowerCase()))
        .toList();
    final recent = widget.recentCategoryIds
        .toSet()
        .map((id) => widget.categories.where((c) => c.id == id).firstOrNull)
        .whereType<BudgetCategory>()
        .take(3)
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Выберите категорию',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Поиск категории',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (text) => setState(() => query = text),
          ),
          if (widget.onCreate != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: creating
                    ? null
                    : () async {
                        setState(() => creating = true);
                        try {
                          final created = await widget.onCreate!();
                          if (created != null && context.mounted) {
                            Navigator.pop(context, created);
                          }
                        } finally {
                          if (mounted) setState(() => creating = false);
                        }
                      },
                icon: const Icon(Icons.add),
                label: const Text('Создать категорию'),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                if (query.isEmpty && recent.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Недавно использованные'),
                  ),
                  ...recent.map(tile),
                  const Divider(),
                  const Text('Все категории'),
                ],
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Категория не найдена'),
                  ),
                ...filtered.map(tile),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
