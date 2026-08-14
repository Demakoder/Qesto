import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
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
              (item) => item['notificationKey'] == arguments['notificationKey'],
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

  Widget buildApp() {
    return QestoApp(
      repository: MockQestoRepository(
        delay: Duration.zero,
        financialData: sampleUserFinancialData,
        coupons: mockCoupons,
        promotions: mockPromotions,
      ),
    );
  }

  testWidgets('основные вкладки переключаются и сохраняют содержимое', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Бюджет'), findsWidgets);
    expect(find.text('Расходы по категориям'), findsOneWidget);

    await tester.tap(find.text('Выгода').last);
    await tester.pumpAndSettle();
    expect(find.text('Скидка 15% в Перекрёстке'), findsOneWidget);

    await tester.tap(find.text('Накопления').last);
    await tester.pumpAndSettle();
    expect(find.text('Накоплено'), findsOneWidget);
  });

  testWidgets('голосовая фраза открывает подтверждение расхода', (
    tester,
  ) async {
    mockVoiceRecognition = {
      'text': 'Потратил 850 рублей на продукты',
      'onDevice': true,
    };
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final voiceButton = find.byKey(const Key('voice-transaction-button'));
    await tester.ensureVisible(voiceButton);
    await tester.tap(voiceButton);
    await tester.pumpAndSettle();

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
    expect(find.text('Найденные операции'), findsOneWidget);
    expect(find.text('Новых операций нет'), findsOneWidget);

    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Расходы по категориям'), findsOneWidget);
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
        'text': '50 ₽ - Баланс: ... ₽ Счёт карты МИР ...',
      },
    ];

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.text('46 750 ₽'), findsWidgets);

    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();

    expect(find.text('Новых операций нет'), findsOneWidget);
    expect(find.text('Добавить'), findsNothing);
  });

  testWidgets('месяцы бюджета переключаются свайпом, детали открываются', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Бюджет на июль'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Бюджет на август'), findsOneWidget);
    expect(find.text('109%'), findsOneWidget);

    await tester.tap(find.text('Бюджет на август'));
    await tester.pumpAndSettle();
    expect(find.text('Динамика бюджета'), findsOneWidget);
    expect(find.text('Выгода'), findsNothing);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Бюджет на август'), findsOneWidget);
  });

  testWidgets('разделы выгоды переключают набор карточек', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выгода').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Акции'));
    await tester.pumpAndSettle();
    expect(find.text('Три поездки со скидкой 25%'), findsOneWidget);

    await tester.tap(find.text('Отслеживаемое'));
    await tester.pumpAndSettle();
    expect(find.text('Беспроводные наушники'), findsOneWidget);
  });

  testWidgets('поиск фильтрует купоны и акции', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выгода').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('benefits-search')),
      'Перекрестке',
    );
    await tester.pumpAndSettle();
    expect(find.text('Скидка 15% в Перекрёстке'), findsOneWidget);
    expect(find.text('Кешбэк 20% в ресторанах'), findsNothing);

    await tester.tap(find.text('Акции'));
    await tester.pumpAndSettle();
    expect(find.text('Акции не найдены'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-benefits-search')));
    await tester.pumpAndSettle();
    expect(find.text('Три поездки со скидкой 25%'), findsOneWidget);
  });

  testWidgets('сумма и серия накоплений ведут на разные экраны', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Накопления').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('467 000 ₽'));
    await tester.pumpAndSettle();
    expect(find.text('Динамика накоплений'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('64 недели'));
    await tester.pumpAndSettle();
    expect(find.text('Серия накоплений'), findsOneWidget);
  });

  testWidgets('полный список категорий и экран категории открываются', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Бюджет на июль'));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -1100), 1600);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('show-all-category-plans')));
    await tester.pumpAndSettle();
    expect(find.text('Сортировка'), findsOneWidget);

    await tester.tap(find.text('Продукты').first);
    await tester.pumpAndSettle();
    expect(find.text('Операции'), findsOneWidget);
    expect(find.text('Перекрёсток'), findsWidgets);
  });

  testWidgets('категория на диаграмме открывает список операций', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final products = find.text('Продукты').first;
    await tester.ensureVisible(products);
    await tester.tap(products);
    await tester.pumpAndSettle();

    expect(find.text('Операции'), findsOneWidget);
    expect(find.byTooltip('Назад'), findsOneWidget);
  });

  testWidgets('показывает полный список предстоящих трат', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Бюджет на июль'));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -1800), 1800);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('show-all-upcoming-expenses')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Spotify'), findsOneWidget);
    expect(find.textContaining('Аренда'), findsOneWidget);
  });

  testWidgets('ручное добавление расхода обновляет итог', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.text('46 700 ₽'), findsWidgets);

    await tester.ensureVisible(find.text('Добавить'));
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить расход'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.text('Продукты').first);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -900), 1500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить расход'));
    await tester.pumpAndSettle();

    expect(find.text('47 700 ₽'), findsWidgets);
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
    await tester.ensureVisible(find.text('Добавить'));
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Загрузить выписку'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить Excel-таблицу'), findsOneWidget);
    await tester.tap(find.text('Загрузить выписку'));
    await tester.pumpAndSettle();

    expect(find.text('Выписка Сбербанка в PDF'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick-statement-pdf')));
    await tester.pumpAndSettle();

    expect(find.text('sber-test.pdf'), findsOneWidget);
    expect(find.text('Найдено операций: 3'), findsOneWidget);
    expect(find.text('MAGNIT TEST MOSCOW RUS'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Перевод от И. Имя'), 260);
    expect(find.text('Перевод от И. Имя'), findsOneWidget);
    expect(find.text('−84,99 ₽'), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-statement-transactions')));
    await tester.pumpAndSettle();
    expect(find.text('Добавлено операций: 3'), findsOneWidget);

    await tester.ensureVisible(find.text('Капитал'));
    await tester.tap(find.text('Капитал'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Счёт Сбербанка • 2345'), 300);
    expect(find.text('Счёт Сбербанка • 2345'), findsOneWidget);
    expect(find.text('6 010 ₽'), findsWidgets);

    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-history-button')));
    await tester.pumpAndSettle();
    expect(find.text('Импорт sber-test.pdf'), findsOneWidget);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('отменено'), findsOneWidget);
  });

  testWidgets('QR-код кассового чека сканируется и добавляется', (
    tester,
  ) async {
    mockReceiptQr =
        't=20260719T1430&s=987.65&fn=9282440300999999&'
        'i=123456&fp=987654321&n=1';

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Добавить'));
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Добавить чек'));
    await tester.tap(find.text('Добавить чек'));
    await tester.pumpAndSettle();

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
    await tester.ensureVisible(find.text('Добавить'));
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Добавить чек'));
    await tester.tap(find.text('Добавить чек'));
    await tester.pumpAndSettle();
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

    await tester.ensureVisible(find.text('Добавить'));
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Добавить чек'));
    await tester.tap(find.text('Добавить чек'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-receipt-qr')));
    await tester.pumpAndSettle();

    expect(find.text('Чек уже добавлен'), findsOneWidget);
    expect(find.text('Обновить состав чека'), findsOneWidget);
  });

  testWidgets('статистика открывается и вкладки переключаются', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Статистика'));
    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('statistics-title')), findsOneWidget);
    expect(find.text('Финансовая динамика'), findsOneWidget);

    await tester.tap(find.byKey(const Key('statistics-tab-expenses')));
    await tester.pumpAndSettle();
    expect(find.text('Динамика расходов'), findsOneWidget);
  });

  testWidgets('период, сравнение и фильтры статистики работают', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Статистика'));
    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('statistics-period-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Последние 30 дней'));
    await tester.pumpAndSettle();
    expect(find.textContaining('20 июня'), findsWidgets);

    await tester.tap(find.byKey(const Key('statistics-comparison-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Без сравнения'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('statistics-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Наличные'));
    await tester.tap(find.byKey(const Key('statistics-apply-filters')));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('служебные экраны статистики открываются', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Статистика'));
    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('statistics-tracked-button')));
    await tester.pumpAndSettle();
    expect(find.text('Отслеживаемое'), findsOneWidget);
    expect(find.text('Кафе и рестораны'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('statistics-explore-button')));
    await tester.pumpAndSettle();
    expect(find.text('Собственный финансовый запрос'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('statistics-quality-button')));
    await tester.pumpAndSettle();
    expect(find.text('Полнота статистики'), findsOneWidget);
    expect(find.text('Возможный дубль'), findsOneWidget);
  });
}
