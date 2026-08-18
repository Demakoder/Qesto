import '../../budget/state/budget_controller.dart';
import '../../../data/models/qesto_models.dart';
import '../data/notification_capture_service.dart';
import 'bank_notification_parser.dart';

class AutomaticNotificationImportResult {
  const AutomaticNotificationImportResult({
    this.created = 0,
    this.merged = 0,
    this.unsupported = 0,
    this.failed = 0,
  });

  final int created;
  final int merged;
  final int unsupported;
  final int failed;

  AutomaticNotificationImportResult operator +(
    AutomaticNotificationImportResult other,
  ) => AutomaticNotificationImportResult(
    created: created + other.created,
    merged: merged + other.merged,
    unsupported: unsupported + other.unsupported,
    failed: failed + other.failed,
  );
}

/// Drains recognised Android bank notifications into Synoball without a
/// confirmation step. The native inbox item is acknowledged only after the
/// canonical state has been persisted successfully.
class AutomaticNotificationImporter {
  AutomaticNotificationImporter({
    required this.controller,
    this.captureService = const NotificationCaptureService(),
    this.parser = const SberbankNotificationParser(),
  });

  final BudgetController controller;
  final NotificationCaptureGateway captureService;
  final BankNotificationParser parser;

  Future<AutomaticNotificationImportResult>? _activeDrain;
  var _rerunRequested = false;

  Future<AutomaticNotificationImportResult> drain() {
    final active = _activeDrain;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }

    final future = _drainUntilIdle();
    _activeDrain = future;
    return future.whenComplete(() => _activeDrain = null);
  }

  Future<AutomaticNotificationImportResult> _drainUntilIdle() async {
    var total = const AutomaticNotificationImportResult();
    do {
      _rerunRequested = false;
      total += await _drainOnce();
    } while (_rerunRequested);
    return total;
  }

  Future<AutomaticNotificationImportResult> _drainOnce() async {
    try {
      if (!await captureService.hasAccess()) {
        return const AutomaticNotificationImportResult();
      }
    } on Object {
      // The channel is intentionally unavailable on desktop and web.
      return const AutomaticNotificationImportResult();
    }

    late final List<CapturedNotification> notifications;
    try {
      notifications = await captureService.readNotifications();
    } on Object {
      return const AutomaticNotificationImportResult(failed: 1);
    }

    var created = 0;
    var merged = 0;
    var unsupported = 0;
    var failed = 0;
    for (final notification in notifications) {
      final transaction = parser.parse(notification);
      if (transaction == null) {
        unsupported += 1;
        try {
          // Unsupported text has no future value to Qesto and may still
          // contain account fragments or balances. Do not retain it until TTL.
          await captureService.removeNotification(notification.notificationKey);
        } on Object {
          failed += 1;
        }
        continue;
      }

      try {
        final period = controller.periodForOrCreate(transaction.date);
        final account = controller.accounts.firstWhere(
          (item) => item.type != AccountType.liability,
          orElse: () => controller.accounts.first,
        );
        final outcome = await controller.addAndroidNotificationExpense(
          period: period,
          amountMinor: transaction.amountMinor,
          date: transaction.date,
          categoryId: transaction.categoryId,
          accountId: account.id,
          title: transaction.merchant,
          notificationKey: notification.notificationKey,
          packageName: notification.packageName,
          rawNotification: '${notification.title}\n${notification.text}',
          subcategoryId: transaction.subcategoryId,
          confidence: transaction.confidence,
        );
        created += outcome.createdTransactionIds.length;
        merged += outcome.matchedTransactionIds.length;

        // Removing the inbox record is the acknowledgement. If it fails, the
        // stable notification key makes the next retry idempotent.
        await captureService.removeNotification(notification.notificationKey);
      } on Object {
        failed += 1;
      }
    }
    return AutomaticNotificationImportResult(
      created: created,
      merged: merged,
      unsupported: unsupported,
      failed: failed,
    );
  }
}
