import 'dart:async';

/// Async work inherits this lease through its Zone. Cancelling a Future alone
/// does not revoke side effects; financial entry points must check this lease.
class FinancialWriteGuard {
  static final Object _key = Object();
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  static void check() {
    final guard = Zone.current[_key] as FinancialWriteGuard?;
    if (guard?._cancelled == true) {
      throw FinancialWriteCancelled();
    }
  }

  Future<T> run<T>(Future<T> Function() body) => runZoned(() async {
    check();
    return await body();
  }, zoneValues: {_key: this});
}

class FinancialWriteCancelled extends StateError {
  FinancialWriteCancelled() : super('Financial operation cancelled');
}
