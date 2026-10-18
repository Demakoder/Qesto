import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../features/notification_import/data/notification_capture_service.dart';

/// Presentation-only status for the Android notification inbox.
///
/// It never parses, acknowledges, imports or edits financial data. The count is
/// the number of persisted raw notifications, not a count of transactions.
class MobileSourceAttentionController extends ChangeNotifier
    with WidgetsBindingObserver {
  MobileSourceAttentionController({
    required this.gateway,
    required this.supported,
  });

  final NotificationCaptureGateway gateway;
  final bool supported;

  StreamSubscription<void>? _events;
  Future<void>? _activeRefresh;
  bool _refreshRequested = false;
  bool _started = false;
  bool _disposed = false;
  bool? _hasAccess;
  int _pendingCount = 0;
  int _failedCount = 0;
  bool _isLoading = false;
  bool _isOpeningSettings = false;
  String? _refreshError;
  String? _eventError;
  String? _settingsError;
  DateTime? _lastUpdated;

  bool? get hasPermission => _hasAccess;
  bool get permissionDenied => supported && _hasAccess == false;
  int get pendingCount => _pendingCount;
  int get failedCount => _failedCount;
  bool get isLoading => _isLoading;
  bool get isOpeningSettings => _isOpeningSettings;
  DateTime? get lastUpdated => _lastUpdated;
  String? get error => _settingsError ?? _refreshError ?? _eventError;
  bool get needsAttention =>
      supported &&
      (permissionDenied ||
          pendingCount > 0 ||
          failedCount > 0 ||
          error != null);

  /// Report only the existing importer's result; this does not retry imports.
  /// A successful later drain clears the last failed-attempt status.
  void reportImportFailures(int count) {
    if (_disposed || !supported) return;
    final next = count < 0 ? 0 : count;
    if (_failedCount == next) return;
    _failedCount = next;
    notifyListeners();
  }

  /// Mirror a failure of the host's single native event subscription.
  /// Reading the inbox successfully does not prove that stream is connected.
  /// Keep the warning for this controller's lifetime rather than claiming heal.
  void reportEventFailure() {
    if (_disposed || !supported) return;
    const message =
        'Не удалось получать обновления уведомлений. '
        'Проверьте статус вручную.';
    if (_eventError == message) return;
    _eventError = message;
    notifyListeners();
  }

  /// Subscribe once. Unsupported platforms never call the Android channels.
  /// A host already observing the native EventChannel must set [listenEvents]
  /// to false and refresh after its existing import listener finishes.
  Future<void> start({bool listenEvents = true}) {
    if (_disposed || _started) {
      return _activeRefresh ?? Future<void>.value();
    }
    _started = true;
    if (!supported) return Future<void>.value();
    WidgetsBinding.instance.addObserver(this);
    if (listenEvents) {
      try {
        _events = gateway.notificationEvents.listen(
          (_) => unawaited(refresh()),
          onError: (Object _, StackTrace _) => reportEventFailure(),
        );
      } on Object {
        _eventError =
            'Не удалось подключить обновления уведомлений. '
            'Проверьте статус вручную.';
      }
    }
    return refresh();
  }

  /// Coalesce simultaneous calls, but read again after an event during a read.
  /// The inbox may be drained independently by the existing importer.
  Future<void> refresh() {
    if (_disposed || !supported) return Future<void>.value();
    final active = _activeRefresh;
    if (active != null) {
      _refreshRequested = true;
      return active;
    }
    final future = _refreshUntilIdle();
    _activeRefresh = future;
    return future.whenComplete(() {
      if (identical(_activeRefresh, future)) _activeRefresh = null;
    });
  }

  Future<void> _refreshUntilIdle() async {
    _isLoading = true;
    notifyListeners();
    do {
      _refreshRequested = false;
      await _readSnapshot();
    } while (_refreshRequested && !_disposed);
    if (_disposed) return;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _readSnapshot() async {
    String? failure;
    try {
      final access = await gateway.hasAccess();
      if (_disposed) return;
      _hasAccess = access;
    } on Object {
      failure = 'Не удалось проверить доступ к уведомлениям.';
    }
    if (_disposed) return;
    try {
      // A revoked permission does not erase already captured inbox records.
      final notifications = await gateway.readNotifications();
      if (_disposed) return;
      _pendingCount = notifications.length;
    } on Object {
      failure =
          'Не удалось прочитать входящие уведомления. '
          'Показан последний доступный статус.';
    }
    if (_disposed) return;
    _refreshError = failure;
    if (failure == null) _lastUpdated = DateTime.now();
  }

  Future<void> openPermissionSettings() async {
    if (_disposed || !supported || _isOpeningSettings) return;
    _isOpeningSettings = true;
    _settingsError = null;
    notifyListeners();
    try {
      await gateway.openSettings();
    } on Object {
      if (!_disposed) {
        _settingsError = 'Не удалось открыть настройки доступа к уведомлениям.';
      }
    } finally {
      if (!_disposed) {
        _isOpeningSettings = false;
        notifyListeners();
      }
    }
    // Android returns before the user changes settings. Refresh on resume.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed && supported) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started && supported) WidgetsBinding.instance.removeObserver(this);
    final events = _events;
    if (events != null) unawaited(events.cancel());
    super.dispose();
  }
}
