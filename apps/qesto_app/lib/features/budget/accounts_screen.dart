import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/nested_screen_header.dart';
import '../../core/widgets/qesto_card.dart';
import '../../core/widgets/qesto_elements.dart';
import '../../data/models/qesto_models.dart';

class CapitalScreen extends StatelessWidget {
  const CapitalScreen({required this.accounts, super.key});

  final List<QestoAccount> accounts;

  IconData _iconFor(AccountType type) => switch (type) {
    AccountType.cash => Icons.payments_rounded,
    AccountType.bankCard => Icons.credit_card_rounded,
    AccountType.savings => Icons.savings_rounded,
    AccountType.deposit => Icons.account_balance_rounded,
    AccountType.investment => Icons.candlestick_chart_rounded,
    AccountType.receivable => Icons.handshake_rounded,
    AccountType.liability => Icons.receipt_long_rounded,
    AccountType.other => Icons.account_balance_wallet_rounded,
  };

  int _sum(Iterable<AccountType> types) => accounts
      .where((account) => types.contains(account.type))
      .fold(0, (sum, account) => sum + account.balance);

  @override
  Widget build(BuildContext context) {
    final currency = accounts.firstOrNull?.currency ?? 'RUB';
    final available = _sum([AccountType.cash, AccountType.bankCard]);
    final deposits = _sum([AccountType.savings, AccountType.deposit]);
    final investments = _sum([AccountType.investment]);
    final receivables = _sum([AccountType.receivable]);
    final liabilities = _sum([AccountType.liability]).abs();
    final netCapital = accounts.fold(
      0,
      (sum, account) => sum + account.balance,
    );
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text('Капитал', style: Theme.of(context).textTheme.titleLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          QestoCard(
            color: context.qestoColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Чистый капитал',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                AmountText(
                  formatMoney(netCapital, currency),
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Все активы за вычетом обязательств',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          QestoCard(
            child: Column(
              children: [
                _CapitalMetric(
                  label: 'Доступные средства',
                  amount: available,
                  currency: currency,
                  color: context.qestoColors.primary,
                ),
                _CapitalMetric(
                  label: 'Вклады и накопления',
                  amount: deposits,
                  currency: currency,
                  color: context.qestoColors.green,
                ),
                _CapitalMetric(
                  label: 'Инвестиции',
                  amount: investments,
                  currency: currency,
                  color: context.qestoColors.purple,
                ),
                _CapitalMetric(
                  label: 'Мне должны',
                  amount: receivables,
                  currency: currency,
                  color: context.qestoColors.orange,
                ),
                _CapitalMetric(
                  label: 'Мои обязательства',
                  amount: liabilities,
                  currency: currency,
                  color: context.qestoColors.danger,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Состав капитала',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          for (final account in accounts) ...[
            QestoCard(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${account.title}: подробности появятся позднее',
                  ),
                ),
              ),
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.qestoColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFor(account.type),
                      color: context.qestoColors.primary,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      account.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    formatMoney(account.balance, account.currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: account.balance < 0
                          ? context.qestoColors.danger
                          : context.qestoColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          QestoButton(
            label: 'Добавить объект капитала',
            icon: Icons.add_circle_rounded,
            style: QestoButtonStyle.secondary,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Форма будет добавлена позднее')),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapitalMetric extends StatelessWidget {
  const _CapitalMetric({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
  });

  final String label;
  final int amount;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            formatMoney(amount, currency),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
