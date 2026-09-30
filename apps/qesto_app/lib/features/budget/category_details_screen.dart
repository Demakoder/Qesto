import 'package:flutter/material.dart';

import '../../data/models/qesto_models.dart';
import '../statistics/presentation/screens/statistics_drilldown_screens.dart';
import '../statistics/presentation/state/statistics_controller.dart';
import 'state/budget_controller.dart';

/// The budget and analytics entry points share one category detail experience.
/// A private statistics controller keeps the selected budget period fixed
/// without changing the global analytics filters.
class CategoryDetailsScreen extends StatefulWidget {
  const CategoryDetailsScreen({
    required this.controller,
    required this.period,
    required this.categoryId,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final String categoryId;

  @override
  State<CategoryDetailsScreen> createState() => _CategoryDetailsScreenState();
}

class _CategoryDetailsScreenState extends State<CategoryDetailsScreen> {
  late StatisticsController _statistics;

  @override
  void initState() {
    super.initState();
    _createStatistics();
  }

  void _createStatistics() {
    _statistics = StatisticsController(budgetController: widget.controller);
    _statistics.setCustomPeriod(widget.period.startDate, widget.period.endDate);
  }

  @override
  void didUpdateWidget(covariant CategoryDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _statistics.dispose();
      _createStatistics();
    } else if (oldWidget.period.id != widget.period.id) {
      _statistics.setCustomPeriod(
        widget.period.startDate,
        widget.period.endDate,
      );
    }
  }

  @override
  void dispose() {
    _statistics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StatisticsCategoryScreen(
    controller: _statistics,
    categoryId: widget.categoryId,
    budgetPeriod: widget.period,
  );
}
