import 'package:flutter/widgets.dart';
import '../statistics/presentation/state/statistics_controller.dart';

/// Mobile presentation routing only. Exact canonical IDs are forwarded;
/// desktop has no scope and continues to use its current presentation.
class TransactionRouteScope extends InheritedWidget {
  const TransactionRouteScope({
    required this.openTransaction,
    required this.openAttention,
    required super.child,
    super.key,
  });
  final ValueChanged<String> openTransaction;
  final void Function([StatisticsController? origin]) openAttention;
  static TransactionRouteScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TransactionRouteScope>();
  @override
  bool updateShouldNotify(TransactionRouteScope oldWidget) =>
      openTransaction != oldWidget.openTransaction ||
      openAttention != oldWidget.openAttention;
}
