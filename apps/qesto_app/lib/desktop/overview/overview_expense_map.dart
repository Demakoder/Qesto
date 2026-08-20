import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import 'desktop_overview_data.dart';

class OverviewExpenseMap extends StatefulWidget {
  const OverviewExpenseMap({required this.data, super.key});

  final OverviewFlowData data;

  @override
  State<OverviewExpenseMap> createState() => _OverviewExpenseMapState();
}

class _OverviewExpenseMapState extends State<OverviewExpenseMap> {
  String? _hoveredId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Карта расходов: доходы ${widget.data.income}, расходы ${widget.data.expenses}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final height = math
              .max(
                compact ? 390.0 : 430.0,
                widget.data.branches.length * 62 + 92,
              )
              .toDouble();
          final geometry = _FlowGeometry.compute(
            Size(constraints.maxWidth, height),
            widget.data,
          );
          final hovered = geometry.hits
              .where((item) => item.id == _hoveredId)
              .firstOrNull;
          return MouseRegion(
            onExit: (_) => setState(() => _hoveredId = null),
            onHover: (event) {
              final hit = geometry.hits
                  .where((item) => item.contains(event.localPosition))
                  .lastOrNull;
              if (hit?.id != _hoveredId) {
                setState(() => _hoveredId = hit?.id);
              }
            },
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ExpenseMapPainter(
                        data: widget.data,
                        geometry: geometry,
                        hoveredId: _hoveredId,
                        compact: compact,
                      ),
                    ),
                  ),
                  if (hovered != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IgnorePointer(
                        child: _FlowTooltip(
                          hit: hovered,
                          total: widget.data.total,
                          currency: widget.data.currency,
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
}

class _FlowTooltip extends StatelessWidget {
  const _FlowTooltip({
    required this.hit,
    required this.total,
    required this.currency,
  });

  final _FlowHit hit;
  final int total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final percent = total <= 0 ? 0.0 : hit.amount / total;
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(11),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16)],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hit.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatMoney(hit.amount, currency)} · ${formatPercent(percent, decimals: 1)}',
              style: const TextStyle(color: Color(0xFFD3DBEA)),
            ),
            if (hit.transactionCount > 0)
              Text(
                _operationCount(hit.transactionCount),
                style: const TextStyle(color: Color(0xFF9FAAC0)),
              ),
          ],
        ),
      ),
    );
  }

  static String _operationCount(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    final suffix = mod10 == 1 && mod100 != 11
        ? 'операция'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
        ? 'операции'
        : 'операций';
    return '$count $suffix';
  }
}

class _FlowGeometry {
  const _FlowGeometry({
    required this.sourceRects,
    required this.rootRect,
    required this.branchRects,
    required this.destinationRects,
    required this.sourcePaths,
    required this.branchPaths,
    required this.destinationPaths,
    required this.hits,
  });

  final List<Rect> sourceRects;
  final Rect rootRect;
  final List<Rect> branchRects;
  final List<List<Rect>> destinationRects;
  final List<Path> sourcePaths;
  final List<Path> branchPaths;
  final List<List<Path>> destinationPaths;
  final List<_FlowHit> hits;

