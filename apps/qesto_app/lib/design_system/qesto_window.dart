import 'package:flutter/material.dart';
import '../core/theme/qesto_theme.dart';
import 'qesto_silver.dart';

/// Composable tool surface. The owner keeps its controller/filter/route state.
class QestoWindow extends StatefulWidget {
  const QestoWindow({
    required this.child,
    this.title,
    this.toolbar,
    this.actions,
    this.footer,
    this.onExpand,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.borderColor,
    super.key,
  });
  final Widget child;
  final String? title;
  final Widget? toolbar;
  final Widget? actions;
  final Widget? footer;
  final VoidCallback? onExpand;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  @override
  State<QestoWindow> createState() => _QestoWindowState();
}

class _QestoWindowState extends State<QestoWindow> {
  bool _hover = false;
  bool _focus = false;
  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: widget.color ?? context.qestoColors.surface,
      borderRadius: QestoGeometry.window,
      clipBehavior: Clip.antiAlias,
      child:
          widget.title == null &&
              widget.toolbar == null &&
              widget.footer == null
          ? Padding(padding: widget.padding, child: widget.child)
          : LayoutBuilder(
              builder: (context, constraints) {
                final body = Padding(
                  padding: widget.padding,
                  child: widget.child,
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.title != null)
                      QestoWindowHeader(
                        title: widget.title!,
                        actions: widget.actions,
                        onExpand: widget.onExpand,
                        focused: _focus,
                      ),
                    if (widget.toolbar != null)
                      QestoWindowToolbar(child: widget.toolbar!),
                    if (constraints.hasBoundedHeight)
                      Expanded(child: body)
                    else
                      body,
                    if (widget.footer != null)
                      QestoWindowFooter(child: widget.footer!),
                  ],
                );
              },
            ),
    );
    final interactive = widget.onTap == null
        ? content
        : InkWell(
            onTap: widget.onTap,
            borderRadius: QestoGeometry.window,
            child: content,
          );
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => _focus = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: QestoMotion.effective(context, QestoMotion.fast),
          decoration: BoxDecoration(
            color: widget.color ?? context.qestoColors.surface,
            borderRadius: QestoGeometry.window,
            border: Border.all(
              color: _focus
                  ? context.qestoColors.primary
                  : _hover
                  ? context.qestoColors.controlEdge
                  : widget.borderColor ?? context.qestoColors.border,
            ),
            boxShadow: _focus
                ? QestoGeometry.focusShadow
                : QestoGeometry.windowShadow,
          ),
          child: interactive,
        ),
      ),
    );
  }
}

class QestoWindowHeader extends StatelessWidget {
  const QestoWindowHeader({
    required this.title,
    this.actions,
    this.onExpand,
    this.focused = false,
    super.key,
  });
  final String title;
  final Widget? actions;
  final VoidCallback? onExpand;
  final bool focused;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.qestoColors.border)),
      gradient: focused
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.qestoColors.controlHighlight,
                context.qestoColors.primarySoft,
              ],
            )
          : null,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: QestoTypography.uiStrong.copyWith(
                color: context.qestoColors.text,
              ),
            ),
          ),
          ?actions,
          if (onExpand != null)
            QestoIconButton(
              icon: Icons.open_in_full_rounded,
              tooltip: 'Развернуть $title',
              onPressed: onExpand,
            ),
        ],
      ),
    ),
  );
}

class QestoWindowBody extends StatelessWidget {
  const QestoWindowBody({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(QestoSpacing.xl), child: child);
}

class QestoWindowToolbar extends StatelessWidget {
  const QestoWindowToolbar({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.qestoColors.surfaceSecondary,
      border: Border(bottom: BorderSide(color: context.qestoColors.border)),
    ),
    child: child,
  );
}

class QestoWindowFooter extends StatelessWidget {
  const QestoWindowFooter({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.qestoColors.border)),
    ),
    child: child,
  );
}

/// Full number remains available to accessibility and pointer users.
class QestoHeroMoney extends StatelessWidget {
  const QestoHeroMoney(this.value, {this.color, this.large = true, super.key});
  final String value;
  final Color? color;
  final bool large;
  @override
  Widget build(BuildContext context) => Semantics(
    label: value,
    excludeSemantics: true,
    child: Tooltip(
      message: value,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style:
                (large ? QestoTypography.moneyHero : QestoTypography.moneyLarge)
                    .copyWith(color: color ?? context.qestoColors.text),
          ),
        ),
      ),
    ),
  );
}

class QestoMoneyCell extends StatelessWidget {
  const QestoMoneyCell(this.value, {this.color, super.key});
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: value,
    child: Text(
      value,
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: QestoTypography.table.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class QestoChartSurface extends StatelessWidget {
  const QestoChartSurface({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: QestoGeometry.data,
    child: ColoredBox(color: context.qestoColors.chartSurface, child: child),
  );
}
