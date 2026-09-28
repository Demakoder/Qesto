import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/desktop/desktop_app_shell.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/mocks/fixtures/mock_deals.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notificationChannel = MethodChannel('ru.qesto.qesto/notifications');
  const statementChannel = MethodChannel('ru.qesto.qesto/statements');
  const receiptChannel = MethodChannel('ru.qesto.qesto/receipts');
  const voiceChannel = MethodChannel('ru.qesto.qesto/voice');
  late List<Map<String, Object?>> mockNotifications;
  Map<String, Object?>? mockStatement;
  String? mockReceiptQr;
  Map<String, Object?>? mockReceiptDocument;
  Map<String, Object?>? mockVoiceRecognition;

  setUp(() {
    mockNotifications = [];
    mockStatement = null;
    mockReceiptQr = null;
    mockReceiptDocument = null;
    mockVoiceRecognition = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (call) async {
          if (call.method == 'removeNotification') {
            final arguments = Map<Object?, Object?>.from(call.arguments as Map);
            mockNotifications.removeWhere(
              (item) =>
                  item['notificationKey'] == arguments['notificationKey'] &&
                  (item['deliveryVersion'] ?? '') ==
                      arguments['expectedVersion'],
            );
            return null;
          }
          return switch (call.method) {
            'hasAccess' => true,
            'readNotifications' => mockNotifications,
            'clearNotifications' => null,
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(statementChannel, (call) async {
          return call.method == 'pickPdf' ? mockStatement : null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(receiptChannel, (call) async {
          return switch (call.method) {
            'scanReceiptQr' => mockReceiptQr,
            'scanReceiptDocument' => mockReceiptDocument,
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(voiceChannel, (call) async {
          return call.method == 'recognizeTransaction'
              ? mockVoiceRecognition
              : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(statementChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(receiptChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(voiceChannel, null);
  });

  Widget buildApp({bool linkedNotificationCard = false}) {
    return QestoApp(
      repository: MockQestoRepository(
        delay: Duration.zero,
        financialData: !linkedNotificationCard
            ? sampleUserFinancialData
            : sampleUserFinancialData.copyWith(
                accounts: [
                  for (final a in sampleUserFinancialData.accounts)
                    if (a.id == 'card-main')
                      QestoAccount(
                        id: a.id,
                        userId: a.userId,
                        title: 'Сбер •• 1234',
                        balance: a.balance,
                        currency: a.currency,
                        type: a.type,
                      )
                    else
                      a,
                ],
              ),
        coupons: mockCoupons,
        promotions: mockPromotions,
      ),
    );
  }

  Future<void> add(WidgetTester tester, String action) async {
    await tester.tap(find.byKey(const Key('mobile-add-data')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(Key('add-data-$action')));
    await tester.tap(find.byKey(Key('add-data-$action')));
    await tester.pumpAndSettle();
  }

  Future<void> openHistory(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    tester
        .state<ScaffoldState>(find.byKey(const Key('mobile-app-shell')))
        .openDrawer();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('action-history-button')),
      250,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('action-history-button'))),
      alignment: 1,
    );
    await tester.tap(find.byKey(const Key('action-history-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('голосовая фраза открывает подтверждение расхода', (
    tester,
  ) async {
    mockVoiceRecognition = {
      'text': 'Потратил 850 рублей на продукты',
      'onDevice': true,
    };
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await add(tester, 'voice');

    expect(find.text('Проверьте операцию'), findsOneWidget);
    expect(find.text('«Потратил 850 рублей на продукты»'), findsOneWidget);
    expect(find.byKey(const Key('voice-amount-field')), findsOneWidget);
    expect(find.text('Продукты'), findsWidgets);

    final saveButton = find.byKey(const Key('save-voice-transaction'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Операция добавлена'), findsOneWidget);
  });

  testWidgets('уведомления открываются и кнопка назад работает', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уведомления и SMS'));
    await tester.pumpAndSettle();
    expect(find.text('Найденные операции'), findsOneWidget);
    expect(find.text('Новых операций нет'), findsOneWidget);

    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Добрый день'), findsOneWidget);
  });

  testWidgets('уведомление Сбербанка автоматически добавляется как расход', (
    tester,
  ) async {
    mockNotifications = [
      {
        'packageName': 'ru.sberbankmobile',
        'notificationKey': 'sber-widget-test',
        'postedAt': DateTime(2026, 7, 21, 14, 32).millisecondsSinceEpoch,
        'title': 'Покупка Burger King',
        'text': '50 ₽ - Баланс: ... ₽ Счёт карты МИР *1234',
      },
    ];

    await tester.pumpWidget(buildApp(linkedNotificationCard: true));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DesktopAppShell>(find.byType(DesktopAppShell))
          .controller
          .transactions
          .any((t) => t.amount == 50),
      isTrue,
    );

    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уведомления и SMS'));
    await tester.pumpAndSettle();

    expect(find.text('Новых операций нет'), findsOneWidget);
    expect(find.text('Добавить'), findsNothing);
  });

  testWidgets('ручное добавление расхода обновляет итог', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await add(tester, 'manual');

    await tester.enterText(
      find.byKey(const Key('expense-amount-field')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const Key('expense-title-field')),
      'Тестовая покупка',
    );
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Продукты');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Продукты').last);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -900), 1500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить расход'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DesktopAppShell>(find.byType(DesktopAppShell))
          .controller
          .transactions
          .any((t) => t.merchant == 'Тестовая покупка' && t.amount == 1000),
      isTrue,
    );
  });

  testWidgets('PDF-выписка Сбербанка открывается и импортируется', (
    tester,
  ) async {
    mockStatement = {
      'fileName': 'sber-test.pdf',
      'text': '''
СБЕР 900 www.sberbank.ru
Выписка по платёжному счёту
За период 01.07.2026 — 31.07.2026
Номер счёта 40817 810 0 0000 0012345
Расшифровка операций
07.07.2026 10:30 Супермаркеты 84,99 6 010,12
07.07.2026 737816 MAGNIT TEST MOSCOW RUS. Операция по карте ****8505
06.07.2026 13:00 Перевод на карту +500,00 6 095,11
06.07.2026 123456 Перевод от И. Имя. Операция по счету ****2345
04.07.2026 13:00 Возврат, отмена операции +540,00 6 247,60
04.07.2026 659298 CAFE TEST MOSCOW RUS. Операция по карте ****8505
''',
    };

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await add(tester, 'statement');

    expect(find.text('Выписка Сбербанка в PDF'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick-statement-pdf')));
    await tester.pumpAndSettle();

    expect(find.text('sber-test.pdf'), findsOneWidget);
    expect(find.text('Найдено операций: 3'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('MAGNIT TEST MOSCOW RUS'), 250);
    expect(find.text('MAGNIT TEST MOSCOW RUS'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Перевод от И. Имя'), 260);
    expect(find.text('Перевод от И. Имя'), findsOneWidget);
    expect(find.text('−84,99 ₽'), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-statement-transactions')));
    await tester.pumpAndSettle();
    expect(find.text('Добавлено операций: 3'), findsOneWidget);

    final controller = tester
        .widget<DesktopAppShell>(find.byType(DesktopAppShell))
        .controller;
    expect(controller.accounts.any((a) => a.title.contains('2345')), isTrue);
    await openHistory(tester);
    expect(find.text('Импорт sber-test.pdf'), findsOneWidget);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('отменено'), findsWidgets);
  });

  testWidgets('QR-код кассового чека сканируется и добавляется', (
    tester,
  ) async {
    mockReceiptQr =
        't=20260719T1430&s=987.65&fn=9282440300999999&'
        'i=123456&fp=987654321&n=1';

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await add(tester, 'receipt');

    expect(find.text('QR-код кассового чека'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-receipt-qr')));
    await tester.pumpAndSettle();

    expect(find.text('987,65 ₽'), findsOneWidget);
    expect(find.text('Новая операция'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('receipt-merchant-field')),
      'Тестовый магазин',
    );
    await tester.tap(find.byKey(const Key('save-receipt')));
    await tester.pumpAndSettle();

    expect(find.text('Расход из чека добавлен'), findsOneWidget);
  });

  testWidgets('фотография чека распознаёт магазин и товары', (tester) async {
    mockReceiptQr =
        't=20260719T1430&s=144.89&fn=9282440300999999&'
        'i=654321&fp=123456789&n=1';
    final lines = [
      'ООО "АГРОТОРГ"',
      'КАССОВЫЙ ЧЕК',
      'МОЛОКО 3,2%',
      '1 X 89,99',
      'ХЛЕБ БОРОДИНСКИЙ 54,90',
      'ИТОГ 144,89',
    ];
    mockReceiptDocument = {
      'text': lines.join('\n'),
      'lines': [
        for (final line in lines) {'text': line},
      ],
    };

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await add(tester, 'receipt');
    await tester.tap(find.byKey(const Key('scan-receipt-qr')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('scan-receipt-document')));
    await tester.tap(find.byKey(const Key('scan-receipt-document')));
    await tester.pumpAndSettle();

    expect(find.text('МОЛОКО 3,2%'), findsOneWidget);
    expect(find.text('ХЛЕБ БОРОДИНСКИЙ'), findsOneWidget);
    final merchantField = tester.widget<TextField>(
      find.byKey(const Key('receipt-merchant-field')),
    );
    expect(merchantField.controller?.text, 'АГРОТОРГ');

    await tester.tap(find.byKey(const Key('save-receipt')));
    await tester.pumpAndSettle();
    expect(find.text('Расход из чека добавлен'), findsOneWidget);

    await add(tester, 'receipt');
    await tester.tap(find.byKey(const Key('scan-receipt-qr')));
    await tester.pumpAndSettle();

    expect(find.text('Чек уже добавлен'), findsOneWidget);
    expect(find.text('Обновить состав чека'), findsOneWidget);
  });
}
