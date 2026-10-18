import 'package:flutter/material.dart';

/// Presentation destinations only. No persisted financial identifiers.
enum MobileRoot {
  dashboard('Обзор', Icons.space_dashboard_outlined),
  transactions('Операции', Icons.receipt_long_outlined),
  budget('Бюджет', Icons.pie_chart_outline_rounded),
  capital('Капитал', Icons.account_balance_wallet_outlined);

  const MobileRoot(this.label, this.icon);

  final String label;
  final IconData icon;
}
