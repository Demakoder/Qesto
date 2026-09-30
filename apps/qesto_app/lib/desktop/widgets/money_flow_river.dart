import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../features/budget/widgets/budget_category_icon.dart';

class MoneyFlowPurchase {
  const MoneyFlowPurchase({required this.label, required this.amount});

  final String label;
  final int amount;
}

class MoneyFlowCategory {
  const MoneyFlowCategory({
    required this.id,
    required this.label,
    required this.amount,
    required this.color,
    required this.iconKey,
    required this.purchases,
    this.isRemainder = false,
  });

  final String id;
  final String label;
  final int amount;
  final Color color;
  final String iconKey;
  final List<MoneyFlowPurchase> purchases;
  final bool isRemainder;
}

/// Interactive three-level money flow: available income -> categories ->
/// largest purchases. It is intentionally a Qesto view model; Synoball remains
/// the canonical source and is not coupled to chart geometry.
class MoneyFlowRiver extends StatefulWidget {
  const MoneyFlowRiver({
    required this.income,
    required this.expenses,
    required this.categories,
    required this.currency,
    this.hideAmounts = false,
    this.onNodeTap,
    super.key,
  });

  final int income;
  final int expenses;
  final List<MoneyFlowCategory> categories;
  final String currency;
  final bool hideAmounts;
  final ValueChanged<String>? onNodeTap;

  @override
  State<MoneyFlowRiver> createState() => _MoneyFlowRiverState();
}

class _MoneyFlowRiverState extends State<MoneyFlowRiver> {
  String? _hoveredId;

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Text(
            'Недостаточно операций для построения потока',
            style: TextStyle(color: context.qestoColors.secondaryText),
          ),
        ),
      );
    }

    return Semantics(
      label:
          'Река денег: доход ${widget.income}, расходы ${widget.expenses}, категорий ${widget.categories.length}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 850;
          final height = moneyFlowRiverHeight(
            widget.categories,
            compact: compact,
          );
          final layout = _MoneyFlowLayout.compute(
            Size(constraints.maxWidth, height),
            widget.categories,
          );
          final hovered = layout.hits
              .where((item) => item.id == _hoveredId)
              .firstOrNull;
          return Listener(
            onPointerDown: (event) {
              final hit = layout.hits
                  .where((item) => item.hitRect.contains(event.localPosition))
                  .lastOrNull;
              setState(() => _hoveredId = hit?.id);
            },
            onPointerUp: (event) {
              final hit = layout.hits
                  .where((item) => item.hitRect.contains(event.localPosition))
                  .lastOrNull;
              if (hit != null) widget.onNodeTap?.call(hit.id);
            },
            child: MouseRegion(
              cursor: widget.onNodeTap == null
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              onExit: (_) => setState(() => _hoveredId = null),
              onHover: (event) {
                final hit = layout.hits
                    .where((item) => item.hitRect.contains(event.localPosition))
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
                        painter: _MoneyFlowPainter(
                          c: context.qestoColors,
                          layout: layout,
                          categories: widget.categories,
                          income: widget.income,
                          expenses: widget.expenses,
                          currency: widget.currency,
                          hideAmounts: widget.hideAmounts,
                          hoveredId: _hoveredId,
                          compact: compact,
                        ),
                      ),
                    ),
                    if (hovered != null)
                      Positioned(
                        right: 12,
                        top: 8,
                        child: IgnorePointer(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 260),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF171B1E),
                              borderRadius: QestoGeometry.control,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hovered.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: QestoTypography.uiFamily,
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.hideAmounts
                                      ? 'Сумма скрыта'
                                      : formatMoney(
                                          hovered.amount,
                                          widget.currency,
                                        ),
                                  style: const TextStyle(
                                    fontFamily: QestoTypography.uiFamily,
                                    color: Color(0xFFBFC9DC),
                                    fontSize: 11,
                                  ),
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
        },
      ),
    );
  }
}