  static _FlowGeometry compute(Size size, OverviewFlowData data) {
    const top = 40.0;
    const bottom = 22.0;
    const gap = 9.0;
    const barWidth = 9.0;
    final sourceX = size.width * 0.18;
    final rootX = size.width * 0.37;
    final branchX = size.width * 0.61;
    final destinationX = size.width * 0.84;
    final branchCount = math.max(1, data.branches.length);
    final flowHeight = math.max(
      1.0,
      size.height - top - bottom - gap * (branchCount - 1),
    );
    final outerHeight = flowHeight + gap * (branchCount - 1);
    final rootTop = top + (outerHeight - flowHeight) / 2;
    final root = Rect.fromLTWH(rootX, rootTop, barWidth, flowHeight);

    final sourceRects = <Rect>[];
    final sourcePaths = <Path>[];
    final branchRects = <Rect>[];
    final branchPaths = <Path>[];
    final destinationRects = <List<Rect>>[];
    final destinationPaths = <List<Path>>[];
    final hits = <_FlowHit>[];

    var sourceY = root.top;
    var rootSourceY = root.top;
    for (final source in data.sources) {
      final height = flowHeight * source.amount / math.max(1, data.total);
      final sourceRect = Rect.fromLTWH(sourceX, sourceY, barWidth, height);
      final rootSegment = Rect.fromLTWH(
        root.left,
        rootSourceY,
        barWidth,
        height,
      );
      final path = _ribbonPath(sourceRect, rootSegment);
      sourceRects.add(sourceRect);
      sourcePaths.add(path);
      hits.add(
        _FlowHit(
          id: source.id,
          label: source.label,
          amount: source.amount,
          transactionCount: source.transactionCount,
          rect: Rect.fromLTRB(
            0,
            sourceRect.top - 2,
            root.left,
            sourceRect.bottom + 2,
          ),
          path: path,
        ),
      );
      sourceY += height;
      rootSourceY += height;
    }

    var branchY = top;
    var rootBranchY = root.top;
    for (var index = 0; index < data.branches.length; index++) {
      final branch = data.branches[index];
      final height = flowHeight * branch.amount / math.max(1, data.total);
      final branchRect = Rect.fromLTWH(branchX, branchY, barWidth, height);
      final rootSegment = Rect.fromLTWH(
        root.left,
        rootBranchY,
        barWidth,
        height,
      );
      final path = _ribbonPath(rootSegment, branchRect);
      branchRects.add(branchRect);
      branchPaths.add(path);
      hits.add(
        _FlowHit(
          id: 'branch-${branch.id}',
          label: branch.label,
          amount: branch.amount,
          transactionCount: branch.destinations.fold<int>(
            0,
            (sum, item) => sum + item.transactionCount,
          ),
          rect: Rect.fromLTRB(
            root.right,
            branchRect.top - 2,
            destinationX,
            branchRect.bottom + 2,
          ),
          path: path,
        ),
      );

      final rects = <Rect>[];
      final paths = <Path>[];
      var destinationY = branchRect.top;
      var branchSegmentY = branchRect.top;
      for (final destination in branch.destinations) {
        final destinationHeight = branch.amount <= 0
            ? 0.0
            : branchRect.height * destination.amount / branch.amount;
        final destinationRect = Rect.fromLTWH(
          destinationX,
          destinationY,
          7,
          destinationHeight,
        );
        final branchSegment = Rect.fromLTWH(
          branchRect.left,
          branchSegmentY,
          barWidth,
          destinationHeight,
        );
        final destinationPath = _ribbonPath(branchSegment, destinationRect);
        rects.add(destinationRect);
        paths.add(destinationPath);
        hits.add(
          _FlowHit(
            id: destination.id,
            label: destination.label,
            amount: destination.amount,
            transactionCount: destination.transactionCount,
            rect: Rect.fromLTRB(
              branchRect.right,
              destinationRect.top - 2,
              size.width,
              destinationRect.bottom + 2,
            ),
            path: destinationPath,
          ),
        );
        destinationY += destinationHeight;
        branchSegmentY += destinationHeight;
      }
      destinationRects.add(rects);
      destinationPaths.add(paths);
      branchY += height + gap;
      rootBranchY += height;
    }

    hits.add(
      _FlowHit(
        id: 'root',
        label: data.total == data.income ? 'Доходы' : 'Деньги периода',
        amount: data.total,
        transactionCount: data.sources.fold<int>(
          0,
          (sum, item) => sum + item.transactionCount,
        ),
        rect: root.inflate(12),
      ),
    );
    return _FlowGeometry(
      sourceRects: sourceRects,
      rootRect: root,
      branchRects: branchRects,
      destinationRects: destinationRects,
      sourcePaths: sourcePaths,
      branchPaths: branchPaths,
      destinationPaths: destinationPaths,
      hits: hits,
    );
  }

  static Path _ribbonPath(Rect source, Rect target) {
    final distance = target.left - source.right;
    return Path()
      ..moveTo(source.right, source.top)
      ..cubicTo(
        source.right + distance * 0.45,
        source.top,
        target.left - distance * 0.45,
        target.top,
        target.left,
        target.top,
      )
      ..lineTo(target.left, target.bottom)
      ..cubicTo(
        target.left - distance * 0.45,
        target.bottom,
        source.right + distance * 0.45,
        source.bottom,
        source.right,
        source.bottom,
      )
      ..close();
  }
}

class _FlowHit {
  const _FlowHit({
    required this.id,
    required this.label,
    required this.amount,
    required this.transactionCount,
    required this.rect,
    this.path,
  });

  final String id;
  final String label;
  final int amount;
  final int transactionCount;
  final Rect rect;
  final Path? path;

  bool contains(Offset point) =>
      rect.contains(point) || (path?.contains(point) ?? false);
}

class _ExpenseMapPainter extends CustomPainter {
  const _ExpenseMapPainter({
    required this.data,
    required this.geometry,
    required this.hoveredId,
    required this.compact,
  });

  final OverviewFlowData data;
  final _FlowGeometry geometry;
  final String? hoveredId;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    _columnLabel(canvas, 'ИСТОЧНИКИ', const Offset(0, 6), size.width * 0.18);
    _columnLabel(
      canvas,
      'ОБЩИЙ ПОТОК',
      Offset(size.width * 0.31, 6),
      size.width * 0.2,
    );
    _columnLabel(
      canvas,
      'НАПРАВЛЕНИЯ',
      Offset(size.width * 0.55, 6),
      size.width * 0.22,
    );
    if (!compact) {
      _columnLabel(
        canvas,
        'КРУПНЕЙШИЕ ОПЕРАЦИИ',
        Offset(size.width * 0.78, 6),
        size.width * 0.22,
      );
    }

