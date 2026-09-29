import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'qesto_silver.dart';
import 'qesto_window.dart';

/// One element subtree is reparented, not a second copy of the financial tool.
/// Chart selection, forms and scroll state survive compact/expanded transitions.
class QestoExpandableTool extends StatefulWidget {
  const QestoExpandableTool({
    required this.title,
    required this.builder,
    this.actions,
    super.key,
  });
  final String title;
  final Widget Function(BuildContext context, bool expanded) builder;
  final Widget? actions;
  @override
  State<QestoExpandableTool> createState() => _QestoExpandableToolState();
}

class _QestoExpandableToolState extends State<QestoExpandableTool> {
  final _overlay = OverlayPortalController();
  final _bodyKey = GlobalKey();
  final _anchorKey = GlobalKey();
  bool _expanded = false;
  Size _compactSize = const Size(400, 360);
  FocusNode? _previousFocus;

  void _toggle() {
    if (!_expanded) {
      final render = _anchorKey.currentContext?.findRenderObject();
      if (render is RenderBox && render.hasSize) _compactSize = render.size;
      _previousFocus = FocusManager.instance.primaryFocus;
      setState(() => _expanded = true);
      _overlay.show();
    } else {
      setState(() => _expanded = false);
      _overlay.hide();
      if (_previousFocus?.context != null) _previousFocus!.requestFocus();
    }
  }

  Widget _window(BuildContext context) => QestoWindow(
    title: widget.title,
    actions: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?widget.actions,
        QestoIconButton(
          icon: _expanded
              ? Icons.close_fullscreen_rounded
              : Icons.open_in_full_rounded,
          tooltip: '${_expanded ? 'Свернуть' : 'Развернуть'} ${widget.title}',
          onPressed: _toggle,
        ),
      ],
    ),
    child: KeyedSubtree(
      key: _bodyKey,
      child: widget.builder(context, _expanded),
    ),
  );

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _overlay,
    overlayChildBuilder: (context) => Positioned.fill(
      child: Stack(
        children: [
          ModalBarrier(
            color: const Color(0x66171B1E),
            dismissible: true,
            onDismiss: _toggle,
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 12 : 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): _toggle,
                    },
                    child: Focus(
                      autofocus: true,
                      child: Semantics(
                        scopesRoute: true,
                        explicitChildNodes: true,
                        namesRoute: true,
                        label: widget.title,
                        child: _window(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    child: SizedBox(
      key: _anchorKey,
      child: _expanded
          ? SizedBox(height: _compactSize.height, width: _compactSize.width)
          : _window(context),
    ),
  );
}
