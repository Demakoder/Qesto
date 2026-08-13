import 'package:flutter/services.dart';

class CapturedNotification {
  const CapturedNotification({
    required this.packageName,
    required this.notificationKey,
    required this.postedAt,
    required this.title,
    required this.text,
  });

  final String packageName;
  final String notificationKey;
  final DateTime postedAt;
  final String title;
  final String text;

  factory CapturedNotification.fromMap(Map<Object?, Object?> map) {
    return CapturedNotification(
      packageName: map['packageName'] as String? ?? '',
      notificationKey: map['notificationKey'] as String? ?? '',
      postedAt: DateTime.fromMillisecondsSinceEpoch(
        map['postedAt'] as int? ?? 0,
      ),
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
    );
  }
}

abstract interface class NotificationCaptureGateway {
  Future<bool> hasAccess();
  Future<void> openSettings();
  Future<List<CapturedNotification>> readNotifications();
  Future<void> clearNotifications();
  Future<void> removeNotification(String notificationKey);
  Stream<void> get notificationEvents;
}

class NotificationCaptureService implements NotificationCaptureGateway {
  const NotificationCaptureService();

  static const _channel = MethodChannel('ru.qesto.qesto/notifications');
  static const _events = EventChannel('ru.qesto.qesto/notification_events');

  @override
  Stream<void> get notificationEvents =>
      _events.receiveBroadcastStream().map<void>((_) {});

  @override
  Future<bool> hasAccess() async {
    return await _channel.invokeMethod<bool>('hasAccess') ?? false;
  }

  @override
  Future<void> openSettings() {
    return _channel.invokeMethod<void>('openSettings');
  }

  @override
  Future<List<CapturedNotification>> readNotifications() async {
    final items = await _channel.invokeListMethod<Object?>('readNotifications');

    return (items ?? const [])
        .map(
          (item) => CapturedNotification.fromMap(
            Map<Object?, Object?>.from(item as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> clearNotifications() {
    return _channel.invokeMethod<void>('clearNotifications');
  }

  @override
  Future<void> removeNotification(String notificationKey) {
    return _channel.invokeMethod<void>('removeNotification', {
      'notificationKey': notificationKey,
    });
  }
}