/// Gives every branch the same pixels-per-unit scale. The extra height keeps
/// ordinary small categories readable without giving them an inflated flow.
@visibleForTesting
double moneyFlowRiverHeight(
  List<MoneyFlowCategory> categories, {
  required bool compact,
}) {
  final base = compact ? 410.0 : 470.0;
  final total = categories.fold<int>(0, (sum, item) => sum + item.amount);
  final smallest = categories
      .where((item) => item.amount > 0)
      .map((item) => item.amount)
      .fold<int>(0, (min, amount) => min == 0 ? amount : math.min(min, amount));
  if (smallest == 0 || total <= 0) return base;
  const chartPadding = 62.0;
  const categoryGap = 10.0;
  const readableBranch = 26.0;
  final requested =
      chartPadding +
      categoryGap * math.max(0, categories.length - 1) +
      readableBranch * total / smallest;
  return math.max(base, requested).clamp(base, 800.0);
}

/// The same financial scale is used for categories and their purchases.
@visibleForTesting
double moneyFlowThickness(int amount, int total, double flowHeight) =>
    total <= 0 || amount <= 0 ? 0 : flowHeight * amount / total;

class _MoneyFlowLayout {
  const _MoneyFlowLayout({
    required this.root,
    required this.categories,
    required this.purchases,
    required this.hits,
  });

  final Rect root;
  final List<Rect> categories;
  final List<List<Rect>> purchases;
  final List<_FlowHit> hits;

  static _MoneyFlowLayout compute(Size size, List<MoneyFlowCategory> data) {
    const top = 36.0;
    const bottom = 26.0;
    const categoryGap = 10.0;
    final total = data.fold<int>(0, (sum, item) => sum + item.amount);
    final available = math.max(
      1.0,
      size.height - top - bottom - categoryGap * (data.length - 1),
    );
    final heights = [
      for (final item in data)
        total <= 0
            ? available / data.length
            : moneyFlowThickness(item.amount, total, available),
    ];

    final rootX = size.width < 850 ? 105.0 : 135.0;
    final categoryX = size.width * (size.width < 850 ? 0.44 : 0.43);
    final purchaseX = size.width * (size.width < 850 ? 0.76 : 0.75);
    final categoryRects = <Rect>[];
    final purchaseRects = <List<Rect>>[];
    final hits = <_FlowHit>[];
    var y = top;
    for (var index = 0; index < data.length; index++) {
      final item = data[index];
      final height = heights[index];
      final rect = Rect.fromLTWH(categoryX, y, 9, height);
      categoryRects.add(rect);
      hits.add(
        _FlowHit(
          id: 'category-${item.id}',
          label: item.label,
          amount: item.amount,
          hitRect: Rect.fromLTWH(
            categoryX - 34,
            y - 3,
            math.max(170, purchaseX - categoryX - 48),
            height + 6,
          ),
        ),
      );

      final purchases = item.purchases;
      var purchaseY = y;
      final rects = <Rect>[];
      for (
        var purchaseIndex = 0;
        purchaseIndex < purchases.length;
        purchaseIndex++
      ) {
        final purchase = purchases[purchaseIndex];
        final purchaseHeight = purchaseIndex == purchases.length - 1
            ? y + height - purchaseY
            : total <= 0
            ? 0.0
            : moneyFlowThickness(purchase.amount, total, available);
        final purchaseRect = Rect.fromLTWH(
          purchaseX,
          purchaseY,
          7,
          purchaseHeight,
        );
        rects.add(purchaseRect);
        hits.add(
          _FlowHit(
            id: 'purchase-${item.id}-$purchaseIndex',
            label: purchase.label,
            amount: purchase.amount,
            hitRect: Rect.fromLTWH(
              purchaseX - 8,
              purchaseY - 2,
              size.width - purchaseX + 4,
              math.max(8, purchaseHeight + 4),
            ),
          ),
        );
        purchaseY += purchaseHeight;
      }
      purchaseRects.add(rects);
      y += height + categoryGap;
    }
    final rootHeight = heights.fold<double>(0, (sum, value) => sum + value);
    final root = Rect.fromLTWH(
      rootX,
      top + (available - rootHeight) / 2,
      11,
      rootHeight,
    );
    hits.insert(
      0,
      _FlowHit(
        id: 'root',
        label: 'Общий денежный поток',
        amount: total,
        hitRect: Rect.fromLTWH(0, top - 4, rootX + 22, root.height + 8),
      ),
    );
    return _MoneyFlowLayout(
      root: root,
      categories: categoryRects,
      purchases: purchaseRects,
      hits: hits,
    );
  }
}

