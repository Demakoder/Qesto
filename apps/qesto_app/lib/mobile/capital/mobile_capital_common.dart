import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/capital/domain/account_capital_service.dart';
import '../../features/capital/domain/investment_analytics_service.dart';
import '../../features/capital/domain/debt_analytics_service.dart';
import '../../features/capital/domain/goal_planning_service.dart';
import '../analytics/mobile_financial_widgets.dart';
export '../../features/capital/domain/account_capital_service.dart';
export '../../features/capital/domain/investment_analytics_service.dart';
export '../../features/capital/domain/debt_analytics_service.dart';
export '../../features/capital/domain/goal_planning_service.dart';

// Read-only wiring, not a second financial engine. Arguments mirror desktop.
AccountCapitalSnapshot mobileLiquidity(BudgetController c, CapitalPeriod p) =>
    const AccountCapitalService().calculate(
      accounts: c.accounts,
      accountPreferences: c.accountPreferences,
      transactions: c.transactions,
      upcomingExpenses: c.upcomingExpenses,
      savingsGoals: c.savingsGoals,
      goalAllocations: c.goalAllocations,
      debts: c.debts,
      synoballState: c.synoballState,
      asOf: c.referenceDate,
      period: p,
      baseCurrency: c.user.defaultCurrency,
    );
InvestmentPortfolioSnapshot mobileInvestments(
  BudgetController c,
  InvestmentPeriod p,
) => const InvestmentAnalyticsService().calculate(
  accounts: c.investmentAccounts,
  balanceSnapshots: c.investmentBalanceSnapshots,
  contributions: c.investmentContributions,
  asOf: c.referenceDate,
  period: p,
  baseCurrency: c.user.defaultCurrency,
);
DebtPortfolioSnapshot mobileDebts(BudgetController c, DebtAnalyticsPeriod p) =>
    const DebtAnalyticsService().calculate(
      debts: c.debts,
      balanceSnapshots: c.debtBalanceSnapshots,
      debtPayments: c.debtPayments,
      transactions: c.transactions,
      asOf: c.referenceDate,
      period: p,
      baseCurrency: c.user.defaultCurrency,
    );
GoalPortfolioPlan mobileGoals(BudgetController c) =>
    const GoalPlanningService().calculate(
      goals: c.savingsGoals,
      allocations: c.goalAllocations,
      contributions: c.goalContributions,
      asOf: c.referenceDate,
      baseCurrency: c.user.defaultCurrency,
    );
GoalPlan mobileGoal(BudgetController c, SavingsGoal goal) =>
    const GoalPlanningService().calculateGoal(
      goal: goal,
      allocations: c.goalAllocations.where((a) => a.goalId == goal.id).toList(),
      contributions: c.goalContributions
          .where((a) => a.goalId == goal.id)
          .toList(),
      asOf: c.referenceDate,
    );

Future<T?> capitalPush<T>(BuildContext context, String name, Widget page) =>
    Navigator.of(context).push<T>(
      MaterialPageRoute(
        settings: RouteSettings(name: name),
        builder: (_) => page,
      ),
    );

class CapitalPage extends StatelessWidget {
  const CapitalPage({
    required this.title,
    required this.controller,
    required this.builder,
    this.actions = const [],
    super.key,
  });
  final String title;
  final BudgetController controller;
  final WidgetBuilder builder;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => builder(context),
      ),
    ),
  );
}

class CapitalRows extends StatelessWidget {
  const CapitalRows({required this.items, this.storageKey, super.key});
  final List<Widget Function()> items;
  final String? storageKey;
  @override
  Widget build(BuildContext context) => ListView.builder(
    key: PageStorageKey(storageKey ?? 'capital-list'),
    padding: const EdgeInsets.all(16),
    itemCount: items.length,
    itemBuilder: (_, i) => items[i](),
  );
}

// Presentation labels only; enums and calculations remain owned by the core.
String capitalStatus(String value) =>
    const {
      'current': 'актуально',
      'needsUpdate': 'нужно обновить',
      'partial': 'частичные данные',
      'manual': 'введено вручную',
      'aging': 'давно обновлялось',
      'stale': 'устарело',
      'normal': 'в пределах оценки',
      'attention': 'требует внимания',
      'critical': 'низкий остаток',
      'unknown': 'нет достаточных данных',
      'verified': 'проверено',
      'estimated': 'оценка',
      'incomplete': 'неполные данные',
      'annuity': 'аннуитет',
      'differentiated': 'дифференцированная схема',
      'api': 'интеграция',
      'bank': 'банк',
      'statement': 'выписка',
      'brokerStatement': 'отчёт брокера',
      'calculated': 'расчёт',
      'transaction': 'операция',
    }[value] ??
    value;

