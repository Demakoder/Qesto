import 'package:flutter/material.dart';
import 'qesto_tokens.dart';
import 'qesto_semantic_colors.dart';

class QestoSilverSurface extends StatelessWidget {
  const QestoSilverSurface({
    required this.child,
    this.pressed = false,
    this.focused = false,
    this.disabled = false,
    this.padding = EdgeInsets.zero,
    super.key,
  });
  final Widget child;
  final bool pressed;
  final bool focused;
  final bool disabled;
  final EdgeInsetsGeometry padding;

  static BoxDecoration decoration({
    QestoSemanticColors colors = QestoSemanticColors.light,
    bool pressed = false,
    bool focused = false,
    bool disabled = false,
  }) => BoxDecoration(
    borderRadius: QestoGeometry.control,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: disabled
          ? [colors.surfaceSecondary, colors.surfaceSecondary]
          : pressed
          ? [colors.controlMid, colors.controlHighlight]
          : [colors.controlHighlight, colors.controlMid, colors.controlLow],
      stops: disabled || pressed ? null : const [0, .48, 1],
    ),
    border: Border.all(
      color: focused ? colors.primary : colors.controlEdge,
      width: focused ? 1.5 : 1,
    ),
    boxShadow: disabled || pressed
        ? const []
        : const [
            BoxShadow(
              color: Color(0x12161B1F),
              blurRadius: 3,
              offset: Offset(0, 2),
            ),
          ],
  );

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: QestoMotion.effective(context, QestoMotion.fast),
    padding: padding,
    decoration: decoration(
      colors: context.qestoColors,
      pressed: pressed,
      focused: focused,
      disabled: disabled,
    ),
    child: child,
  );

  /// Native buttons retain keyboard, semantics, form and focus behaviour.
  static Widget buttonBackground(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => QestoSilverSurface(
    pressed: states.contains(WidgetState.pressed),
    focused: states.contains(WidgetState.focused),
    disabled: states.contains(WidgetState.disabled),
    child: child ?? const SizedBox.shrink(),
  );
}

class QestoPrimaryButton extends StatelessWidget {
  const QestoPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: icon == null ? null : Icon(icon, size: 18),
    label: Text(label),
  );
}

class QestoNavigationSurface extends StatelessWidget {
  const QestoNavigationSurface({
    required this.selected,
    required this.child,
    super.key,
  });
  final bool selected;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Ink(
      decoration: selected
          ? QestoSilverSurface.decoration(colors: context.qestoColors)
          : const BoxDecoration(borderRadius: QestoGeometry.control),
      child: child,
    ),
  );
}

class QestoSecondaryButton extends StatelessWidget {
  const QestoSecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: icon == null ? null : Icon(icon, size: 18),
    label: Text(label),
  );
}

class QestoGhostButton extends StatelessWidget {
  const QestoGhostButton({
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: onPressed, child: Text(label));
}

class QestoIconButton extends StatelessWidget {
  const QestoIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton.outlined(
    icon: Icon(icon, size: 18),
    tooltip: tooltip,
    onPressed: onPressed,
  );
}

class QestoDangerButton extends StatelessWidget {
  const QestoDangerButton({
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: context.qestoColors.negative,
      side: BorderSide(color: context.qestoColors.negative),
    ),
    child: Text(label),
  );
}
