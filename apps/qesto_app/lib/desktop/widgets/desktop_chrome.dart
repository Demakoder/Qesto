import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../desktop_destination.dart';
import 'desktop_components.dart';

class DesktopSidebar extends StatefulWidget {
  const DesktopSidebar({
    required this.selected,
    required this.collapsed,
    required this.user,
    required this.onSelected,
    required this.onToggle,
    super.key,
  });

  final DesktopDestination selected;
  final bool collapsed;
  final QestoUser user;
  final ValueChanged<DesktopDestination> onSelected;
  final VoidCallback onToggle;
  @override
  State<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<DesktopSidebar> {
  late DesktopProductSection _expandedSection =
      widget.selected.section ?? DesktopProductSection.budget;

  @override
  void didUpdateWidget(covariant DesktopSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final section = widget.selected.section;
    if (section != null && section != _expandedSection) {
      _expandedSection = section;
    }
  }

  void _openSection(DesktopProductSection section) {
    setState(() => _expandedSection = section);
    widget.onSelected(section.landing);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.collapsed ? 76 : 244,
      decoration: const BoxDecoration(
        color: QestoColors.surface,
        border: Border(right: BorderSide(color: QestoColors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                widget.collapsed ? 10 : 18,
                16,
                widget.collapsed ? 10 : 12,
                12,
              ),
              child: Row(
                mainAxisAlignment: widget.collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (!widget.collapsed) ...[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4D89F8), Color(0xFF2969E7)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Q',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Text(
                        'Qesto',
                        style: TextStyle(
                          color: QestoColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ] else
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: QestoColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        tooltip: 'Развернуть меню',
                        onPressed: widget.onToggle,
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          color: QestoColors.primary,
                          size: 19,
                        ),
                      ),
                    ),
                  if (!widget.collapsed)
                    IconButton(
                      tooltip: 'Свернуть меню',
                      onPressed: widget.onToggle,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.keyboard_double_arrow_left_rounded,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                children: [
                  if (!widget.collapsed)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(10, 7, 10, 7),
                      child: Text(
                        'РАЗДЕЛЫ',
                        style: TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  for (final section in DesktopProductSection.values) ...[
                    _ProductSectionItem(
                      section: section,
                      selected: section == widget.selected.section,
                      expanded: section == _expandedSection,
                      collapsed: widget.collapsed,
                      onTap: () => _openSection(section),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: section == _expandedSection
                          ? Padding(
                              key: Key('desktop-section-items-${section.name}'),
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Column(
                                children: [
                                  for (final destination
                                      in DesktopDestination.values.where(
                                        (item) => item.section == section,
                                      ))
                                    _SidebarItem(
                                      destination: destination,
                                      selected: destination == widget.selected,
                                      collapsed: widget.collapsed,
                                      nested: true,
                                      onTap: () =>
                                          widget.onSelected(destination),
                                    ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
              child: _ProfileSettingsCard(
                user: widget.user,
                collapsed: widget.collapsed,
                selected: widget.selected == DesktopDestination.settings,
                onTap: () => widget.onSelected(DesktopDestination.settings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSectionItem extends StatelessWidget {
  const _ProductSectionItem({
    required this.section,
    required this.selected,
    required this.expanded,
    required this.collapsed,
    required this.onTap,
  });

  final DesktopProductSection section;
  final bool selected;
  final bool expanded;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: collapsed ? section.label : '',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? section.color.withValues(alpha: 0.11)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          key: Key('desktop-section-${section.name}'),
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                SizedBox(width: collapsed ? 0 : 11),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: section.color.withValues(
                      alpha: selected ? 0.17 : 0.09,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(section.icon, color: section.color, size: 18),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.label,
                      style: TextStyle(
                        color: selected ? section.color : QestoColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.chevron_right_rounded,
                    size: 17,
                    color: selected ? section.color : QestoColors.secondaryText,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.nested = false,
  });

  final DesktopDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? destination.label : '',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected ? QestoColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: SizedBox(
              height: nested ? 36 : 40,
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (!collapsed)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 3,
                      height: selected ? 20 : 0,
                      decoration: BoxDecoration(
                        color: QestoColors.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  SizedBox(width: collapsed ? 0 : (nested ? 20 : 10)),
                  Icon(
                    destination.icon,
                    size: nested ? 18 : 20,
                    color: selected
                        ? QestoColors.primary
                        : QestoColors.secondaryText,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? QestoColors.primary
                              : QestoColors.text,
                          fontSize: nested ? 12 : 13,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopUserAvatar extends StatelessWidget {
  const DesktopUserAvatar({required this.user, this.radius = 17, super.key});

  final QestoUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final emoji = user.avatarUrl?.startsWith('emoji:') == true
        ? user.avatarUrl!.substring('emoji:'.length)
        : null;
    return CircleAvatar(
      radius: radius,
      backgroundColor: QestoColors.primarySoft,
      child: Text(
        emoji ?? (user.name.trim().isEmpty ? 'Q' : user.name.trim()[0]),
        style: TextStyle(
          color: QestoColors.primary,
          fontSize: emoji == null ? radius * 0.85 : radius,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileSettingsCard extends StatelessWidget {
  const _ProfileSettingsCard({
    required this.user,
    required this.collapsed,
    required this.selected,
    required this.onTap,
  });

  final QestoUser user;
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: collapsed ? 'Профиль и настройки' : '',
    child: Material(
      color: selected ? QestoColors.primarySoft : QestoColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        key: const Key('desktop-profile-settings'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: EdgeInsets.all(collapsed ? 8 : 10),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              DesktopUserAvatar(user: user),
              if (!collapsed) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        user.defaultCurrency,
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.settings_outlined,
                  size: 17,
                  color: selected
                      ? QestoColors.primary
                      : QestoColors.secondaryText,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class DesktopTopBar extends StatelessWidget {
  const DesktopTopBar({
    required this.title,
    required this.onSearch,
    required this.onAdd,
    required this.onNotifications,
    this.period,
    this.onPeriodPressed,
    this.compactSearch = false,
    this.contextualActions = const [],
    super.key,
  });

  final String title;
  final String? period;
  final VoidCallback? onPeriodPressed;
  final bool compactSearch;
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  final VoidCallback onNotifications;
  final List<Widget> contextualActions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: const BoxDecoration(
        color: QestoColors.background,
        border: Border(bottom: BorderSide(color: QestoColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.qestoTypography.display(
                          const TextStyle(
                            color: QestoColors.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.55,
                          ),
                        ),
                      ),
                    ),
                    if (period != null && !compact) ...[
                      const SizedBox(width: 14),
                      if (onPeriodPressed == null)
                        DesktopPill(
                          label: period!,
                          icon: Icons.calendar_month_outlined,
                          color: QestoColors.secondaryText,
                          background: QestoColors.surfaceSecondary,
                        )
                      else
                        OutlinedButton.icon(
                          key: const Key('desktop-overview-period'),
                          onPressed: onPeriodPressed,
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                          ),
                          label: Text(period!),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: QestoColors.text,
                            side: const BorderSide(color: QestoColors.border),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (!compact) ...contextualActions,
              const SizedBox(width: 8),
              if (compact || compactSearch)
                IconButton.outlined(
                  tooltip: 'Поиск · Ctrl K',
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded, size: 20),
                  style: IconButton.styleFrom(
                    foregroundColor: QestoColors.secondaryText,
                    side: const BorderSide(color: QestoColors.border),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Row(
                    children: [
                      Text('Поиск'),
                      SizedBox(width: 12),
                      DesktopPill(
                        label: 'Ctrl K',
                        color: QestoColors.secondaryText,
                        background: QestoColors.surfaceSecondary,
                      ),
                    ],
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: QestoColors.secondaryText,
                    side: const BorderSide(color: QestoColors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (!compact) ...[
                IconButton.outlined(
                  key: const Key('desktop-notifications'),
                  tooltip: 'Уведомления',
                  onPressed: onNotifications,
                  icon: const Icon(Icons.notifications_none_rounded, size: 20),
                  style: IconButton.styleFrom(
                    foregroundColor: QestoColors.secondaryText,
                    side: const BorderSide(color: QestoColors.border),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (compact)
                IconButton.filled(
                  key: const Key('desktop-add-data'),
                  tooltip: 'Добавить',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: QestoColors.primary,
                    foregroundColor: Colors.white,
                  ),
                )
              else
                FilledButton.icon(
                  key: const Key('desktop-add-data'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Добавить'),
                  style: FilledButton.styleFrom(
                    backgroundColor: QestoColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