    for (var index = 0; index < data.sources.length; index++) {
      final source = data.sources[index];
      final highlighted = hoveredId == null || hoveredId == source.id;
      canvas.drawPath(
        geometry.sourcePaths[index],
        Paint()
          ..color = source.color.withValues(alpha: highlighted ? 0.22 : 0.08),
      );
    }
    for (var index = 0; index < data.branches.length; index++) {
      final branch = data.branches[index];
      final branchId = 'branch-${branch.id}';
      final highlighted = hoveredId == null || hoveredId == branchId;
      canvas.drawPath(
        geometry.branchPaths[index],
        Paint()
          ..color = branch.color.withValues(alpha: highlighted ? 0.30 : 0.09),
      );
      for (
        var destinationIndex = 0;
        destinationIndex < branch.destinations.length;
        destinationIndex++
      ) {
        final destination = branch.destinations[destinationIndex];
        final destinationHighlighted =
            hoveredId == null || hoveredId == destination.id;
        canvas.drawPath(
          geometry.destinationPaths[index][destinationIndex],
          Paint()
            ..color = branch.color.withValues(
              alpha: destinationHighlighted ? 0.25 : 0.07,
            ),
        );
      }
    }

    for (var index = 0; index < data.sources.length; index++) {
      final source = data.sources[index];
      final rect = geometry.sourceRects[index];
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()..color = source.color,
      );
      if (rect.height >= 12) {
        _nodeText(
          canvas,
          source.label,
          formatMoney(source.amount, data.currency),
          Rect.fromLTRB(
            0,
            rect.center.dy - 18,
            rect.left - 8,
            rect.center.dy + 20,
          ),
          TextAlign.right,
        );
      }
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(geometry.rootRect, const Radius.circular(5)),
      Paint()..color = const Color(0xFF2A92C8),
    );
    final rootLabel = data.total == data.income ? 'Доходы' : 'Деньги периода';
    _nodeText(
      canvas,
      rootLabel,
      '${formatMoney(data.total, data.currency)} · 100%',
      Rect.fromLTRB(
        geometry.rootRect.right + 8,
        geometry.rootRect.center.dy - 20,
        size.width * 0.59,
        geometry.rootRect.center.dy + 22,
      ),
      TextAlign.left,
    );

    for (var index = 0; index < data.branches.length; index++) {
      final branch = data.branches[index];
      final rect = geometry.branchRects[index];
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()..color = branch.color,
      );
      if (rect.height >= 11) {
        _nodeText(
          canvas,
          branch.label,
          '${formatMoney(branch.amount, data.currency)} · ${formatPercent(branch.amount / data.total, decimals: 1)}',
          Rect.fromLTRB(
            rect.right + 8,
            rect.center.dy - 18,
            size.width * 0.825,
            rect.center.dy + 20,
          ),
          TextAlign.left,
          compact: true,
        );
      }

      for (
        var destinationIndex = 0;
        destinationIndex < branch.destinations.length;
        destinationIndex++
      ) {
        final destination = branch.destinations[destinationIndex];
        final destinationRect =
            geometry.destinationRects[index][destinationIndex];
        canvas.drawRRect(
          RRect.fromRectAndRadius(destinationRect, const Radius.circular(4)),
          Paint()..color = branch.color.withValues(alpha: 0.92),
        );
        if (!compact && destinationRect.height >= 12) {
          _nodeText(
            canvas,
            destination.label,
            formatMoney(destination.amount, data.currency),
            Rect.fromLTRB(
              destinationRect.right + 6,
              destinationRect.center.dy - 17,
              size.width,
              destinationRect.center.dy + 19,
            ),
            TextAlign.left,
            compact: true,
          );
        }
      }
    }
  }

  void _columnLabel(Canvas canvas, String text, Offset offset, double width) {
    _paintText(
      canvas,
      text,
      offset,
      width,
      const TextStyle(
        color: QestoColors.secondaryText,
        fontSize: 8,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.55,
      ),
    );
  }

  void _nodeText(
    Canvas canvas,
    String title,
    String value,
    Rect rect,
    TextAlign align, {
    bool compact = false,
  }) {
    _paintText(
      canvas,
      title,
      rect.topLeft,
      rect.width,
      TextStyle(
        color: QestoColors.text,
        fontSize: compact ? 8.5 : 9.5,
        fontWeight: FontWeight.w800,
      ),
      align: align,
    );
    _paintText(
      canvas,
      value,
      Offset(rect.left, rect.top + (compact ? 13 : 15)),
      rect.width,
      TextStyle(
        color: QestoColors.secondaryText,
        fontSize: compact ? 7.5 : 8.5,
        fontWeight: FontWeight.w600,
      ),
      align: align,
    );
  }

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
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(1, width));
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ExpenseMapPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.geometry != geometry ||
      oldDelegate.hoveredId != hoveredId ||
      oldDelegate.compact != compact;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
