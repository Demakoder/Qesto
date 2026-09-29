import 'package:flutter/material.dart';

import '../theme/qesto_theme.dart';

class NestedScreenHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const NestedScreenHeader({
    required this.title,
    this.centerTitle = false,
    this.actions,
    this.onBack,
    super.key,
  });

  final Widget title;
  final bool centerTitle;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(70);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      leadingWidth: 58,
      leading: IconButton(
        onPressed: onBack ?? () => Navigator.of(context).pop(),
        tooltip: 'Назад',
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21),
      ),
      centerTitle: centerTitle,
      titleSpacing: centerTitle ? 0 : 2,
      title: title,
      actions: actions,
      backgroundColor: context.qestoColors.background,
      surfaceTintColor: Colors.transparent,
    );
  }
}
