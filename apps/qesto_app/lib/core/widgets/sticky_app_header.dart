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
          color: QestoColors.secondaryText,
        ),
        IconButton(
          onPressed: onNotificationsPressed,
          tooltip: 'Уведомления',
          icon: const Icon(Icons.notifications_none_rounded, size: 27),
          color: QestoColors.secondaryText,
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFDDEAFF), Color(0xFFF4E4D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0xFF4B5874),
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
