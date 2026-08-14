import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';

class SpendingTrajectoryChart extends StatefulWidget {
  const SpendingTrajectoryChart({
    required this.actual,
    required this.plan,
    required this.forecast,
    required this.currency,
    super.key,
  });

  final List<double> actual;
  final List<double> plan;
  final List<double> forecast;
  final String currency;

  @override
  State<SpendingTrajectoryChart> createState() =>
      _SpendingTrajectoryChartState();
}

class _SpendingTrajectoryChartState extends State<SpendingTrajectoryChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final length = math.max(
      widget.actual.length,
      math.max(widget.plan.length, widget.forecast.length),
    );
    return Semantics(
      label: 'График фактических расходов, плана и прогноза',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const plotLeft = 44.0;
          const plotRight = 12.0;
          final plotWidth = math.max(
            1,
            constraints.maxWidth - plotLeft - plotRight,
          );
          return MouseRegion(
            onExit: (_) => setState(() => _hoveredIndex = null),
            onHover: (event) {
              if (length <= 1) return;
              final ratio = ((event.localPosition.dx - plotLeft) / plotWidth)
                  .clamp(0, 1);
              final index = (ratio * (length - 1)).round();
              if (_hoveredIndex != index) setState(() => _hoveredIndex = index);
            },
            child: SizedBox(
              height: 220,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TrajectoryPainter(
                        actual: widget.actual,
                        plan: widget.plan,
                        forecast: widget.forecast,
                        hoveredIndex: _hoveredIndex,
                      ),
                    ),
                  ),
                  if (_hoveredIndex case final index?)
                    Positioned(
                      left: _tooltipLeft(index, length, constraints.maxWidth),
                      top: 8,
                      child: _TrajectoryTooltip(
                        day: index + 1,
                        actual: _valueAt(widget.actual, index),
                        plan: _valueAt(widget.plan, index),
                        currency: widget.currency,
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
    final x = 44 + (width - 56) * (length <= 1 ? 0 : index / (length - 1));
    return (x - 76).clamp(4, math.max(4, width - 156));
  }

  double? _valueAt(List<double> values, int index) =>
      values.isEmpty || index >= values.length ? null : values[index];
}

class _TrajectoryTooltip extends StatelessWidget {
  const _TrajectoryTooltip({
    required this.day,
    required this.actual,
    required this.plan,
    required this.currency,
  });

  final int day;
  final double? actual;
  final double? plan;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF172033),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 12),
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$day число',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Факт: ${actual == null ? '—' : formatMoney(actual!.round(), currency)}',
              ),
              Text(
                'План: ${plan == null ? '—' : formatMoney(plan!.round(), currency)}',
              ),
              if (actual != null && plan != null)
                Text(
                  'Разница: ${formatMoney((actual! - plan!).round(), currency, showSign: true)}',
                  style: TextStyle(
                    color: actual! <= plan!
                        ? const Color(0xFF84E397)
                        : const Color(0xFFFF9A91),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  const _TrajectoryPainter({
    required this.actual,
    required this.plan,
    required this.forecast,
    required this.hoveredIndex,
  });

  final List<double> actual;
  final List<double> plan;
  final List<double> forecast;
  final int? hoveredIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0;
    const top = 18.0;
    const right = 12.0;
    const bottom = 28.0;
    final rect = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final values = [...actual, ...plan, ...forecast];
    final maxValue = values.isEmpty
        ? 1.0
        : math.max(1.0, values.reduce(math.max) * 1.12);
    final grid = Paint()..color = const Color(0xFFE9EDF4);
    for (var i = 0; i <= 4; i++) {
      final y = rect.bottom - rect.height * i / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
      _label(
        canvas,
        formatCompactMoney(maxValue * i / 4, 'RUB'),
        Offset(0, y - 7),
        maxWidth: 40,
      );
    }
    final length = math.max(
      actual.length,
      math.max(plan.length, forecast.length),
    );
    if (length == 0) return;
    for (final day in [1, 7, 14, 21, 28, length]) {
      if (day > length) continue;
      final x = _x(day - 1, length, rect);
      _label(canvas, '$day', Offset(x - 8, rect.bottom + 8), maxWidth: 20);
    }
    _drawSeries(
      canvas,
      plan,
      length,
      rect,
      maxValue,
      const Color(0xFFBBC3D1),
      dashed: true,
      width: 1.5,
    );
    _drawSeries(
      canvas,
      forecast,
      length,
      rect,
      maxValue,
      QestoColors.purple.withValues(alpha: 0.75),
      dashed: true,
      width: 2,
    );
    _drawSeries(
      canvas,
      actual,
      length,
      rect,
      maxValue,
      QestoColors.primary,
      width: 2.7,
      fill: true,
    );
    if (hoveredIndex case final index?) {
      final x = _x(index, length, rect);
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        Paint()..color = QestoColors.text.withValues(alpha: 0.17),
      );
      if (index < actual.length) {
        final y = _y(actual[index], rect, maxValue);
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = Colors.white);
        canvas.drawCircle(
          Offset(x, y),
          3,
          Paint()..color = QestoColors.primary,
        );
      }
    }
  }

  void _drawSeries(
    Canvas canvas,
    List<double> values,
    int length,
    Rect rect,
    double maxValue,
    Color color, {
    bool dashed = false,
    bool fill = false,
    double width = 2,
  }) {
    if (values.isEmpty) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(_x(i, length, rect), _y(values[i], rect, maxValue));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    if (fill && values.length > 1) {
      final area = Path.from(path)
        ..lineTo(_x(values.length - 1, length, rect), rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 6, metric.length)),
          paint,
        );
        distance += 10;
      }
    }
  }

  double _x(int index, int length, Rect rect) =>
      length <= 1 ? rect.left : rect.left + rect.width * index / (length - 1);

  double _y(double value, Rect rect, double maxValue) =>
      rect.bottom - rect.height * value / maxValue;

  void _label(
    Canvas canvas,
    String value,
    Offset offset, {
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(color: QestoColors.secondaryText, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter oldDelegate) =>
      oldDelegate.actual != actual ||
      oldDelegate.plan != plan ||
      oldDelegate.forecast != forecast ||
      oldDelegate.hoveredIndex != hoveredIndex;
}

class DesktopCashFlowPoint {
  const DesktopCashFlowPoint({
    required this.label,
    required this.income,
    required this.expenses,
  });

  final String label;
  final int income;
  final int expenses;
  int get net => income - expenses;
}

class CashFlowBarChart extends StatefulWidget {
  const CashFlowBarChart({
    required this.points,
    required this.currency,
    super.key,
  });

  final List<DesktopCashFlowPoint> points;
  final String currency;

  @override
  State<CashFlowBarChart> createState() => _CashFlowBarChartState();
}

class _CashFlowBarChartState extends State<CashFlowBarChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => MouseRegion(
        onExit: (_) => setState(() => _hoveredIndex = null),
        onHover: (event) {
          if (widget.points.isEmpty) return;
          final x = (event.localPosition.dx - 44).clamp(
            0,
            math.max(1, constraints.maxWidth - 56),
          );
          final index =
              (x /
                      math.max(1, constraints.maxWidth - 56) *
                      widget.points.length)
                  .floor()
                  .clamp(0, widget.points.length - 1);
          if (_hoveredIndex != index) setState(() => _hoveredIndex = index);
        },
        child: SizedBox(
          height: 230,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CashFlowPainter(
                    points: widget.points,
                    hoveredIndex: _hoveredIndex,
                  ),
                ),
              ),
              if (_hoveredIndex case final index?)
                Positioned(
                  top: 7,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF172033),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.points[index].label,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Доходы: ${formatMoney(widget.points[index].income, widget.currency)}',
                          ),
                          Text(
                            'Расходы: ${formatMoney(widget.points[index].expenses, widget.currency)}',
                          ),
                          Text(
                            'Итого: ${formatMoney(widget.points[index].net, widget.currency, showSign: true)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CashFlowPainter extends CustomPainter {
  const _CashFlowPainter({required this.points, required this.hoveredIndex});

  final List<DesktopCashFlowPoint> points;
  final int? hoveredIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 44.0;
    const right = 12.0;
    const top = 18.0;
    const bottom = 30.0;
    final rect = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final maxAbs = points
        .map((point) => point.net.abs())
        .fold<int>(1, math.max)
        .toDouble();
    final zeroY = rect.center.dy;
    final gridPaint = Paint()..color = const Color(0xFFE9EDF4);
    for (var i = 0; i <= 4; i++) {
      final y = rect.top + rect.height * i / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }
    canvas.drawLine(
      Offset(rect.left, zeroY),
      Offset(rect.right, zeroY),
      Paint()..color = const Color(0xFFCBD2DE),
    );
    final slot = rect.width / points.length;
    final barWidth = math.min(34.0, slot * 0.48);
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final x = rect.left + slot * index + slot / 2;
      final height = rect.height / 2 * point.net.abs() / maxAbs;
      final barRect = point.net >= 0
          ? Rect.fromLTWH(x - barWidth / 2, zeroY - height, barWidth, height)
          : Rect.fromLTWH(x - barWidth / 2, zeroY, barWidth, height);
      final color = point.net >= 0
          ? QestoColors.positive
          : QestoColors.negative;
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(5)),
        Paint()
          ..color = index == hoveredIndex
              ? color
              : color.withValues(alpha: 0.84),
      );
      final label = TextPainter(
        text: TextSpan(
          text: point.label,
          style: const TextStyle(
            color: QestoColors.secondaryText,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slot);
      label.paint(canvas, Offset(x - label.width / 2, rect.bottom + 9));
    }
  }

  @override
  bool shouldRepaint(covariant _CashFlowPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.hoveredIndex != hoveredIndex;
}

class DesktopSparkline extends StatelessWidget {
  const DesktopSparkline({
    required this.values,
    this.color = QestoColors.primary,
    super.key,
  });

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SparklinePainter(values, color),
    size: const Size(double.infinity, 42),
  );
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1.0, maxValue - minValue);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] - minValue) / range * size.height;
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
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
