import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../budget/widgets/budget_category_icon.dart';
import '../../domain/models/statistics_models.dart';

String statisticsRangeLabel(StatisticsDateRange range) {
  if (range.start == range.end) {
    return formatDate(range.start, includeYear: true);
  }
  if (range.start.year == range.end.year &&
      range.start.month == range.end.month) {
    final end = formatDate(range.end, includeYear: true).split(' ');
    return '${range.start.day}–${range.end.day} ${end.skip(1).join(' ')}';
  }
  return '${formatDate(range.start, includeYear: true)} — ${formatDate(range.end, includeYear: true)}';
}

class StatisticsIconButton extends StatelessWidget {
  const StatisticsIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge,
    this.badgeColor,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: context.qestoColors.surface,
              borderRadius: QestoGeometry.control,
              child: InkWell(
                onTap: onPressed,
                borderRadius: QestoGeometry.control,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    border: Border.all(color: context.qestoColors.border),
                    borderRadius: QestoGeometry.control,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C26324A),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: context.qestoColors.primary,
                    size: 25,
                  ),
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 19,
                    minHeight: 19,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor ?? context.qestoColors.primary,
                    borderRadius: QestoGeometry.control,
                    border: Border.all(
                      color: context.qestoColors.surface,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    badge!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StatisticsSectionHeader extends StatelessWidget {
  const StatisticsSectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
      ],
    );
  }
}

class StatisticsMetricStrip extends StatelessWidget {
  const StatisticsMetricStrip({required this.items, super.key});

  final List<StatisticsMetricItem> items;

  @override
  Widget build(BuildContext context) {
    return QestoCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 420
              ? constraints.maxWidth / items.length
              : 176.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  SizedBox(
                    width: width,
                    child: _MetricCell(item: items[index]),
                  ),
                  if (index != items.length - 1)
                    const SizedBox(
                      height: 104,
                      child: VerticalDivider(width: 1),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class StatisticsMetricItem {
  const StatisticsMetricItem({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color? valueColor;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.item});

  final StatisticsMetricItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: context.qestoColors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.qestoColors.primarySoft,
                  borderRadius: QestoGeometry.control,
                ),
                child: Icon(
                  item.icon,
                  color: context.qestoColors.primary,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              item.value,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: item.valueColor ?? context.qestoColors.text,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class StatisticsGroupList extends StatelessWidget {
  const StatisticsGroupList({
    required this.title,
    required this.items,
    required this.onTap,
    this.limit = 3,
    this.onShowAll,
    this.currency = 'RUB',
    this.amountConverter,
    super.key,
  });

  final String title;
  final List<StatisticsGroupStat> items;
  final ValueChanged<StatisticsGroupStat> onTap;
  final int limit;
  final VoidCallback? onShowAll;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(limit).toList();
    return QestoCard(
      child: Column(
        children: [
          StatisticsSectionHeader(
            title: title,
            actionLabel: onShowAll == null ? null : 'Показать всё',
            onAction: onShowAll,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < visible.length; index++)
            _GroupRow(
              item: visible[index],
              onTap: () => onTap(visible[index]),
              maxAmount: items.isEmpty ? 1 : items.first.amount,
              currency: currency,
              amountConverter: amountConverter,
            ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.item,
    required this.onTap,
    required this.maxAmount,
    required this.currency,
    required this.amountConverter,
  });

  final StatisticsGroupStat item;
  final VoidCallback onTap;
  final int maxAmount;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  Widget build(BuildContext context) {
    final change = item.changePercent;
    final positive = (change ?? 0) >= 0;
    final color = change == null
        ? context.qestoColors.secondaryText
        : positive
        ? context.qestoColors.positive
        : context.qestoColors.danger;
    return InkWell(
      onTap: onTap,
      borderRadius: QestoGeometry.control,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            BudgetCategoryIcon(
              iconKey: item.iconKey ?? 'store',
              color: Color(
                item.colorValue ?? context.qestoColors.primary.toARGB32(),
              ),
              size: 42,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: maxAmount <= 0 ? 0 : item.amount / maxAmount,
                      backgroundColor: context.qestoColors.border,
                      valueColor: AlwaysStoppedAnimation(
                        Color(
                          item.colorValue ??
                              context.qestoColors.primary.toARGB32(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(
                    amountConverter?.call(item.amount) ?? item.amount,
                    currency,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  change == null
                      ? 'нет сравнения'
                      : '${positive ? '↑' : '↓'} ${change.abs().toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              color: context.qestoColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class StatisticsInsightsCard extends StatelessWidget {
  const StatisticsInsightsCard({
    required this.insights,
    required this.onDetails,
    super.key,
  });

  final List<StatisticsInsight> insights;
  final ValueChanged<StatisticsInsight> onDetails;

  @override
  Widget build(BuildContext context) {
    return QestoCard(
      child: Column(
        children: [
          const StatisticsSectionHeader(title: 'Выводы'),
          const SizedBox(height: 8),
          for (final insight in insights.take(3))
            InkWell(
              onTap: () => onDetails(insight),
              borderRadius: QestoGeometry.control,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: context.qestoColors.primarySoft,
                        borderRadius: QestoGeometry.control,
                      ),
                      child: Icon(
                        _insightIcon(insight.type),
                        color: context.qestoColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            insight.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            insight.explanation,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: context.qestoColors.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _insightIcon(StatisticsInsightType type) => switch (type) {
    StatisticsInsightType.change => Icons.trending_up_rounded,
    StatisticsInsightType.category => Icons.category_outlined,
    StatisticsInsightType.merchant => Icons.storefront_outlined,
    StatisticsInsightType.largePurchase => Icons.shopping_bag_outlined,
    StatisticsInsightType.quality => Icons.fact_check_outlined,
  };
}

class StatisticsInfoBanner extends StatelessWidget {
  const StatisticsInfoBanner({
    required this.message,
    this.icon = Icons.info_outline_rounded,
    super.key,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.qestoColors.primarySoft,
        borderRadius: QestoGeometry.control,
      ),
      child: Row(
        children: [
          Icon(icon, color: context.qestoColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
