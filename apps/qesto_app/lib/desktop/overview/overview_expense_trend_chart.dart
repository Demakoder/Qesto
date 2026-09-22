import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../design_system/qesto_window.dart';
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
    final colors = context.qestoColors;
    final scaler = MediaQuery.textScalerOf(context);
    return QestoChartSurface(
      child: SizedBox(
        height: widget.height,
        child: points.isEmpty || points.every((p) => p.amount == 0)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Расходов за выбранный период пока нет',
                    style: QestoTypography.caption.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              )
            : Semantics(
                label: 'График расходов за выбранный период',
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final geometry = OverviewTrendGeometry.compute(
                      constraints.biggest,
                      points,
                      widget.currency,
                      scaler,
                    );
                    final selected = _hoveredIndex?.clamp(0, points.length - 1);
                    void select(Offset position) {
                      final index = geometry.indexAt(
                        position.dx,
                        points.length,
                      );
                      if (index != _hoveredIndex) {
                        setState(() => _hoveredIndex = index);
                      }
                    }

                    final tooltipWidth = math.min(
                      250.0,
                      math.max(1.0, constraints.maxWidth - 16),
                    );
                    final tooltipLeft = selected == null
                        ? 0.0
                        : (geometry.x(selected, points.length) -
                                  tooltipWidth / 2)
                              .clamp(
                                8.0,
                                math.max(
                                  8.0,
                                  constraints.maxWidth - tooltipWidth - 8,
                                ),
                              );
                    return Listener(
                      onPointerDown: (event) => select(event.localPosition),
                      child: MouseRegion(
                        onExit: (_) => setState(() => _hoveredIndex = null),
                        onHover: (event) => select(event.localPosition),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _ExpenseTrendPainter(
                                  points: points,
                                  hoveredIndex: selected,
                                  currency: widget.currency,
                                  geometry: geometry,
                                  colors: colors,
                                  scaler: scaler,
                                ),
                              ),
                            ),
                            if (selected != null)
                              Positioned(
                                top: 8,
                                left: tooltipLeft.toDouble(),
                                width: tooltipWidth,
                                child: IgnorePointer(
                                  child: _TrendTooltip(
                                    point: points[selected],
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
              ),
      ),
    );
  }
}

/// Canvas margins and hit testing share exactly the same local geometry.
/// Labels are measured with the selected font/text scale, not clipped to 48px.
class OverviewTrendGeometry {
  const OverviewTrendGeometry({
    required this.size,
    required this.plot,
    required this.maximum,
    required this.yLabels,
    required this.xLabels,
  });
  final Size size;
  final Rect plot;
  final double maximum;
  final List<String> yLabels;
  final Map<int, String> xLabels;

  static TextPainter label(String text, TextScaler scaler, Color color) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: QestoTypography.metadata.copyWith(fontSize: 10, color: color),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();

  static OverviewTrendGeometry compute(
    Size size,
    List<OverviewTrendPoint> points,
    String currency,
    TextScaler scaler,
  ) {
    final maximum =
        math.max(
          1,
          points.fold<int>(0, (value, item) => math.max(value, item.amount)),
        ) *
        1.1;
    final yLabels = List.generate(
      5,
      (i) => formatCompactMoney(maximum * i / 4, currency),
    );
    final xLabels = {
      if (points.isNotEmpty)
        for (final i in <int>{0, points.length ~/ 2, points.length - 1})
          i: formatDate(points[i].date),
    };
    final yWidth = yLabels
        .map((s) => label(s, scaler, Colors.black).width)
        .reduce(math.max);
    final labelHeight = label('0 ₽', scaler, Colors.black).height;
    final left = yWidth + 16;
    final top = labelHeight / 2 + 12;
    final bottom = labelHeight + 18;
    return OverviewTrendGeometry(
      size: size,
      plot: Rect.fromLTRB(
        left,
        top,
        math.max(left + 1, size.width - 12),
        math.max(top + 1, size.height - bottom),
      ),
      maximum: maximum,
      yLabels: yLabels,
      xLabels: xLabels,
    );
  }

