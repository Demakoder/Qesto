import 'package:flutter/material.dart';

import '../theme/qesto_theme.dart';
import 'qesto_card.dart';
import '../../design_system/qesto_silver.dart';
import '../../design_system/qesto_window.dart';

enum QestoButtonStyle { primary, secondary }

class QestoButton extends StatelessWidget {
  const QestoButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = QestoButtonStyle.primary,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final QestoButtonStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: style == QestoButtonStyle.primary
        ? QestoPrimaryButton(label: label, icon: icon, onPressed: onPressed)
        : QestoSecondaryButton(label: label, icon: icon, onPressed: onPressed),
  );
}

class QestoProgressBar extends StatelessWidget {
  const QestoProgressBar({
    required this.value,
    this.color,
    this.backgroundColor,
    this.height = 9,
    super.key,
  });

  final double value;
  final Color? color;
  final Color? backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.qestoColors.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: backgroundColor ?? context.qestoColors.surfaceSecondary,
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, Color.lerp(color, Colors.white, 0.22)!],
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

class AmountText extends StatelessWidget {
  const AmountText(this.value, {this.color, super.key});

  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      QestoHeroMoney(value, color: color, large: false);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    );
  }
}

class QestoActionTile extends StatelessWidget {
  const QestoActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final iconColor = this.iconColor ?? context.qestoColors.primary;
    return QestoCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.qestoColors.secondaryText,
          ),
        ],
      ),
    );
  }
}