class _FlowHit {
  const _FlowHit({
    required this.id,
    required this.label,
    required this.amount,
    required this.hitRect,
  });

  final String id;
  final String label;
  final int amount;
  final Rect hitRect;
}

class _MoneyFlowPainter extends CustomPainter {
  final QestoSemanticColors c;
  const _MoneyFlowPainter({
    required this.c,
    required this.layout,
    required this.categories,
    required this.income,
    required this.expenses,
    required this.currency,
    required this.hideAmounts,
    required this.hoveredId,
    required this.compact,
  });

  final _MoneyFlowLayout layout;
  final List<MoneyFlowCategory> categories;
  final int income;
  final int expenses;
  final String currency;
  final bool hideAmounts;
  final String? hoveredId;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    _columnTitle(canvas, 'ДОХОД', const Offset(0, 6));
    _columnTitle(
      canvas,
      'КАТЕГОРИИ',
      Offset(layout.categories.first.left - 34, 6),
    );
    _columnTitle(
      canvas,
      'КРУПНЕЙШИЕ ОПЕРАЦИИ',
      Offset(layout.purchases.first.firstOrNull?.left ?? size.width * 0.75, 6),
    );

    var rootY = layout.root.top;
    for (var index = 0; index < categories.length; index++) {
      final category = categories[index];
      final target = layout.categories[index];
      final sourceHeight = target.height;
      final source = Rect.fromLTWH(
        layout.root.left,
        rootY,
        layout.root.width,
        sourceHeight,
      );
      final categoryHovered = hoveredId == 'category-${category.id}';
      _ribbon(
        canvas,
        source,
        target,
        category.color.withValues(alpha: categoryHovered ? 0.48 : 0.24),
      );
      rootY += sourceHeight;

      var categoryY = target.top;
      final purchaseRects = layout.purchases[index];
      for (
        var purchaseIndex = 0;
        purchaseIndex < purchaseRects.length;
        purchaseIndex++
      ) {
        final purchaseTarget = purchaseRects[purchaseIndex];
        final purchaseSource = Rect.fromLTWH(
          target.left,
          categoryY,
          target.width,
          purchaseTarget.height,
        );
        final purchaseHovered =
            hoveredId == 'purchase-${category.id}-$purchaseIndex';
        _ribbon(
          canvas,
          purchaseSource,
          purchaseTarget,
          category.color.withValues(alpha: purchaseHovered ? 0.5 : 0.22),
        );
        categoryY += purchaseTarget.height;
      }
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(layout.root, const Radius.circular(6)),
      Paint()..color = c.primary,
    );
    final deficit = math.max(0, expenses - income);
    _text(
      canvas,
      'Доступно',
      Offset(0, layout.root.center.dy - 25),
      width: layout.root.left - 12,
      style: TextStyle(
        fontFamily: QestoTypography.uiFamily,
        color: c.text,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      align: TextAlign.right,
    );
    _text(
      canvas,
      hideAmounts ? '••••' : formatMoney(math.max(income, expenses), currency),
      Offset(0, layout.root.center.dy - 6),
      width: layout.root.left - 12,
      style: TextStyle(
        fontFamily: QestoTypography.uiFamily,
        color: c.text,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
      align: TextAlign.right,
    );
    if (deficit > 0) {
      _text(
        canvas,
        hideAmounts
            ? 'с учётом резерва'
            : '+${formatMoney(deficit, currency)} из резерва',
        Offset(0, layout.root.center.dy + 17),
        width: layout.root.left - 12,
        style: TextStyle(
          fontFamily: QestoTypography.uiFamily,
          color: c.negative,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
        align: TextAlign.right,
      );
    }

    for (var index = 0; index < categories.length; index++) {
      final category = categories[index];
      final rect = layout.categories[index];
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()..color = category.color,
      );
      final icon = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(
            budgetCategoryIcon(category.iconKey).codePoint,
          ),
          style: TextStyle(
            fontFamily: budgetCategoryIcon(category.iconKey).fontFamily,
            package: budgetCategoryIcon(category.iconKey).fontPackage,
            color: category.color,
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      icon.paint(canvas, Offset(rect.left + 15, rect.center.dy - 16));
      if (rect.height >= 20) {
        _text(
          canvas,
          category.label,
          Offset(rect.left + 35, rect.center.dy - 18),
          width: math.max(
            70,
            (layout.purchases[index].firstOrNull?.left ?? size.width) -
                rect.left -
                52,
          ),
          style: TextStyle(
            fontFamily: QestoTypography.uiFamily,
            color: c.text,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        );
        _text(
          canvas,
          hideAmounts ? '••••' : formatMoney(category.amount, currency),
          Offset(rect.left + 35, rect.center.dy - 2),
          width: math.max(
            70,
            (layout.purchases[index].firstOrNull?.left ?? size.width) -
                rect.left -
                52,
          ),
          style: TextStyle(
            fontFamily: QestoTypography.uiFamily,
            color: c.secondaryText,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        );
      }

      for (
        var purchaseIndex = 0;
        purchaseIndex < layout.purchases[index].length;
        purchaseIndex++
      ) {
        final purchase = category.purchases[purchaseIndex];
        final purchaseRect = layout.purchases[index][purchaseIndex];
        canvas.drawRRect(
          RRect.fromRectAndRadius(purchaseRect, const Radius.circular(4)),
          Paint()..color = category.color.withValues(alpha: 0.86),
        );
        if (purchaseRect.height < 10) continue;
        _text(
          canvas,
          purchase.label,
          Offset(purchaseRect.right + 8, purchaseRect.center.dy - 12),
          width: size.width - purchaseRect.right - 12,
          maxLines: 1,
          style: TextStyle(
            fontFamily: QestoTypography.uiFamily,
            color: c.text,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        );
        if (purchaseRect.height >= 22) {
          _text(
            canvas,
            hideAmounts ? '••••' : formatMoney(purchase.amount, currency),
            Offset(purchaseRect.right + 8, purchaseRect.center.dy + 1),
            width: size.width - purchaseRect.right - 12,
            maxLines: 1,
            style: TextStyle(
              fontFamily: QestoTypography.uiFamily,
              color: c.secondaryText,
              fontSize: 8,
            ),
          );
        }
      }
    }
  }

  void _ribbon(Canvas canvas, Rect source, Rect target, Color color) {
    final distance = target.left - source.right;
    final path = Path()
      ..moveTo(source.right, source.top)
      ..cubicTo(
        source.right + distance * 0.46,
        source.top,
        target.left - distance * 0.46,
        target.top,
        target.left,
        target.top,
      )
      ..lineTo(target.left, target.bottom)
      ..cubicTo(
        target.left - distance * 0.46,
        target.bottom,
        source.right + distance * 0.46,
        source.bottom,
        source.right,
        source.bottom,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _columnTitle(Canvas canvas, String value, Offset offset) => _text(
    canvas,
    value,
    offset,
    width: 210,
    style: TextStyle(
      fontFamily: QestoTypography.uiFamily,
      color: c.secondaryText,
      fontSize: 8,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.55,
    ),
  );

  void _text(
    Canvas canvas,
    String value,
    Offset offset, {
    required double width,
    required TextStyle style,
    TextAlign align = TextAlign.left,
    int maxLines = 2,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: style.copyWith(fontFamily: QestoTypography.uiFamily),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: math.max(1, width));
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _MoneyFlowPainter oldDelegate) =>
      oldDelegate.c != c ||
      oldDelegate.categories != categories ||
      oldDelegate.income != income ||
      oldDelegate.expenses != expenses ||
      oldDelegate.hideAmounts != hideAmounts ||
      oldDelegate.hoveredId != hoveredId ||
      oldDelegate.compact != compact;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
