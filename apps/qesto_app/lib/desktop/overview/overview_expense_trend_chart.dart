import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import 'desktop_overview_data.dart';

class OverviewExpenseTrendChart extends StatefulWidget {
  const OverviewExpenseTrendChart({
    required this.points,
    required this.currency,
    required this.granularity,
    this.height = 285,
    super.key,
  });

  final List<OverviewTrendPoint> points;
  final String currency;
  final OverviewTrendGranularity granularity;
  final double height;

  @override
  State<OverviewExpenseTrendChart> createState() =>
      _OverviewExpenseTrendChartState();
}

class _OverviewExpenseTrendChartState extends State<OverviewExpenseTrendChart> {
  int? _hoveredIndex;

  List<OverviewTrendPoint> get _visiblePoints {
    if (widget.granularity == OverviewTrendGranularity.days ||
        widget.points.length <= 8) {
      return widget.points;
    }
    final values = <OverviewTrendPoint>[];
    for (var index = 6; index < widget.points.length; index += 7) {
      values.add(widget.points[index]);
    }
    if (values.isEmpty || values.last.date != widget.points.last.date) {
      values.add(widget.points.last);
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final points = _visiblePoints;
    if (points.isEmpty || points.every((item) => item.amount == 0)) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'Расходов за выбранный период пока нет',
            style: TextStyle(color: QestoColors.secondaryText, fontSize: 13),
          ),
        ),
      );
    }
    return Semantics(
      label: 'График расходов за выбранный период',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const left = 54.0;
          const right = 16.0;
          final width = math.max(1, constraints.maxWidth - left - right);
          return MouseRegion(
            onExit: (_) => setState(() => _hoveredIndex = null),
            onHover: (event) {
              final ratio = ((event.localPosition.dx - left) / width).clamp(
                0,
                1,
              );
              final index = points.length == 1
                  ? 0
                  : (ratio * (points.length - 1)).round();
              if (index != _hoveredIndex) {
                setState(() => _hoveredIndex = index);
              }
            },
            child: SizedBox(
              height: widget.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ExpenseTrendPainter(
                        points: points,
                        hoveredIndex: _hoveredIndex,
                        currency: widget.currency,
                      ),
                    ),
                  ),
                  if (_hoveredIndex case final index?)
                    Positioned(
                      top: 12,
                      left: _tooltipLeft(
                        index,
                        points.length,
                        constraints.maxWidth,
                      ),
                      child: IgnorePointer(
                        child: _TrendTooltip(
                          point: points[index],
                          currency: widget.currency,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _tooltipLeft(int index, int length, double width) {
    final x = 54 + (width - 70) * (length <= 1 ? 0 : index / (length - 1));
    return (x - 77).clamp(4, math.max(4, width - 158));
  }
}

class _TrendTooltip extends StatelessWidget {
  const _TrendTooltip({required this.point, required this.currency});

  final OverviewTrendPoint point;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 154,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(11),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14)],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatDate(point.date),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: QestoColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Расходы ${formatMoney(point.amount, currency)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseTrendPainter extends CustomPainter {
  const _ExpenseTrendPainter({
    required this.points,
    required this.hoveredIndex,
    required this.currency,
  });

  final List<OverviewTrendPoint> points;
  final int? hoveredIndex;
  final String currency;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 54.0;
    const top = 24.0;
    const right = 16.0;
    const bottom = 35.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final maximum = math.max(
      1,
      points.fold<int>(0, (value, item) => math.max(value, item.amount)),
    );
    final maxValue = maximum * 1.1;
    final gridPaint = Paint()
      ..color = QestoColors.border
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = plot.bottom - plot.height * index / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _paintText(
        canvas,
        formatCompactMoney(maxValue * index / 4, currency),
        Offset(0, y - 7),
        48,
        const TextStyle(color: QestoColors.secondaryText, fontSize: 9),
      );
    }

    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = Offset(
        _x(index, plot),
        plot.bottom - plot.height * points[index].amount / maxValue,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    if (points.length > 1) {
      final fill = Path.from(path)
        ..lineTo(plot.right, plot.bottom)
        ..lineTo(plot.left, plot.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x333478F6), Color(0x003478F6)],
          ).createShader(plot),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = QestoColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final labelIndices = <int>{0, points.length ~/ 2, points.length - 1};
    for (final index in labelIndices) {
      final point = points[index];
      _paintText(
        canvas,
        formatDate(point.date),
        Offset(_x(index, plot) - 28, plot.bottom + 10),
        56,
        const TextStyle(color: QestoColors.secondaryText, fontSize: 9),
        align: TextAlign.center,
      );
    }

    if (hoveredIndex case final index?) {
      final x = _x(index, plot);
      final y = plot.bottom - plot.height * points[index].amount / maxValue;
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()..color = QestoColors.text.withValues(alpha: 0.15),
      );
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, y),
        3.4,
        Paint()..color = QestoColors.primary,
      );
    }
  }

  double _x(int index, Rect plot) => points.length <= 1
      ? plot.left
      : plot.left + plot.width * index / (points.length - 1);

  void _paintText(
    Canvas canvas,
    String value,
    Offset offset,
    double width,
    TextStyle style, {
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ExpenseTrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.hoveredIndex != hoveredIndex ||
      oldDelegate.currency != currency;
}
