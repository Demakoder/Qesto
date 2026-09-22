import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/qesto_card.dart';
import '../../data/models/qesto_models.dart';
import 'widgets/budget_category_icon.dart';

Future<BudgetCategory?> showBudgetCategoryPicker({
  required BuildContext context,
  required List<BudgetCategory> categories,
  required List<String> recentCategoryIds,
}) {
  return showModalBottomSheet<BudgetCategory>(
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
      ),
    ),
  );
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({
    required this.categories,
    required this.recentCategoryIds,
  });

  final List<BudgetCategory> categories;
  final List<String> recentCategoryIds;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  final _searchController = TextEditingController();
  var _showAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BudgetCategory> get _recent => widget.recentCategoryIds
      .map(
        (id) => widget.categories
            .where((category) => category.id == id)
            .firstOrNull,
      )
      .whereType<BudgetCategory>()
      .take(3)
      .toList();

  List<BudgetCategory> get _popular {
    const ids = [
      'groceries',
      'transport',
      'cafes',
      'shopping',
      'health',
      'fun',
    ];
    return ids
        .map(
          (id) => widget.categories
              .where((category) => category.id == id)
              .firstOrNull,
        )
        .whereType<BudgetCategory>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.categories
        .where((category) => category.name.toLowerCase().contains(query))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Выберите категорию',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Закрыть',
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            children: [
              if (_recent.isNotEmpty) ...[
                const _PickerTitle('Недавно использованные'),
                const SizedBox(height: 8),
                for (final category in _recent)
                  _CategoryListTile(
                    category: category,
                    onTap: () => Navigator.of(context).pop(category),
                  ),
                const SizedBox(height: 18),
              ],
              const _PickerTitle('Популярные категории'),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _popular.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 9,
                  mainAxisSpacing: 9,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, index) {
                  final category = _popular[index];
                  final color = Color(category.colorValue);
                  return QestoCard(
                    onTap: () => Navigator.of(context).pop(category),
                    padding: const EdgeInsets.all(9),
                    radius: 17,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BudgetCategoryIcon(
                          iconKey: category.iconKey,
                          color: color,
                          size: 42,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          category.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              if (!_showAll)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showAll = true),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('Все категории'),
                )
              else ...[
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Поиск категории',
                    prefixIcon: Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: context.qestoColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Категория не найдена',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.qestoColors.secondaryText,
                      ),
                    ),
                  )
                else
                  for (final category in filtered)
                    _CategoryListTile(
                      category: category,
                      onTap: () => Navigator.of(context).pop(category),
                    ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Свои категории появятся в следующей версии',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Создать свою категорию'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PickerTitle extends StatelessWidget {
  const _PickerTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _CategoryListTile extends StatelessWidget {
  const _CategoryListTile({required this.category, required this.onTap});

  final BudgetCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      leading: BudgetCategoryIcon(
        iconKey: category.iconKey,
        color: color,
        size: 42,
      ),
      title: Text(
        category.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: context.qestoColors.secondaryText,
      ),
    );
  }
}
