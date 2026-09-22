import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../data/models/qesto_models.dart';

enum _SeriesKind { actual, projected, target, limit }

class _Selection {
  const _Selection(this.kind, this.date, this.amount);

  final _SeriesKind kind;
  final DateTime date;
  final double amount;
}

class BudgetDynamicsChart extends StatefulWidget {
  const BudgetDynamicsChart({
    required this.period,
    required this.forecast,
    super.key,
  });

  final BudgetPeriod period;
  final BudgetForecast forecast;

  @override
  State<BudgetDynamicsChart> createState() => _BudgetDynamicsChartState();
}

class _BudgetDynamicsChartState extends State<BudgetDynamicsChart> {
  _Selection? _selection;

  @override
  void didUpdateWidget(covariant BudgetDynamicsChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period.id != widget.period.id) _selection = null;
  }

  void _select(TapDownDetails details, Size size) {
    const left = 51.0;
    const top = 18.0;
    const right = 8.0;
    const bottom = 38.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    if (!plot.contains(details.localPosition)) return;
    final ratio = ((details.localPosition.dx - plot.left) / plot.width).clamp(
      0.0,
      1.0,
    );
    final dayOffset = (ratio * (widget.period.dayCount - 1)).round();
    final date = widget.period.startDate.add(Duration(days: dayOffset));
    final candidates = <_Selection>[];
    void addNearest(_SeriesKind kind, List<DailyBudgetPoint> points) {
      if (points.isEmpty) return;
      final sorted = List.of(points)
        ..sort(
          (a, b) => (a.date.difference(date).inDays.abs()).compareTo(
            b.date.difference(date).inDays.abs(),
          ),
        );
      candidates.add(_Selection(kind, sorted.first.date, sorted.first.amount));
    }

    addNearest(_SeriesKind.actual, widget.forecast.actualPoints);
    addNearest(_SeriesKind.projected, widget.forecast.projectedPoints);
    addNearest(_SeriesKind.target, widget.forecast.targetPoints);
    candidates.add(
      _Selection(_SeriesKind.limit, date, widget.period.totalPlan.toDouble()),
    );

    final maxY = _maxChartValue(widget.forecast, widget.period.totalPlan);
    double yFor(double value) => plot.bottom - value / maxY * plot.height;
    candidates.sort(
      (a, b) => (yFor(a.amount) - details.localPosition.dy).abs().compareTo(
        (yFor(b.amount) - details.localPosition.dy).abs(),
      ),
    );
    setState(() => _selection = candidates.first);
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: selection == null
              ? SizedBox(
                  key: ValueKey('hint'),
                  height: 44,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Нажмите на линию, чтобы увидеть значение',
                      style: TextStyle(
                        color: context.qestoColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              : Container(
                  key: ValueKey('${selection.kind}-${selection.date}'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _seriesColor(
                      selection.kind,
                      context.qestoColors,
                    ).withValues(alpha: 0.10),
                    borderRadius: QestoGeometry.control,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _seriesColor(
                            selection.kind,
                            context.qestoColors,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '${_seriesLabel(selection.kind)}\n${formatDate(selection.date)} · ${formatMoney(selection.amount.round(), widget.period.currency)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, 294);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _select(details, size),
              onLongPressStart: (details) => _select(
                TapDownDetails(localPosition: details.localPosition),
                size,
              ),
              child: CustomPaint(
                size: size,
                painter: _BudgetDynamicsPainter(
                  c: context.qestoColors,
                  period: widget.period,
                  forecast: widget.forecast,
                  selected: selection,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

Color _seriesColor(_SeriesKind kind, QestoSemanticColors c) => switch (kind) {
  _SeriesKind.actual || _SeriesKind.projected => c.primary,
  _SeriesKind.target => c.green,
  _SeriesKind.limit => c.secondaryText,
};

String _seriesLabel(_SeriesKind kind) => switch (kind) {
  _SeriesKind.actual => 'Фактические расходы',
  _SeriesKind.projected => 'Прогноз при текущем темпе',
  _SeriesKind.target => 'Целевая траектория',
  _SeriesKind.limit => 'План на период',
};

double _maxChartValue(BudgetForecast forecast, int totalPlan) {
  var maximum = totalPlan.toDouble();
  for (final point in [
    ...forecast.actualPoints,
    ...forecast.projectedPoints,
    ...forecast.targetPoints,
  ]) {
    maximum = math.max(maximum, point.amount);
  }
  return math.max(maximum * 1.18, 1);
}

class _BudgetDynamicsPainter extends CustomPainter {
  final QestoSemanticColors c;
  const _BudgetDynamicsPainter({
    required this.c,
    required this.period,
    required this.forecast,
    required this.selected,
  });

  final BudgetPeriod period;
  final BudgetForecast forecast;
  final _Selection? selected;

  @override
  void paint(Canvas canvas, Size size) {
    const plot = EdgeInsets.fromLTRB(51, 18, 8, 38);
    final rect = Rect.fromLTRB(
      plot.left,
      plot.top,
      size.width - plot.right,
      size.height - plot.bottom,
    );
    final maxY = _maxChartValue(forecast, period.totalPlan);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final gridPaint = Paint()
      ..color = c.border
      ..strokeWidth = 1;

    for (var index = 0; index <= 4; index++) {
      final ratio = index / 4;
      final y = rect.bottom - rect.height * ratio;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      textPainter.text = TextSpan(
        text: formatCompactMoney(maxY * ratio, period.currency),
        style: TextStyle(fontSize: 9.5, color: c.secondaryText),
      );
      textPainter.layout(maxWidth: 47);
      textPainter.paint(canvas, Offset(0, y - textPainter.height / 2));
    }

    final xLabelCount = math.min(6, period.dayCount);
    for (var index = 0; index < xLabelCount; index++) {
      final ratio = xLabelCount == 1 ? 0.0 : index / (xLabelCount - 1);
      final day = period.startDate.add(
        Duration(days: (ratio * (period.dayCount - 1)).round()),
      );
      final x = rect.left + rect.width * ratio;
      textPainter.text = TextSpan(
        text: '${day.day}',
        style: TextStyle(fontSize: 10, color: c.secondaryText),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, rect.bottom + 10),
      );
    }

    Offset pointOffset(DailyBudgetPoint point) {
      final day = point.date.difference(period.startDate).inDays;
      final x = rect.left + day / math.max(period.dayCount - 1, 1) * rect.width;
      final y = rect.bottom - point.amount / maxY * rect.height;
      return Offset(x, y);
    }

    Path pathFor(List<DailyBudgetPoint> points) {
      final path = Path();
      for (var index = 0; index < points.length; index++) {
        final offset = pointOffset(points[index]);
        if (index == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      return path;
    }

    final limitY = rect.bottom - period.totalPlan / maxY * rect.height;
    _drawDashedLine(
      canvas,
      Offset(rect.left, limitY),
      Offset(rect.right, limitY),
      Paint()
        ..color = c.secondaryText
        ..strokeWidth = 1.6,
    );
    if (forecast.targetPoints.length > 1) {
      canvas.drawPath(
        pathFor(forecast.targetPoints),
        Paint()
          ..color = c.green
          ..strokeWidth = 2.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    if (forecast.actualPoints.length > 1) {
      canvas.drawPath(
        pathFor(forecast.actualPoints),
        Paint()
          ..color = c.primary
          ..strokeWidth = 3.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (forecast.projectedPoints.length > 1) {
      final offsets = forecast.projectedPoints.map(pointOffset).toList();
      _drawDashedPath(
        canvas,
        offsets,
        Paint()
          ..color = c.primary
          ..strokeWidth = 2.6,
      );
    }

    final crossing = forecast.crossingDate;
    if (crossing != null) {
      final crossingPoint = DailyBudgetPoint(
        date: crossing,
        amount: period.totalPlan.toDouble(),
      );
      final offset = pointOffset(crossingPoint);
      _drawDashedLine(
        canvas,
        offset,
        Offset(offset.dx, rect.bottom),
        Paint()
          ..color = c.secondaryText.withValues(alpha: 0.7)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(offset, 5.5, Paint()..color = c.surface);
      canvas.drawCircle(
        offset,
        5.5,
        Paint()
          ..color = c.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      final label = formatDate(crossing);
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: c.secondaryText,
        ),
      );
      textPainter.layout();
      final pill = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(offset.dx, rect.bottom - 15),
          width: textPainter.width + 18,
          height: 28,
        ),
        const Radius.circular(14),
      );
      canvas.drawRRect(pill, Paint()..color = c.primarySoft);
      textPainter.paint(
        canvas,
        Offset(
          pill.left + 9,
          pill.top + (pill.height - textPainter.height) / 2,
        ),
      );
    }

    final selectedValue = selected;
    if (selectedValue != null) {
      final offset = pointOffset(
        DailyBudgetPoint(
          date: selectedValue.date,
          amount: selectedValue.amount,
        ),
      );
      canvas.drawCircle(offset, 5, Paint()..color = c.surface);
      canvas.drawCircle(
        offset,
        5,
        Paint()
          ..color = _seriesColor(selectedValue.kind, c)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final delta = end - start;
    final distance = delta.distance;
    if (distance == 0) return;
    final direction = delta / distance;
    var drawn = 0.0;
    while (drawn < distance) {
      final segmentEnd = math.min(drawn + 7, distance);
      canvas.drawLine(
        start + direction * drawn,
        start + direction * segmentEnd,
        paint,
      );
      drawn += 12;
    }
  }

  void _drawDashedPath(Canvas canvas, List<Offset> points, Paint paint) {
    for (var index = 0; index < points.length - 1; index++) {
      _drawDashedLine(canvas, points[index], points[index + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BudgetDynamicsPainter oldDelegate) {
    return oldDelegate.c != c ||
        oldDelegate.period.id != period.id ||
        oldDelegate.forecast != forecast ||
        oldDelegate.selected != selected;
  }
}
