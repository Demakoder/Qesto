import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/qesto_card.dart';

/// Presentation only: callers provide values from the existing read models.
class MobileMoney extends StatelessWidget {
  const MobileMoney(
    this.amount, {
    this.currency = 'RUB',
    this.hidden = false,
    this.size = 26,
    this.color,
    this.showSign = false,
    super.key,
  });
  final int amount;
  final String currency;
  final bool hidden;
  final double size;
  final Color? color;
  final bool showSign;
  @override
  Widget build(BuildContext context) => Semantics(
    label: hidden
        ? 'Сумма скрыта'
        : formatMoney(amount, currency, showSign: showSign),
    child: ExcludeSemantics(
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            hidden ? '••••' : formatMoney(amount, currency, showSign: showSign),
            maxLines: 1,
            style: QestoTypography.moneyLarge.copyWith(
              fontSize: size,
              color: color ?? context.qestoColors.text,
            ),
          ),
        ),
      ),
    ),
  );
}

class MobileSection extends StatelessWidget {
  const MobileSection({
    required this.title,
    required this.child,
    this.action,
    this.actionLabel = 'Подробнее',
    super.key,
  });
  final String title;
  final Widget child;
  final VoidCallback? action;
  final String actionLabel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: QestoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (action != null)
                TextButton(onPressed: action, child: Text(actionLabel)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class MobileMetric extends StatelessWidget {
  const MobileMetric({
    required this.label,
    required this.amount,
    this.currency = 'RUB',
    this.hidden = false,
    this.color,
    this.onTap,
    super.key,
  });
  final String label;
  final int amount;
  final String currency;
  final bool hidden;
  final Color? color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: hidden ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.qestoColors.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          MobileMoney(
            amount,
            currency: currency,
            hidden: hidden,
            size: 22,
            color: color,
          ),
        ],
      ),
    ),
  );
}

class MobileValueRow extends StatelessWidget {
  const MobileValueRow({
    required this.title,
    required this.amount,
    this.caption,
    this.currency = 'RUB',
    this.hidden = false,
    this.color,
    this.onTap,
    this.progress,
    super.key,
  });
  final String title;
  final String? caption;
  final int amount;
  final String currency;
  final bool hidden;
  final Color? color;
  final VoidCallback? onTap;
  final double? progress;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: hidden ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (caption != null)
                      Text(
                        caption!,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.qestoColors.secondaryText,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: MobileMoney(
                  amount,
                  currency: currency,
                  hidden: hidden,
                  size: 19,
                  color: color,
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right, size: 18),
            ],
          ),
          if (progress != null && !hidden) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress!.clamp(0, 1),
              minHeight: 4,
              color: color ?? context.qestoColors.primary,
              backgroundColor: context.qestoColors.border,
            ),
          ],
        ],
      ),
    ),
  );
}

class MobileAnalysisNotice extends StatelessWidget {
  const MobileAnalysisNotice(
    this.text, {
    this.onTap,
    this.icon = Icons.info_outline,
    super.key,
  });
  final String text;
  final VoidCallback? onTap;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, size: 20),
        title: Text(text, style: const TextStyle(fontSize: 13)),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      ),
    ),
  );
}

class MobileReadError extends StatelessWidget {
  const MobileReadError({
    required this.onRetry,
    this.hasPrevious = false,
    super.key,
  });
  final VoidCallback onRetry;
  final bool hasPrevious;
  @override
  Widget build(BuildContext context) => MobileAnalysisNotice(
    hasPrevious
        ? 'Не удалось обновить. Показаны предыдущие данные. Нажмите для повтора.'
        : 'Не удалось получить аналитику. Нажмите для повтора.',
    onTap: onRetry,
    icon: Icons.refresh,
  );
}
