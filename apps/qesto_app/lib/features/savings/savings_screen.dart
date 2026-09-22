import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/qesto_card.dart';
import '../../core/widgets/qesto_elements.dart';
import '../../core/widgets/states.dart';
import '../../data/models/qesto_models.dart';
import '../shared/placeholder_screen.dart';
import 'widgets/gamification_scene.dart';
import 'widgets/savings_placeholders.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({required this.goals, super.key});

  final List<SavingsGoal> goals;

  @override
  State<SavingsScreen> createState() => SavingsScreenState();
}

class SavingsScreenState extends State<SavingsScreen> {
  final _scrollController = ScrollController();

  SavingsGoal? get _activeGoal {
    for (final goal in widget.goals) {
      if (goal.isActive) return goal;
    }
    return widget.goals.isEmpty ? null : widget.goals.first;
  }

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openHistory(SavingsGoal goal) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderScreen(
          title: 'Динамика накоплений',
          description: 'Здесь появится история накоплений',
          icon: Icons.show_chart_rounded,
          child: Column(
            children: [
              QestoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    AmountText(formatMoney(goal.savedAmount, goal.currency)),
                    const SizedBox(height: 4),
                    Text(
                      'Цель: ${formatMoney(goal.targetAmount, goal.currency)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.qestoColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SavingsHistoryChartPlaceholder(),
            ],
          ),
        ),
      ),
    );
  }

  void _openStreak(SavingsGoal goal) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderScreen(
          title: 'Серия накоплений',
          description: 'История серии появится здесь',
          icon: Icons.local_fire_department_rounded,
          child: Column(
            children: [
              QestoCard(
                child: Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: context.qestoColors.orange,
                      size: 38,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${goal.streakWeeks} недели',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SeriesCalendarPlaceholder(),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlaceholder(String title, String description, IconData icon) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderScreen(
          title: title,
          description: description,
          icon: icon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goal = _activeGoal;
    if (goal == null) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(18),
        children: [
          const EmptyState(
            message: 'У вас пока нет целей накопления',
            icon: Icons.savings_outlined,
          ),
          const SizedBox(height: 14),
          QestoButton(
            label: 'Добавить новую цель',
            icon: Icons.add_circle_rounded,
            onPressed: () => _openPlaceholder(
              'Новая цель',
              'Создание новой цели будет добавлено позднее',
              Icons.flag_outlined,
            ),
          ),
        ],
      );
    }

    return ListView(
      key: const PageStorageKey('savings-scroll'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        QestoCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Накоплено',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.qestoColors.secondaryText,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: QestoGeometry.control,
                      child: InkWell(
                        onTap: () => _openHistory(goal),
                        borderRadius: QestoGeometry.control,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: AmountText(
                            formatMoney(goal.savedAmount, goal.currency),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Material(
                    color: context.qestoColors.orange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                    child: InkWell(
                      onTap: () => _openStreak(goal),
                      borderRadius: BorderRadius.circular(99),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_fire_department_rounded,
                              color: context.qestoColors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${goal.streakWeeks} недели',
                              style: const TextStyle(
                                color: Color(0xFFE97B16),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              QestoProgressBar(
                value: goal.progress,
                color: context.qestoColors.green,
              ),
              const SizedBox(height: 9),
              Text(
                '${formatPercent(goal.progress)} до цели • ${goal.title}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        QestoCard(
          padding: EdgeInsets.zero,
          child: GamificationScene(progress: goal.progress),
        ),
        const SizedBox(height: 14),
        QestoActionTile(
          icon: Icons.add_rounded,
          title: 'Добавить новую цель',
          subtitle: 'Поставьте цель и начните копить',
          iconColor: context.qestoColors.green,
          onTap: () => _openPlaceholder(
            'Новая цель',
            'Создание новой цели будет добавлено позднее',
            Icons.flag_outlined,
          ),
        ),
        const SizedBox(height: 11),
        QestoActionTile(
          icon: Icons.emoji_events_rounded,
          title: 'Трофеи',
          subtitle: 'Ваши достижения и награды',
          iconColor: context.qestoColors.orange,
          onTap: () => _openPlaceholder(
            'Трофеи',
            'Ваши достижения появятся здесь',
            Icons.emoji_events_outlined,
          ),
        ),
      ],
    );
  }
}
