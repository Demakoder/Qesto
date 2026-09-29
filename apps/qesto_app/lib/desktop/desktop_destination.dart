import 'package:flutter/material.dart';

enum DesktopProductSection {
  budget('Бюджет', Icons.donut_large_rounded, Color(0xFF424A50)),
  benefits('Выгода', Icons.local_offer_outlined, Color(0xFF424A50)),
  capital('Капитал', Icons.account_balance_wallet_outlined, Color(0xFF424A50));

  const DesktopProductSection(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  DesktopDestination get landing => switch (this) {
    DesktopProductSection.budget => DesktopDestination.expenses,
    DesktopProductSection.benefits => DesktopDestination.benefits,
    DesktopProductSection.capital => DesktopDestination.liquidity,
  };
}

enum DesktopDestination {
  dashboard('Обзор', Icons.space_dashboard_outlined, null),
  expenses(
    'Расходы',
    Icons.trending_down_rounded,
    DesktopProductSection.budget,
  ),
  transactions('Операции', Icons.layers_outlined, DesktopProductSection.budget),
  budget(
    'План бюджета',
    Icons.pie_chart_outline_rounded,
    DesktopProductSection.budget,
  ),
  cashFlow(
    'Денежный поток',
    Icons.swap_vert_circle_outlined,
    DesktopProductSection.budget,
  ),
  rhythm(
    'Ритм жизни',
    Icons.calendar_view_week_rounded,
    DesktopProductSection.budget,
  ),
  merchants('Магазины', Icons.storefront_outlined, null),
  categories('Категории', Icons.category_outlined, null),
  recurring(
    'Регулярные',
    Icons.event_repeat_outlined,
    DesktopProductSection.budget,
  ),
  accounts('Счета', Icons.account_balance_wallet_outlined, null),
  insights('ИИ', Icons.auto_awesome_outlined, null),
  connections('Подключения', Icons.account_balance_outlined, null),
  benefits(
    'Предложения',
    Icons.local_offer_outlined,
    DesktopProductSection.benefits,
  ),
  liquidity(
    'Ликвидность',
    Icons.water_drop_outlined,
    DesktopProductSection.capital,
  ),
  investments(
    'Инвестиции',
    Icons.trending_up_rounded,
    DesktopProductSection.capital,
  ),
  debts('Долги', Icons.account_balance_outlined, DesktopProductSection.capital),
  goals('Цели', Icons.flag_outlined, DesktopProductSection.capital),
  settings('Настройки', Icons.settings_outlined, null);

  const DesktopDestination(this.label, this.icon, this.section);

  final String label;
  final IconData icon;
  final DesktopProductSection? section;
}
