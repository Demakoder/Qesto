import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../desktop_financial_helpers.dart';
import '../widgets/desktop_charts.dart';
import '../widgets/desktop_components.dart';

class DesktopAccountsPage extends StatefulWidget {
  const DesktopAccountsPage({required this.controller, super.key});
  final BudgetController controller;

  @override
  State<DesktopAccountsPage> createState() => _DesktopAccountsPageState();
}

class _DesktopAccountsPageState extends State<DesktopAccountsPage> {
  String? _openedAccountId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final accounts = widget.controller.accounts;
        if (accounts.isEmpty) {
          return DesktopEmptyState(
            title: 'Здесь появятся ваши счета',
            message:
                'Добавьте первый источник данных, чтобы Qesto начала собирать финансовую картину.',
            icon: Icons.account_balance_wallet_outlined,
            action: FilledButton.icon(
              onPressed: () => _showAddAccount(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить счёт'),
            ),
          );
        }
        final currency = accounts.first.currency;
        final state = widget.controller.financialState;
        final netWorth =
            (state.assets.minorUnits - state.debts.minorUnits) ~/ 100;
        final opened = accounts.cast<QestoAccount?>().firstWhere(
          (item) => item?.id == _openedAccountId,
          orElse: () => null,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 28),
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DesktopCard(
                        color: const Color(0xFF172A4A),
                        borderColor: const Color(0xFF172A4A),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Чистый капитал',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    formatMoney(netWorth, currency),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    'Активы ${formatMoney(state.assets.minorUnits ~/ 100, currency)} · Долги ${formatMoney(state.debts.minorUnits ~/ 100, currency)}',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(
                              width: 260,
                              height: 72,
                              child: DesktopSparkline(
                                values: [
                                  512,
                                  518,
                                  526,
                                  530,
                                  544,
                                  552,
                                  548,
                                  569,
                                  581,
                                  590,
                                  604,
                                  624,
                                ],
                                color: Color(0xFF77D98D),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final group in _groups(accounts)) ...[
                        Row(
                          children: [
                            Text(
                              group.label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              formatMoney(
                                group.accounts.fold<int>(
                                  0,
                                  (sum, item) => sum + item.balance,
                                ),
                                currency,
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth > 980 ? 3 : 2;
                            const gap = 13.0;
                            final width =
                                (constraints.maxWidth - gap * (columns - 1)) /
                                columns;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final account in group.accounts)
                                  SizedBox(
                                    width: width,
                                    height: 150,
                                    child: _AccountCard(
                                      controller: widget.controller,
                                      account: account,
                                      onTap: () => setState(
                                        () => _openedAccountId = account.id,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                      ],
                      OutlinedButton.icon(
                        onPressed: () => _showAddAccount(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Добавить счёт / актив / долг'),
                      ),
                    ],
                  ),
                ),
              ),
              if (opened != null)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: 350,
                  child: _AccountDrawer(
                    controller: widget.controller,
                    account: opened,
                    onClose: () => setState(() => _openedAccountId = null),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<_AccountGroup> _groups(List<QestoAccount> accounts) {
    final groups = <_AccountGroup>[
      _AccountGroup(
        'Деньги',
        accounts
            .where(
              (item) =>
                  {AccountType.cash, AccountType.bankCard}.contains(item.type),
            )
            .toList(),
      ),
      _AccountGroup(
        'Накопления',
        accounts
            .where(
              (item) => {
                AccountType.savings,
                AccountType.deposit,
              }.contains(item.type),
            )
            .toList(),
      ),
      _AccountGroup(
        'Инвестиции',
        accounts.where((item) => item.type == AccountType.investment).toList(),
      ),
      _AccountGroup(
        'Обязательства',
        accounts.where((item) => item.type == AccountType.liability).toList(),
      ),
      _AccountGroup(
        'Другие активы',
        accounts
            .where(
              (item) => {
                AccountType.receivable,
                AccountType.other,
              }.contains(item.type),
            )
            .toList(),
      ),
    ];
    return groups.where((group) => group.accounts.isNotEmpty).toList();
  }

  Future<void> _showAddAccount(BuildContext context) async {
    final name = TextEditingController();
    final balance = TextEditingController();
    var type = AccountType.bankCard;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Добавить объект капитала'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: balance,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*')),
                  ],
                  decoration: const InputDecoration(labelText: 'Баланс'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountType>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(
                      value: AccountType.bankCard,
                      child: Text('Банковская карта'),
                    ),
                    DropdownMenuItem(
                      value: AccountType.cash,
                      child: Text('Наличные'),
                    ),
                    DropdownMenuItem(
                      value: AccountType.savings,
                      child: Text('Накопления'),
                    ),
                    DropdownMenuItem(
                      value: AccountType.deposit,
                      child: Text('Вклад'),
                    ),
                    DropdownMenuItem(
                      value: AccountType.investment,
                      child: Text('Инвестиции'),
                    ),
                    DropdownMenuItem(
                      value: AccountType.liability,
                      child: Text('Долг / кредит'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => type = value);
                  },
                  decoration: const InputDecoration(labelText: 'Тип'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (result == true && name.text.trim().isNotEmpty) {
      await widget.controller.addAccount(
        title: name.text.trim(),
        balance: int.tryParse(balance.text) ?? 0,
        type: type,
      );
    }
    name.dispose();
    balance.dispose();
  }
}

class _AccountGroup {
  const _AccountGroup(this.label, this.accounts);
  final String label;
  final List<QestoAccount> accounts;
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.controller,
    required this.account,
    required this.onTap,
  });
  final BudgetController controller;
  final QestoAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final transactions =
        controller.transactions
            .where((item) => item.accountId == account.id)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final values = <double>[account.balance.toDouble()];
    var running = account.balance.toDouble();
    for (final item in transactions.reversed.take(8)) {
      running -= desktopSignedAmount(item);
      values.insert(0, running);
    }
    return DesktopCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon(account.type), size: 19, color: QestoColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  account.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: QestoColors.secondaryText,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            formatMoney(account.balance, account.currency),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: account.balance < 0
                  ? QestoColors.negative
                  : QestoColors.text,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 30,
            child: DesktopSparkline(
              values: values,
              color: account.balance < 0
                  ? QestoColors.negative
                  : QestoColors.primary,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Synoball · обновлено локально',
            style: TextStyle(color: QestoColors.secondaryText, fontSize: 9),
          ),
        ],
      ),
    );
  }

  IconData _icon(AccountType type) => switch (type) {
    AccountType.cash => Icons.payments_outlined,
    AccountType.bankCard => Icons.credit_card_outlined,
    AccountType.savings => Icons.savings_outlined,
    AccountType.deposit => Icons.account_balance_outlined,
    AccountType.investment => Icons.candlestick_chart_outlined,
    AccountType.liability => Icons.receipt_long_outlined,
    _ => Icons.account_balance_wallet_outlined,
  };
}

class _AccountDrawer extends StatelessWidget {
  const _AccountDrawer({
    required this.controller,
    required this.account,
    required this.onClose,
  });
  final BudgetController controller;
  final QestoAccount account;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final transactions =
        controller.transactions
            .where((item) => item.accountId == account.id)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return Material(
      elevation: 16,
      color: QestoColors.surface,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 58,
            child: Row(
              children: [
                const SizedBox(width: 18),
                const Expanded(
                  child: Text(
                    'Детали счёта',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  account.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  formatMoney(account.balance, account.currency),
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    color: account.balance < 0
                        ? QestoColors.negative
                        : QestoColors.text,
                  ),
                ),
                const SizedBox(height: 18),
                DesktopCard(
                  color: QestoColors.surfaceSecondary,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Состояние источника',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const DesktopPill(
                        label: 'Локальные данные доступны',
                        icon: Icons.check_circle_outline_rounded,
                        color: QestoColors.positive,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${transactions.length} операций связано со счётом',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Последние операции',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 9),
                for (final transaction in transactions.take(7))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            desktopTransactionTitle(transaction),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          formatMoney(
                            desktopSignedAmount(transaction),
                            transaction.currency,
                            showSign: true,
                          ),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: desktopAmountColor(transaction),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
