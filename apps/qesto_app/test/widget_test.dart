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
  late List<Map<String, Object?>> mockNotifications;
  Map<String, Object?>? mockStatement;
  String? mockReceiptQr;

  setUp(() {
    mockNotifications = [];
    mockStatement = null;
    mockReceiptQr = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (call) async {
          return switch (call.method) {
            'hasAccess' => true,
            'readNotifications' => mockNotifications,
            'removeNotification' || 'clearNotifications' => null,
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(statementChannel, (call) async {
          return call.method == 'pickPdf' ? mockStatement : null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(receiptChannel, (call) async {
          return call.method == 'scanReceiptQr' ? mockReceiptQr : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(statementChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(receiptChannel, null);
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

  testWidgets('распознанное уведомление Сбербанка показывается как расход', (
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
    await tester.tap(find.byTooltip('Уведомления'));
    await tester.pumpAndSettle();

    expect(find.text('Burger King'), findsOneWidget);
    expect(find.text('50 ₽ · Кафе и рестораны'), findsOneWidget);
    expect(find.text('Добавить'), findsOneWidget);
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
    await tester.tap(find.text('Загрузить выписку'));
    await tester.pumpAndSettle();

    expect(find.text('Выписка Сбербанка в PDF'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick-statement-pdf')));
    await tester.pumpAndSettle();

    expect(find.text('sber-test.pdf'), findsOneWidget);
    expect(find.text('Найдено расходов и возвратов: 2'), findsOneWidget);
    expect(find.text('MAGNIT TEST MOSCOW RUS'), findsOneWidget);
    expect(find.text('−84,99 ₽'), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-statement-transactions')));
    await tester.pumpAndSettle();
    expect(find.text('Добавлено операций: 2'), findsOneWidget);
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
