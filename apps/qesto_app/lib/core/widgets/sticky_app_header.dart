import 'package:flutter/material.dart';

import '../../data/models/qesto_models.dart';
import '../theme/qesto_theme.dart';

class StickyAppHeader extends StatelessWidget implements PreferredSizeWidget {
  const StickyAppHeader({
    required this.title,
    required this.user,
    required this.onHistoryPressed,
    required this.onNotificationsPressed,
    required this.onProfilePressed,
    super.key,
  });

  final String title;
  final QestoUser user;
  final VoidCallback onHistoryPressed;
  final VoidCallback onNotificationsPressed;
  final VoidCallback onProfilePressed;

  @override
  Size get preferredSize => const Size.fromHeight(70);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      actions: [
        IconButton(
          key: const Key('action-history-button'),
          onPressed: onHistoryPressed,
          tooltip: 'История действий',
          icon: const Icon(Icons.history_rounded, size: 27),
          color: context.qestoColors.secondaryText,
        ),
        IconButton(
          onPressed: onNotificationsPressed,
          tooltip: 'Уведомления',
          icon: const Icon(Icons.notifications_none_rounded, size: 27),
          color: context.qestoColors.secondaryText,
        ),
        const SizedBox(width: 2),
        Semantics(
          button: true,
          label: 'Профиль пользователя ${user.name}',
          child: InkResponse(
            onTap: onProfilePressed,
            radius: 25,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    context.qestoColors.controlHighlight,
                    context.qestoColors.controlMid,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_rounded,
                color: context.qestoColors.primary,
                size: 27,
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
      ],
    );
  }
}
