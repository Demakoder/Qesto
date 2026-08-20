import 'package:flutter/material.dart';

enum DesktopProductSection {
  budget('Бюджет', Icons.donut_large_rounded, Color(0xFF3478F6)),
  benefits('Выгода', Icons.local_offer_outlined, Color(0xFFFF9F43)),
  savings('Накопления', Icons.savings_outlined, Color(0xFF8D63F6));

  const DesktopProductSection(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  DesktopDestination get landing => switch (this) {
    DesktopProductSection.budget => DesktopDestination.expenses,
    DesktopProductSection.benefits => DesktopDestination.benefits,
    DesktopProductSection.savings => DesktopDestination.goals,
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
  merchants(
    'Магазины',
    Icons.storefront_outlined,
    DesktopProductSection.budget,
  ),
  categories(
    'Категории',
    Icons.category_outlined,
    DesktopProductSection.budget,
  ),
  recurring(
    'Регулярные',
    Icons.event_repeat_outlined,
    DesktopProductSection.budget,
  ),
  accounts(
    'Счета',
    Icons.account_balance_wallet_outlined,
    null,
  ),
  insights(
    'Наблюдения',
    Icons.auto_awesome_outlined,
    DesktopProductSection.budget,
  ),
  benefits(
    'Предложения',
    Icons.local_offer_outlined,
    DesktopProductSection.benefits,
  ),
  goals('Цели', Icons.flag_outlined, DesktopProductSection.savings),
  capital('Капитал', Icons.show_chart_rounded, DesktopProductSection.savings),
  settings('Настройки', Icons.settings_outlined, null);

  const DesktopDestination(this.label, this.icon, this.section);

  final String label;
  final IconData icon;
  final DesktopProductSection? section;
}
