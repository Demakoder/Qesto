import 'package:flutter/material.dart';

import '../theme/qesto_theme.dart';
import '../../design_system/qesto_window.dart';

class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final String? semanticsLabel;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: QestoMotion.effective(context, QestoMotion.fast),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.88 : 1,
          duration: QestoMotion.effective(context, QestoMotion.fast),
          child: Material(
            color: Colors.transparent,
            borderRadius: widget.borderRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (pressed) {
                if (_pressed != pressed) setState(() => _pressed = pressed);
              },
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class QestoCard extends StatelessWidget {
  const QestoCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.radius = QestoGeometry.radius,
    this.color,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    child: QestoWindow(
      padding: padding,
      color: color,
      onTap: onTap,
      child: child,
    ),
  );
}
