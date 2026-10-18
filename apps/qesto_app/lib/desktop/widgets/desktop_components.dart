import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../design_system/qesto_window.dart';

/// Card contents stack on phones; desktop keeps its original flex layout.
class DesktopAdaptiveRow extends StatelessWidget {
  const DesktopAdaptiveRow({
    required this.children,
    this.wrapOnMobile = false,
    super.key,
  });
  final List<Widget> children;
  final bool wrapOnMobile;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) return Row(children: children);
    if (wrapOnMobile) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final child in children)
            if (child is! Spacer) child is Expanded ? child.child : child,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          if (child is! Spacer)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: child is Expanded
                  ? child.child
                  : child is SizedBox && child.child == null
                  ? const SizedBox.shrink()
                  : child,
            ),
      ],
    );
  }
}

class DesktopCollapsibleFilters extends StatelessWidget {
  const DesktopCollapsibleFilters({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => MediaQuery.sizeOf(context).width < 600
      ? ExpansionTile(title: const Text('Поиск и фильтры'), children: [child])
      : child;
}

class DesktopCard extends StatelessWidget {
  const DesktopCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => QestoWindow(
    padding: padding,
    color: color,
    borderColor: borderColor,
    onTap: onTap,
    child: child,
  );
}

class DesktopKpiCard extends StatelessWidget {
  const DesktopKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.detailColor,
    this.accent,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? detailColor;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent ?? context.qestoColors.primary;
    return DesktopCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: QestoGeometry.control,
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.qestoTypography.display(
              TextStyle(
                color: context.qestoColors.text,
                fontSize: 27,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
              numeric: true,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 9),
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: detailColor ?? context.qestoColors.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DesktopSectionHeader extends StatelessWidget {
  const DesktopSectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.qestoColors.text,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.qestoColors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class DesktopTextButton extends StatelessWidget {
  const DesktopTextButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: context.qestoColors.primary,
        textStyle: const TextStyle(
          fontFamily: QestoTypography.uiFamily,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class DesktopPill extends StatelessWidget {
  const DesktopPill({
    required this.label,
    this.icon,
    this.color,
    this.background,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.qestoColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.09),
        borderRadius: QestoGeometry.control,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopEmptyState extends StatelessWidget {
  const DesktopEmptyState({
    required this.title,
    required this.message,
    required this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: context.qestoColors.primarySoft,
                  borderRadius: QestoGeometry.control,
                ),
                child: Icon(icon, color: context.qestoColors.primary, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopProgressBar extends StatelessWidget {
  const DesktopProgressBar({
    required this.value,
    this.color,
    this.height = 7,
    super.key,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: QestoGeometry.control,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: context.qestoColors.surfaceSecondary),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0, 1),
              child: ColoredBox(color: color ?? context.qestoColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
