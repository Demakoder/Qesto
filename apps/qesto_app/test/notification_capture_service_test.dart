import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/notification_import/data/notification_capture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ru.qesto.qesto/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native storage errors cannot look like an empty inbox or a successful ack',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'notification_storage_unavailable');
      });
      const service = NotificationCaptureService();
      await expectLater(
        service.readNotifications(),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        service.removeNotification('key', expectedVersion: 'v1'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        service.clearNotifications(),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('native delivery revision survives read and acknowledgement', () async {
    Map<Object?, Object?>? acknowledgement;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readNotifications') {
        return [
          {'notificationKey': 'os-key', 'deliveryVersion': 'revision-2'},
          {'notificationKey': 'legacy-key'},
        ];
      }
      if (call.method == 'removeNotification') {
        acknowledgement = Map<Object?, Object?>.from(call.arguments as Map);
      }
      return null;
    });
    const service = NotificationCaptureService();
    final notifications = await service.readNotifications();
    expect(notifications.first.deliveryVersion, 'revision-2');
    expect(notifications.last.deliveryVersion, '');
    await service.removeNotification(
      notifications.first.notificationKey,
      expectedVersion: notifications.first.deliveryVersion,
    );
    expect(acknowledgement, {
      'notificationKey': 'os-key',
      'expectedVersion': 'revision-2',
    });
  });
}