  double x(int index, int length) =>
      plot.left + plot.width * (length <= 1 ? .5 : index / (length - 1));
  int indexAt(double dx, int length) => length <= 1
      ? 0
      : (((dx - plot.left) / plot.width).clamp(0, 1) * (length - 1)).round();
  Rect xLabelBounds(int index, int length, TextScaler scaler) {
    final painter = label(xLabels[index]!, scaler, Colors.black);
    final left = (x(index, length) - painter.width / 2).clamp(
      4.0,
      math.max(4.0, size.width - painter.width - 4),
    );
    return Rect.fromLTWH(
      left.toDouble(),
      plot.bottom + 8,
      painter.width,
      painter.height,
    );
  }
}

class _TrendTooltip extends StatelessWidget {
  const _TrendTooltip({required this.point, required this.currency});
  final OverviewTrendPoint point;
  final String currency;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.qestoColors.chartTooltip,
      border: Border.all(color: context.qestoColors.border),
      borderRadius: QestoGeometry.control,
      boxShadow: QestoGeometry.focusShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatDate(point.date),
          style: QestoTypography.uiStrong.copyWith(
            color: context.qestoColors.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Расходы ${formatMoney(point.amount, currency)}',
          style: QestoTypography.table.copyWith(
            color: context.qestoColors.negative,
          ),
        ),
      ],
    ),
  );
}

class _ExpenseTrendPainter extends CustomPainter {
  const _ExpenseTrendPainter({
    required this.points,
    required this.hoveredIndex,
    required this.currency,
    required this.geometry,
    required this.colors,
    required this.scaler,
  });
  final List<OverviewTrendPoint> points;
  final int? hoveredIndex;
  final String currency;
  final OverviewTrendGeometry geometry;
  final QestoSemanticColors colors;
  final TextScaler scaler;
  @override
  void paint(Canvas canvas, Size size) {
    final plot = geometry.plot;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = colors.chartGrid
          ..strokeWidth = .7,
      );
      final label = OverviewTrendGeometry.label(
        geometry.yLabels[i],
        scaler,
        colors.chartAxis,
      );
      label.paint(
        canvas,
        Offset(plot.left - label.width - 8, y - label.height / 2),
      );
    }
    final path = Path();
    Offset pointAt(int i) => Offset(
      geometry.x(i, points.length),
      plot.bottom - plot.height * points[i].amount / geometry.maximum,
    );
    for (var i = 0; i < points.length; i++) {
      final point = pointAt(i);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    // Clip only the data plot, never the axis labels or tooltip overlay.
    canvas.save();
    canvas.clipRect(plot.inflate(5));
    if (points.length > 1) {
      final fill = Path.from(path)
        ..lineTo(plot.right, plot.bottom)
        ..lineTo(plot.left, plot.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.negative.withValues(alpha: .12),
              colors.negative.withValues(alpha: .01),
            ],
          ).createShader(plot),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = colors.negative
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      canvas.drawCircle(pointAt(0), 3, Paint()..color = colors.negative);
    }
    if (hoveredIndex case final index?) {
      final point = pointAt(index);
      canvas.drawLine(
        Offset(point.dx, plot.top),
        Offset(point.dx, plot.bottom),
        Paint()..color = colors.secondaryText.withValues(alpha: .45),
      );
      canvas.drawCircle(point, 5, Paint()..color = colors.surface);
      canvas.drawCircle(point, 3.4, Paint()..color = colors.negative);
    }
    canvas.restore();
    for (final entry in geometry.xLabels.entries) {
      final label = OverviewTrendGeometry.label(
        entry.value,
        scaler,
        colors.chartAxis,
      );
      label.paint(
        canvas,
        geometry.xLabelBounds(entry.key, points.length, scaler).topLeft,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExpenseTrendPainter old) =>
      old.points != points ||
      old.hoveredIndex != hoveredIndex ||
      old.currency != currency ||
      old.geometry.size != geometry.size ||
      old.colors != colors ||
      old.scaler != scaler;
}