Widget capitalLink(
  String title,
  VoidCallback onTap, {
  String? subtitle,
  Key? key,
  IconData icon = Icons.chevron_right,
}) => ListTile(
  key: key,
  contentPadding: EdgeInsets.zero,
  title: Text(title),
  subtitle: subtitle == null ? null : Text(subtitle),
  trailing: Icon(icon),
  onTap: onTap,
);
Widget capitalNote(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: Text(text),
);
Widget capitalEmpty(String text, String action, VoidCallback onTap) =>
    MobileSection(
      title: text,
      child: FilledButton(onPressed: onTap, child: Text(action)),
    );
Widget capitalProgress(double value, {bool hidden = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: hidden
      ? const Text('Суммы скрыты')
      : LinearProgressIndicator(value: value.clamp(0, 1)),
);
Widget capitalPrivacy(bool hidden, VoidCallback onTap) => IconButton(
  key: const Key('capital-privacy'),
  tooltip: hidden ? 'Показать суммы' : 'Скрыть суммы',
  onPressed: onTap,
  icon: Icon(
    hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
  ),
);

class CapitalExactMoney extends StatelessWidget {
  const CapitalExactMoney(
    this.minor,
    this.currency, {
    this.hidden = false,
    super.key,
  });
  final int minor;
  final String currency;
  final bool hidden;
  @override
  Widget build(BuildContext context) => Semantics(
    label: hidden ? 'Сумма скрыта' : formatMinorMoney(minor, currency),
    child: ExcludeSemantics(
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            hidden ? '••••' : formatMinorMoney(minor, currency),
            style: QestoTypography.moneyLarge.copyWith(
              fontSize: 32,
              color: minor < 0 ? context.qestoColors.negative : null,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Chart-only view tuples: all dates/values originate in existing services.
typedef CapitalChartPoint = ({DateTime date, int amount, bool confirmed});

class MobileCapitalHistory extends StatefulWidget {
  const MobileCapitalHistory({
    required this.points,
    required this.currency,
    this.hidden = false,
    super.key,
  });
  final List<CapitalChartPoint> points;
  final String currency;
  final bool hidden;
  @override
  State<MobileCapitalHistory> createState() => _MobileCapitalHistoryState();
}

class _MobileCapitalHistoryState extends State<MobileCapitalHistory> {
  CapitalChartPoint? _selected;
  void _select(double x, double width) {
    if (widget.points.isEmpty) return;
    final index = (x / width * (widget.points.length - 1)).round().clamp(
      0,
      widget.points.length - 1,
    );
    setState(() => _selected = widget.points[index]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) return const Text('История скрыта');
    if (widget.points.isEmpty) return const Text('Истории пока нет');
    final selected =
        widget.points.where((p) => p == _selected).firstOrNull ??
        widget.points.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              'История. ${formatDate(selected.date, includeYear: true)}: ${formatMoney(selected.amount, widget.currency)}. Доступен список значений.',
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              key: const Key('capital-history-touch'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) =>
                  _select(d.localPosition.dx, constraints.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _select(d.localPosition.dx, constraints.maxWidth),
              child: SizedBox(
                height: 160,
                child: CustomPaint(
                  painter: _CapitalHistoryPainter(
                    widget.points,
                    selected,
                    QestoColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          '${formatDate(selected.date, includeYear: true)} · ${formatMoney(selected.amount, widget.currency)}',
          key: const Key('capital-history-selected'),
        ),
        Text(
          selected.confirmed
              ? 'Подтверждённая точка'
              : 'Расчётная история / оценка',
          style: const TextStyle(fontSize: 12),
        ),
        TextButton(
          onPressed: () => capitalPush(
            context,
            '/capital/history/list',
            Scaffold(
              appBar: AppBar(title: const Text('История: даты и суммы')),
              body: ListView.builder(
                itemCount: widget.points.length,
                itemBuilder: (_, i) {
                  final p = widget.points[widget.points.length - i - 1];
                  return MobileValueRow(
                    title: formatDate(p.date, includeYear: true),
                    caption: p.confirmed ? 'Подтверждено' : 'Расчёт / оценка',
                    amount: p.amount,
                    currency: widget.currency,
                  );
                },
              ),
            ),
          ),
          child: const Text('Даты и суммы списком'),
        ),
      ],
    );
  }
}

class _CapitalHistoryPainter extends CustomPainter {
  _CapitalHistoryPainter(this.points, this.selected, this.color);
  final List<CapitalChartPoint> points;
  final CapitalChartPoint selected;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final low = points.map((p) => p.amount).reduce(math.min);
    final high = points.map((p) => p.amount).reduce(math.max);
    final span = math.max(1, high - low);
    Offset xy(int i) => Offset(
      points.length == 1
          ? size.width / 2
          : i / (points.length - 1) * size.width,
      12 + (1 - (points[i].amount - low) / span) * (size.height - 24),
    );
    final grid = Paint()
      ..color = color.withValues(alpha: .12)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = 12 + i * (size.height - 24) / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path()..moveTo(xy(0).dx, xy(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(xy(i).dx, xy(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    final i = points.indexWhere((p) => p == selected);
    if (i >= 0) canvas.drawCircle(xy(i), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CapitalHistoryPainter old) =>
      old.points != points || old.selected != selected || old.color != color;
}
