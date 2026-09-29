import 'package:flutter/material.dart';

import '../theme/qesto_theme.dart';

class QestoBottomNavigation extends StatelessWidget {
  const QestoBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = <({String label, IconData icon})>[
    (label: 'Бюджет', icon: Icons.pie_chart_rounded),
    (label: 'Выгода', icon: Icons.local_offer_rounded),
    (label: 'Капитал', icon: Icons.account_balance_wallet_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.qestoColors.surface,
        border: Border(top: BorderSide(color: context.qestoColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x122A344A),
            blurRadius: 24,
            offset: Offset(0, -7),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var index = 0; index < _destinations.length; index++)
                Expanded(
                  child: _NavigationItem(
                    destination: _destinations[index],
                    selected: index == selectedIndex,
                    onTap: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ({String label, IconData icon}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.qestoColors.primary
        : context.qestoColors.secondaryText;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(destination.icon, color: color, size: 27),
            const SizedBox(height: 4),
            Text(
              destination.label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 34 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: context.qestoColors.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
