import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../core/widgets/qesto_elements.dart';
import '../../../data/models/qesto_models.dart';

class SpendingDonutCard extends StatefulWidget {
  const SpendingDonutCard({
    required this.summary,
    this.onCategoryPress,
    super.key,
  });

  final BudgetSummary summary;
  final ValueChanged<SpendingCategory>? onCategoryPress;

  @override
  State<SpendingDonutCard> createState() => _SpendingDonutCardState();
}

class _SpendingDonutCardState extends State<SpendingDonutCard> {
  String? _selectedCategoryId;

  @override
  void didUpdateWidget(covariant SpendingDonutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.period.id != widget.summary.period.id) {
      _selectedCategoryId = null;
    }
  }

  void _toggleCategory(SpendingCategory category) {
    setState(() {
      _selectedCategoryId = _selectedCategoryId == category.id
          ? null
          : category.id;
    });
    widget.onCategoryPress?.call(category);
  }

  void _handleChartTap(TapDownDetails details, double size) {
    final categories = widget.summary.categories;
    final total = categories.fold<int>(0, (sum, item) => sum + item.amount);
    if (total == 0) return;

    final center = Offset(size / 2, size / 2);
    final local = details.localPosition - center;
    final distance = local.distance;
    if (distance < size * 0.25 || distance > size * 0.52) return;

    var angle = math.atan2(local.dy, local.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;

    var cursor = 0.0;
    for (final category in categories) {
      final sweep = category.amount / total * math.pi * 2;
      if (angle >= cursor && angle < cursor + sweep) {
        _toggleCategory(category);
        return;
      }
      cursor += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return QestoCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Расходы по категориям'),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 300;
              final chart = _DonutChart(
                summary: summary,
                selectedCategoryId: _selectedCategoryId,
                onTapDown: _handleChartTap,
              );
              final legend = _CategoryLegend(
                summary: summary,
                selectedCategoryId: _selectedCategoryId,
                onTap: _toggleCategory,
              );

              if (compact) {
                return Column(
                  children: [chart, const SizedBox(height: 18), legend],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  chart,
                  const SizedBox(width: 18),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({
    required this.summary,
    required this.selectedCategoryId,
    required this.onTapDown,
  });

  final BudgetSummary summary;
  final String? selectedCategoryId;
  final void Function(TapDownDetails details, double size) onTapDown;

  @override
  Widget build(BuildContext context) {
    const size = 142.0;
    return Semantics(
      label: 'Кольцевая диаграмма расходов',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => onTapDown(details, size),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(size),
                painter: _DonutPainter(
                  categories: summary.categories,
                  selectedCategoryId: selectedCategoryId,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatMoney(
                      summary.currentExpense,
                      summary.period.currency,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: QestoColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary.hasAssignedBudget
                        ? 'из ${formatMoney(summary.period.totalPlan, summary.period.currency)}'
                        : 'бюджет не назначен',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({
    required this.summary,
    required this.selectedCategoryId,
    required this.onTap,
  });

  final BudgetSummary summary;
  final String? selectedCategoryId;
  final ValueChanged<SpendingCategory> onTap;

  @override
  Widget build(BuildContext context) {
    final total = summary.categories.fold<int>(
      0,
      (sum, category) => sum + category.amount,
    );
    return Column(
      children: [
        for (final category in summary.categories)
          _LegendRow(
            category: category,
            currency: summary.period.currency,
            percentage: total == 0 ? 0 : category.amount / total,
            selected: selectedCategoryId == category.id,
            onTap: () => onTap(category),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.category,
    required this.currency,
    required this.percentage,
    required this.selected,
    required this.onTap,
  });

  final SpendingCategory category;
  final String currency;
  final double percentage;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Material(
      color: selected ? color.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: selected ? 12 : 10,
                height: selected ? 12 : 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      formatMoney(category.amount, currency),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                formatPercent(percentage),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.categories,
    required this.selectedCategoryId,
  });

  final List<SpendingCategory> categories;
  final String? selectedCategoryId;

  @override
  void paint(Canvas canvas, Size size) {
    final total = categories.fold<int>(
      0,
      (sum, category) => sum + category.amount,
    );
    if (total == 0) return;

    final center = size.center(Offset.zero);
    var start = -math.pi / 2;
    const gap = 0.025;

    for (final category in categories) {
      final selected = selectedCategoryId == category.id;
      final sweep = category.amount / total * math.pi * 2;
      final strokeWidth = selected ? 33.0 : 29.0;
      final rect = Rect.fromCircle(center: center, radius: size.width / 2 - 19);
      final paint = Paint()
        ..color = Color(category.colorValue)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0, sweep - gap),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.categories != categories ||
        oldDelegate.selectedCategoryId != selectedCategoryId;
  }
}
