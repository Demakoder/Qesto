import 'package:flutter/services.dart';

class CapturedNotification {
  const CapturedNotification({
    required this.packageName,
    required this.notificationKey,
    required this.postedAt,
    required this.title,
    required this.text,
    this.deliveryVersion = '',
    this.bigText = '',
    this.subText = '',
    this.textLines = const [],
  });

  final String packageName;
  final String notificationKey;
  final DateTime postedAt;
  final String title;
  final String text;

  /// Opaque inbox revision, not the identity of a financial transaction.
  /// Empty identifies records captured before revision-aware acknowledgements.
  final String deliveryVersion;
  final String bigText;
  final String subText;
  final List<String> textLines;

  String get fullText => <String>{
    title.trim(),
    text.trim(),
    bigText.trim(),
    subText.trim(),
    ...textLines.map((value) => value.trim()),
  }.where((value) => value.isNotEmpty).join('\n');

  factory CapturedNotification.fromMap(Map<Object?, Object?> map) {
    return CapturedNotification(
      packageName: map['packageName'] as String? ?? '',
      notificationKey: map['notificationKey'] as String? ?? '',
      postedAt: DateTime.fromMillisecondsSinceEpoch(
        map['postedAt'] as int? ?? 0,
      ),
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
      deliveryVersion: map['deliveryVersion'] as String? ?? '',
      bigText: map['bigText'] as String? ?? '',
      subText: map['subText'] as String? ?? '',
      textLines:
          (map['textLines'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const [],
    );
  }
}

abstract interface class NotificationCaptureGateway {
  Future<bool> hasAccess();
  Future<void> openSettings();
  Future<List<CapturedNotification>> readNotifications();
  Future<void> clearNotifications();
  Future<void> removeNotification(
    String notificationKey, {
    required String expectedVersion,
  });
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
  Future<void> removeNotification(
    String notificationKey, {
    required String expectedVersion,
  }) {
    return _channel.invokeMethod<void>('removeNotification', {
      'notificationKey': notificationKey,
      'expectedVersion': expectedVersion,
    });
  }
}
