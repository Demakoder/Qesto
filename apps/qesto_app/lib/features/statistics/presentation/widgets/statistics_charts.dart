import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../domain/models/statistics_models.dart';
import 'statistics_components.dart';

class StatisticsLineChartCard extends StatefulWidget {
  const StatisticsLineChartCard({
    required this.title,
    required this.points,
    this.comparison = const [],
    this.cumulative = true,
    this.currency = 'RUB',
    this.amountConverter,
    this.selectedDate,
    this.onDaySelected,
    super.key,
  });

  final String title;
  final List<StatisticsDailyPoint> points;
  final List<StatisticsDailyPoint> comparison;
  final bool cumulative;
  final String currency;
  final int Function(int amount)? amountConverter;
  final DateTime? selectedDate;
  final ValueChanged<DateTime>? onDaySelected;

  @override
  State<StatisticsLineChartCard> createState() =>
      _StatisticsLineChartCardState();
}

class _StatisticsLineChartCardState extends State<StatisticsLineChartCard> {
  int? selectedIndex;

  void _select(Offset position, double width) {
    if (widget.points.isEmpty) return;
    final fraction = (position.dx / math.max(width, 1)).clamp(0.0, 1.0);
    final index = (fraction * (widget.points.length - 1)).round();
    if (widget.onDaySelected case final onDaySelected?) {
      onDaySelected(widget.points[index].date);
    } else {
      setState(() => selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.onDaySelected == null
        ? selectedIndex
        : widget.points.indexWhere(
            (point) => DateUtils.isSameDay(point.date, widget.selectedDate),
          );
    final selected =
        activeIndex == null || activeIndex < 0 || widget.points.isEmpty
        ? null
        : widget.points[activeIndex.clamp(0, widget.points.length - 1)];
    final endValue = widget.points.isEmpty
        ? 0
        : widget.cumulative
        ? widget.points.last.cumulative
        : widget.points.fold<int>(0, (sum, point) => sum + point.amount);
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatisticsSectionHeader(
            title: widget.title,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: context.qestoColors.background,
                borderRadius: QestoGeometry.control,
                border: Border.all(color: context.qestoColors.border),
              ),
              child: Text(
                widget.cumulative ? 'По дням' : 'Интервалы',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            label:
                '${widget.title}. Итог ${formatMoney(_amount(endValue), widget.currency)}. Нажмите на график, чтобы выбрать день.',
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    _select(details.localPosition, constraints.maxWidth),
                onLongPressStart: (details) =>
                    _select(details.localPosition, constraints.maxWidth),
                child: SizedBox(
                  height: 210,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _LinePainter(
                      c: context.qestoColors,
                      points: widget.points,
                      comparison: widget.comparison,
                      cumulative: widget.cumulative,
                      selectedIndex: activeIndex != null && activeIndex >= 0
                          ? activeIndex
                          : null,
                      currency: widget.currency,
                      amountConverter: widget.amountConverter,
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: selected == null
                ? const StatisticsInfoBanner(
                    key: ValueKey('line-hint'),
                    message: 'Коснитесь графика, чтобы увидеть день и сумму',
                  )
                : Container(
                    key: ValueKey(selected.date),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.qestoColors.primarySoft,
                      borderRadius: QestoGeometry.control,
                    ),
                    child: Text(
                      widget.onDaySelected == null
                          ? '${formatDate(selected.date, includeYear: true)} · ${formatMoney(_amount(widget.cumulative ? selected.cumulative : selected.amount), widget.currency)} · ${selected.count} операций'
                          : '${formatDate(selected.date, includeYear: true)} · за день ${formatMoney(_amount(selected.amount), widget.currency)} · ${selected.count} операций',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  int _amount(int value) => widget.amountConverter?.call(value) ?? value;
}

class _LinePainter extends CustomPainter {
  final QestoSemanticColors c;
  const _LinePainter({
    required this.c,
    required this.points,
    required this.comparison,
    required this.cumulative,
    required this.selectedIndex,
    required this.currency,
    required this.amountConverter,
  });

  final List<StatisticsDailyPoint> points;
  final List<StatisticsDailyPoint> comparison;
  final bool cumulative;
  final int? selectedIndex;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(8, 12, size.width - 16, size.height - 38);
    final values = <int>[
      for (final point in points) cumulative ? point.cumulative : point.amount,
      for (final point in comparison)
        cumulative ? point.cumulative : point.amount,
    ];
    final maximum = math.max(values.isEmpty ? 1 : values.reduce(math.max), 1);
    final gridPaint = Paint()..color = c.border;
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    void drawSeries(
      List<StatisticsDailyPoint> source,
      Color color,
      double width,
    ) {
      if (source.isEmpty) return;
      final path = Path();
      for (var i = 0; i < source.length; i++) {
        final value = cumulative ? source[i].cumulative : source[i].amount;
        final x =
            plot.left +
            plot.width * (source.length == 1 ? 0 : i / (source.length - 1));
        final y = plot.bottom - plot.height * value / maximum;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    drawSeries(comparison, c.primary.withValues(alpha: 0.26), 2);
    drawSeries(points, c.primary, 3);
    if (selectedIndex != null && points.isNotEmpty) {
      final index = selectedIndex!.clamp(0, points.length - 1);
      final value = cumulative
          ? points[index].cumulative
          : points[index].amount;
      final x =
          plot.left +
          plot.width * (points.length == 1 ? 0 : index / (points.length - 1));
      final y = plot.bottom - plot.height * value / maximum;
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()..color = c.secondaryText.withValues(alpha: 0.5),
      );
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, y),
        5,
        Paint()
          ..color = c.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    labelPainter.text = TextSpan(
      text: formatCompactMoney(
        amountConverter?.call(maximum) ?? maximum,
        currency,
      ),
      style: TextStyle(
        fontFamily: QestoTypography.uiFamily,
        fontSize: 11,
        color: c.secondaryText,
      ),
    );
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(plot.left, 0));
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.c != c ||
      oldDelegate.points != points ||
      oldDelegate.comparison != comparison ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.cumulative != cumulative ||
      oldDelegate.currency != currency;
}

class StatisticsPeriodBarsCard extends StatefulWidget {
  const StatisticsPeriodBarsCard({
    required this.title,
    required this.points,
    super.key,
  });

  final String title;
  final List<StatisticsPeriodPoint> points;

  @override
  State<StatisticsPeriodBarsCard> createState() =>
      _StatisticsPeriodBarsCardState();
}

class _StatisticsPeriodBarsCardState extends State<StatisticsPeriodBarsCard> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    final visible = widget.points.length <= 8
        ? widget.points
        : widget.points.sublist(widget.points.length - 8);
    final maxValue = visible.fold<int>(
      1,
      (value, item) => math.max(value, math.max(item.expenses, item.income)),
    );
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatisticsSectionHeader(title: widget.title),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < visible.length; index++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label:
                          '${formatBudgetPeriod(visible[index].period.month, visible[index].period.year)}: расходы ${formatMoney(visible[index].expenses, 'RUB')}',
                      child: InkWell(
                        onTap: () => setState(() => selected = index),
                        borderRadius: QestoGeometry.control,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (selected == index)
                                FittedBox(
                                  child: Text(
                                    formatCompactMoney(
                                      visible[index].expenses,
                                      'RUB',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Container(
                                height:
                                    126 * visible[index].expenses / maxValue,
                                decoration: BoxDecoration(
                                  color: selected == index
                                      ? context.qestoColors.primary
                                      : context.qestoColors.primary.withValues(
                                          alpha: 0.62,
                                        ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(7),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                _monthShort(visible[index].period.month),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.qestoColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const StatisticsInfoBanner(
            message: 'Столбцы построены из операций каждого бюджетного периода',
          ),
        ],
      ),
    );
  }

  String _monthShort(int month) => const [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ][month - 1];
}

class StatisticsDonut extends StatelessWidget {
  const StatisticsDonut({required this.items, super.key});

  final List<StatisticsGroupStat> items;

  @override
  Widget build(BuildContext context) {
    final top = items.take(6).toList();
    return Semantics(
      label:
          'Структура расходов: ${top.map((item) => '${item.label} ${(item.share * 100).round()} процентов').join(', ')}',
      child: SizedBox(
        height: 178,
        child: Row(
          children: [
            SizedBox(
              width: 148,
              height: 148,
              child: CustomPaint(
                painter: _DonutPainter(top, context.qestoColors),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final item in top.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: Color(
                                item.colorValue ??
                                    context.qestoColors.primary.toARGB32(),
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(item.share * 100).round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final QestoSemanticColors c;
  const _DonutPainter(this.items, this.c);
  final List<StatisticsGroupStat> items;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    if (items.isEmpty) {
      canvas.drawArc(
        rect.deflate(18),
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = c.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22,
      );
      return;
    }
    for (final item in items) {
      final sweep = math.pi * 2 * item.share;
      canvas.drawArc(
        rect.deflate(18),
        start,
        sweep,
        false,
        Paint()
          ..color = Color(item.colorValue ?? c.primary.toARGB32())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.c != c || oldDelegate.items != items;
}

class StatisticsHeatmap extends StatelessWidget {
  const StatisticsHeatmap({
    required this.points,
    required this.onDayTap,
    super.key,
  });

  final List<StatisticsDailyPoint> points;
  final ValueChanged<StatisticsDailyPoint> onDayTap;

  @override
  Widget build(BuildContext context) {
    final maxAmount = points.fold<int>(
      1,
      (value, point) => math.max(value, point.amount),
    );
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: points.length,
      itemBuilder: (context, index) {
        final point = points[index];
        final intensity = point.amount <= 0
            ? 0.05
            : 0.18 + 0.78 * point.amount / maxAmount;
        return Tooltip(
          message:
              '${formatDate(point.date)}: ${formatMoney(point.amount, 'RUB')}',
          child: Semantics(
            button: true,
            label:
                '${formatDate(point.date)}, расходы ${formatMoney(point.amount, 'RUB')}',
            child: InkWell(
              onTap: () => onDayTap(point),
              borderRadius: QestoGeometry.control,
              child: Container(
                decoration: BoxDecoration(
                  color: context.qestoColors.primary.withValues(
                    alpha: intensity,
                  ),
                  borderRadius: QestoGeometry.control,
                  border: point.amount == 0
                      ? Border.all(color: context.qestoColors.border)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${point.date.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: intensity > 0.55
                        ? Theme.of(context).colorScheme.onPrimary
                        : context.qestoColors.text,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class StatisticsScatter extends StatelessWidget {
  const StatisticsScatter({
    required this.items,
    required this.onTap,
    this.currency = 'RUB',
    this.amountConverter,
    super.key,
  });

  final List<StatisticsGroupStat> items;
  final ValueChanged<StatisticsGroupStat> onTap;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(10).toList();
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final item in visible)
          ActionChip(
            onPressed: () => onTap(item),
            avatar: CircleAvatar(
              backgroundColor: context.qestoColors.primary.withValues(
                alpha: (0.2 + item.share).clamp(0.2, 0.9),
              ),
              child: Text(
                '${item.count}',
                style: TextStyle(fontSize: 11, color: context.qestoColors.text),
              ),
            ),
            label: Text(
              '${item.label} · ${formatMoney(amountConverter?.call(item.averageCheck.round()) ?? item.averageCheck.round(), currency)}',
            ),
            tooltip:
                '${item.count} покупок, средний чек ${formatMoney(amountConverter?.call(item.averageCheck.round()) ?? item.averageCheck.round(), currency)}',
          ),
      ],
    );
  }
}
