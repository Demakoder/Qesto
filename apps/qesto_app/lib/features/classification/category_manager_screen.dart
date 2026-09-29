import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../data/models/qesto_models.dart';
import '../../desktop/pages/desktop_transactions_page.dart';
import '../budget/state/budget_controller.dart';
import '../budget/widgets/budget_category_icon.dart';
import 'classification_actions.dart';

Future<void> openCategoryManager(
  BuildContext context,
  BudgetController controller,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CategoryManagerScreen(controller: controller),
  ),
);

class CategoryManagerScreen extends StatelessWidget {
  const CategoryManagerScreen({required this.controller, super.key});
  final BudgetController controller;

  void _operations(BuildContext context, {String? categoryId, String? tagId}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Все операции')),
          body: DesktopTransactionsPage(
            controller: controller,
            initialCategoryId: categoryId,
            initialTagId: tagId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Категории и теги'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Категории'),
            Tab(text: 'Теги'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => editCategory(context, controller),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить категорию'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Суммы за ${formatDate(DateTime(controller.referenceDate.year, controller.referenceDate.month), includeYear: true)} — ${formatDate(DateTime(controller.referenceDate.year, controller.referenceDate.month + 1, 0), includeYear: true)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final category in controller.categories)
                  Card(
                    child: ListTile(
                      leading: BudgetCategoryIcon(
                        iconKey: category.iconKey,
                        color: Color(category.colorValue),
                        size: 40,
                      ),
                      title: Text(category.name),
                      subtitle: Text(_categorySummary(category.id)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _categoryDetails(context, category.id),
                    ),
                  ),
                if (controller.hiddenSystemCategories.isNotEmpty)
                  ExpansionTile(
                    title: const Text('Объединённые системные категории'),
                    children: [
                      for (final c in controller.hiddenSystemCategories)
                        ListTile(
                          title: Text(c.name),
                          subtitle: Text(
                            'Новые операции → ${controller.categoryById(c.id).name}',
                          ),
                          trailing: TextButton(
                            child: const Text('Восстановить'),
                            onPressed: () async {
                              if (await confirmClassification(
                                context,
                                'Восстановить категорию?',
                                'Вернутся стандартные название и оформление. Уже перенесённые операции останутся в целевой категории.',
                              )) {
                                try {
                                  await controller.restoreSystemCategory(c.id);
                                } catch (e) {
                                  if (context.mounted) {
                                    classificationError(context, e);
                                  }
                                }
                              }
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => editUserTag(context, controller),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить тег'),
                  ),
                ),
                if (controller.classification.tags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Создайте тег, чтобы отмечать операции независимо от категории.',
                    ),
                  ),
                for (final tag in controller.classification.tags)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.label, color: Color(tag.colorValue)),
                      title: Text('#${tag.name}'),
                      subtitle: Text(
                        '${controller.transactions.where((t) => controller.tagsForTransaction(t).any((v) => v.id == tag.id)).length} операций',
                      ),
                      onTap: () => _operations(context, tagId: tag.id),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Действия с тегом',
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Редактировать'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить'),
                          ),
                        ],
                        onSelected: (action) async {
                          if (action == 'edit') {
                            await editUserTag(context, controller, tag: tag);
                            return;
                          }
                          if (await confirmClassification(
                            context,
                            'Удалить тег #${tag.name}?',
                            'Тег будет снят с операций, в том числе в корзине. Сами операции сохранятся.',
                            action: 'Удалить',
                          )) {
                            try {
                              await controller.deleteUserTag(tag.id);
                            } catch (e) {
                              if (context.mounted) {
                                classificationError(context, e);
                              }
                            }
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  String _categorySummary(String id) {
    final count = controller.transactions
        .where((t) => t.categoryId == id)
        .length;
    final now = controller.referenceDate;
    // Reuse the same cash-flow treatment and exact minor-unit calculations as
    // the rest of Qesto; never add unlike currencies together.
    final selected = controller.transactions
        .where((t) => t.categoryId == id)
        .toList();
    final currencies = selected
        .where((t) => t.date.year == now.year && t.date.month == now.month)
        .map((t) => t.currency)
        .toSet();
    final totals = <String>[];
    for (final currency in currencies) {
      final summary = controller.cashFlowCalculationService.calculate(
        transactions: selected,
        from: DateTime(now.year, now.month),
        toExclusive: DateTime(now.year, now.month + 1),
        currency: currency,
      );
      totals.add(
        '${formatMinorMoney(summary.externalOutflowsMinor, currency)} расход · ${formatMinorMoney(summary.externalInflowsMinor, currency)} доход',
      );
    }
    return count == 0
        ? 'Нет операций'
        : 'Операций за всё время: $count${totals.isEmpty ? ' · За месяц: —' : '\n${totals.join('\n')}'}';
  }

  Future<void> _categoryDetails(BuildContext context, String id) async {
    final pageContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final category = controller.categories
              .where((c) => c.id == id)
              .firstOrNull;
          if (category == null) {
            return AlertDialog(
              title: const Text('Категория объединена'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'),
                ),
              ],
            );
          }
          final rules = controller.classification.rules
              .where((r) => r.categoryId == id)
              .toList();
          return AlertDialog(
            title: Text(category.name),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_categorySummary(id)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => editCategory(
                            context,
                            controller,
                            category: category,
                          ),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Оформление'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _operations(pageContext, categoryId: id);
                          },
                          icon: const Icon(Icons.list),
                          label: const Text('Все операции'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('Автоматические правила'),
                    if (rules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Правило создаётся при выборе «Прошлые и будущие операции».',
                        ),
                      ),
                    for (final rule in rules)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${rule.merchantLabel} → ${category.name}'),
                        subtitle: const Text(
                          'Точный продавец и направление операции',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Действия с правилом',
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Изменить категорию'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Удалить правило'),
                            ),
                          ],
                          onSelected: (action) async {
                            try {
                              if (action == 'edit') {
                                final target = await pickCategory(
                                  context,
                                  controller,
                                );
                                if (target != null) {
                                  await controller.updateCategoryRule(
                                    rule.id,
                                    categoryId: target.id,
                                  );
                                }
                              } else if (await confirmClassification(
                                context,
                                'Удалить правило?',
                                'Правило больше не применяется. Ручные категории сохранятся; автоматические могут обновиться при импорте.',
                              )) {
                                await controller.updateCategoryRule(rule.id);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                classificationError(context, e);
                              }
                            }
                          },
                        ),
                      ),
                    const Divider(height: 28),
                    TextButton.icon(
                      onPressed: () => _merge(context, category),
                      icon: const Icon(Icons.merge_type),
                      label: const Text('Объединить с другой категорией'),
                    ),
                    if (!controller.isSystemCategory(id))
                      TextButton.icon(
                        onPressed: () async {
                          if (controller.categoryReferenceCount(id) > 0) {
                            await _merge(context, category);
                            return;
                          }
                          if (await confirmClassification(
                            context,
                            'Удалить категорию?',
                            'Категория «${category.name}» пуста.',
                            action: 'Удалить',
                          )) {
                            try {
                              await controller.deleteCategory(id);
                            } catch (e) {
                              if (context.mounted) {
                                classificationError(context, e);
                              }
                            }
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Удалить категорию'),
                      ),
                    if (controller.isSystemCategory(id))
                      TextButton(
                        onPressed: () async {
                          if (await confirmClassification(
                            context,
                            'Сбросить оформление?',
                            'Вернутся стандартные название, иконка и цвет. Операции и правила не изменятся.',
                          )) {
                            try {
                              await controller.restoreSystemCategory(id);
                            } catch (e) {
                              if (context.mounted) {
                                classificationError(context, e);
                              }
                            }
                          }
                        },
                        child: const Text(
                          'Восстановить стандартное оформление',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _merge(BuildContext context, BudgetCategory category) async {
    final target = await pickCategory(
      context,
      controller,
      exceptId: category.id,
    );
    if (target == null || !context.mounted) return;
    final count = controller.categoryReferenceCount(category.id);
    if (!await confirmClassification(
      context,
      '${category.name} → ${target.name}',
      'Будут перенесены все связи ($count): операции, корзина, правила и планы. Бюджеты за одинаковый период суммируются. '
          '${controller.isSystemCategory(category.id) ? 'Исходная системная категория будет скрыта.' : 'Исходная категория будет удалена.'} Обратного массового переноса нет.',
      action: 'Объединить',
    )) {
      return;
    }
    try {
      await controller.mergeCategories(category.id, target.id);
    } catch (e) {
      if (context.mounted) classificationError(context, e);
    }
  }
}
