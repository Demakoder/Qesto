import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../design_system/qesto_silver.dart';
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
    this.bankConnectionsAvailable = true,
    super.key,
  });

  final DesktopDestination selected;
  final bool collapsed;
  final QestoUser user;
  final ValueChanged<DesktopDestination> onSelected;
  final VoidCallback onToggle;
  final bool bankConnectionsAvailable;
  @override
  State<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<DesktopSidebar> {
  late DesktopProductSection? _expandedSection = widget.selected.section;

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
      width: widget.collapsed ? 76 : 216,
      decoration: BoxDecoration(
        color: context.qestoColors.surface,
        border: Border(right: BorderSide(color: context.qestoColors.border)),
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
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            context.qestoColors.controlHighlight,
                            context.qestoColors.controlMid,
                          ],
                        ),
                        borderRadius: QestoGeometry.control,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Q',
                        style: TextStyle(
                          color: context.qestoColors.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'Qesto',
                        style: TextStyle(
                          color: context.qestoColors.text,
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
                        color: context.qestoColors.primarySoft,
                        borderRadius: QestoGeometry.control,
                      ),
                      child: IconButton(
                        tooltip: 'Развернуть меню',
                        onPressed: widget.onToggle,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          color: context.qestoColors.primary,
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
                  _SidebarItem(
                    destination: DesktopDestination.dashboard,
                    selected: widget.selected == DesktopDestination.dashboard,
                    collapsed: widget.collapsed,
                    onTap: () =>
                        widget.onSelected(DesktopDestination.dashboard),
                  ),
                  _SidebarItem(
                    destination: DesktopDestination.insights,
                    selected: widget.selected == DesktopDestination.insights,
                    collapsed: widget.collapsed,
                    onTap: () => widget.onSelected(DesktopDestination.insights),
                  ),
                  if (widget.bankConnectionsAvailable)
                    _SidebarItem(
                      destination: DesktopDestination.connections,
                      selected:
                          widget.selected == DesktopDestination.connections,
                      collapsed: widget.collapsed,
                      onTap: () =>
                          widget.onSelected(DesktopDestination.connections),
                    ),
                  const SizedBox(height: 5),
                  if (!widget.collapsed)
                    Padding(
                      padding: EdgeInsets.fromLTRB(10, 7, 10, 7),
                      child: Text(
                        'РАЗДЕЛЫ',
                        style: TextStyle(
                          color: context.qestoColors.secondaryText,
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
                      duration: QestoMotion.effective(
                        context,
                        QestoMotion.normal,
                      ),
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
      child: QestoNavigationSurface(
        selected: selected,
        child: InkWell(
          key: Key('desktop-section-${section.name}'),
          borderRadius: QestoGeometry.control,
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
                    color: context.qestoColors.primary.withValues(
                      alpha: selected ? 0.17 : 0.09,
                    ),
                    borderRadius: QestoGeometry.control,
                  ),
                  child: Icon(
                    section.icon,
                    color: context.qestoColors.primary,
                    size: 18,
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.label,
                      style: TextStyle(
                        color: selected
                            ? context.qestoColors.primary
                            : context.qestoColors.text,
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
                    color: selected
                        ? context.qestoColors.primary
                        : context.qestoColors.secondaryText,
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
        child: QestoNavigationSurface(
          selected: selected,
          child: InkWell(
            key: Key('desktop-destination-${destination.name}'),
            borderRadius: QestoGeometry.control,
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
                      duration: QestoMotion.effective(
                        context,
                        QestoMotion.normal,
                      ),
                      width: 3,
                      height: selected ? 20 : 0,
                      decoration: BoxDecoration(
                        color: context.qestoColors.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  SizedBox(width: collapsed ? 0 : (nested ? 20 : 10)),
                  Icon(
                    destination.icon,
                    size: nested ? 18 : 20,
                    color: selected
                        ? context.qestoColors.primary
                        : context.qestoColors.secondaryText,
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
                              ? context.qestoColors.primary
                              : context.qestoColors.text,
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
      backgroundColor: context.qestoColors.primarySoft,
      child: Text(
        emoji ?? (user.name.trim().isEmpty ? 'Q' : user.name.trim()[0]),
        style: TextStyle(
          color: context.qestoColors.primary,
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
      color: selected
          ? context.qestoColors.primarySoft
          : context.qestoColors.surfaceSecondary,
      borderRadius: QestoGeometry.control,
      child: InkWell(
        key: const Key('desktop-profile-settings'),
        onTap: onTap,
        borderRadius: QestoGeometry.control,
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
                        style: TextStyle(
                          color: context.qestoColors.secondaryText,
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
                      ? context.qestoColors.primary
                      : context.qestoColors.secondaryText,
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
    this.notificationCount = 0,
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
  final int notificationCount;
  final List<Widget> contextualActions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        color: context.qestoVisual.chrome,
        border: Border(
          bottom: BorderSide(color: context.qestoVisual.chromeBorder),
        ),
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
                        style: QestoTypography.uiStrong.copyWith(
                          fontSize: 22,
                          color: context.qestoVisual.chromeText,
                        ),
                      ),
                    ),
                    if (period != null && !compact) ...[
                      const SizedBox(width: 14),
                      if (onPeriodPressed == null)
                        DesktopPill(
                          label: period!,
                          icon: Icons.calendar_month_outlined,
                          color: context.qestoColors.secondaryText,
                          background: context.qestoColors.surfaceSecondary,
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
                            foregroundColor: context.qestoColors.text,
                            side: BorderSide(color: context.qestoColors.border),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: QestoGeometry.control,
                            ),
                            textStyle: const TextStyle(
                              fontFamily: QestoTypography.uiFamily,
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
                    foregroundColor: context.qestoColors.secondaryText,
                    side: BorderSide(color: context.qestoColors.border),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: Row(
                    children: [
                      Text('Поиск'),
                      SizedBox(width: 12),
                      DesktopPill(
                        label: 'Ctrl K',
                        color: context.qestoColors.secondaryText,
                        background: context.qestoColors.surfaceSecondary,
                      ),
                    ],
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.qestoColors.secondaryText,
                    side: BorderSide(color: context.qestoColors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: QestoGeometry.control,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (!compact) ...[
                Badge(
                  isLabelVisible: notificationCount > 0,
                  label: Text(
                    notificationCount > 99 ? '99+' : '$notificationCount',
                  ),
                  child: IconButton.outlined(
                    key: const Key('desktop-notifications'),
                    tooltip: 'Уведомления',
                    onPressed: onNotifications,
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      foregroundColor: context.qestoColors.secondaryText,
                      side: BorderSide(color: context.qestoColors.border),
                    ),
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
                    backgroundColor: context.qestoColors.controlHighlight,
                    foregroundColor: context.qestoColors.text,
                  ),
                )
              else
                FilledButton.icon(
                  key: const Key('desktop-add-data'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Добавить'),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.qestoColors.controlHighlight,
                    foregroundColor: context.qestoColors.text,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: QestoGeometry.control,
                    ),
                    textStyle: const TextStyle(
                      fontFamily: QestoTypography.uiFamily,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
