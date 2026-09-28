import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/desktop/pages/desktop_transactions_page.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/classification/category_manager_screen.dart';
import 'package:qesto/features/classification/classification_actions.dart';
import 'classification_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Onest': 'assets/fonts/white_silver/Onest-Variable.ttf',
      'Prata': 'assets/fonts/white_silver/Prata-Regular.ttf',
      'Noto Serif Display':
          'assets/fonts/white_silver/NotoSerifDisplay-Italic.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  Future<BudgetController> open(
    WidgetTester tester, {
    double width = 1200,
    Brightness brightness = Brightness.light,
    bool manager = false,
    GlobalKey? renderKey,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture.classificationController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(brightness: brightness),
        home: RepaintBoundary(
          key: renderKey,
          child: manager
              ? CategoryManagerScreen(controller: c)
              : Scaffold(body: DesktopTransactionsPage(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  for (final width in [360.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'classification quick action and scope on $width $brightness',
        (tester) async {
          final c = await open(tester, width: width, brightness: brightness);
          expect(find.text('Категории'), findsOneWidget);
          await tester.tap(find.byTooltip('Действия с операцией').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Изменить категорию'));
          await tester.pumpAndSettle();
          expect(find.text('Поиск категории'), findsOneWidget);
          expect(find.text('Создать категорию'), findsOneWidget);
          await tester.enterText(find.byType(TextField).last, 'кафе');
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(ListTile, c.categoryById('cafes').name).last,
          );
          await tester.pumpAndSettle();
          expect(find.text('Прошлые и будущие операции'), findsOneWidget);
          await tester.tap(find.text('Только эту операцию'));
          await tester.pumpAndSettle();
          expect(
            c.transactions.where((t) => t.categoryId == 'cafes'),
            hasLength(1),
          );
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets('category manager and editor on $width $brightness', (
        tester,
      ) async {
        final key = GlobalKey();
        final c = await open(
          tester,
          width: width,
          brightness: brightness,
          manager: true,
          renderKey: key,
        );
        expect(find.text('Категории и теги'), findsOneWidget);
        await tester.tap(find.text('Добавить категорию'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Мои обеды');
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(c.categories.any((c) => c.name == 'Мои обеды'), isTrue);
        await tester.tap(find.text('Теги'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Добавить тег'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'универ');
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(find.text('#универ'), findsOneWidget);
        await tester.tap(find.text('#универ'));
        await tester.pumpAndSettle();
        expect(find.text('Все операции'), findsOneWidget);
        expect(find.text('Показано 0 из 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Opt-in screenshots are generated only from the synthetic fixture.
        if (Platform.environment['QESTO_CLASSIFICATION_RENDER'] == '1') {
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Категории'));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory('../../.codex_tmp/classification');
            await dir.create(recursive: true);
            await File(
              '${dir.path}/manager-${width.toInt()}-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
  testWidgets(
    'quick delete uses trash and category route filters existing list',
    (tester) async {
      final c = await open(tester);
      await tester.tap(find.byTooltip('Действия с операцией').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить операцию'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(c.transactions, hasLength(2));
      expect(c.trashedTransactions, hasLength(1));
      await tester.tap(find.text('Категории'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(c.categoryById('groceries').name).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Все операции'));
      await tester.pumpAndSettle();
      expect(find.text('Показано 2 из 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'drawer changes persist without saving stale category over them',
    (tester) async {
      final c = await open(tester);
      await tester.tap(find.byTooltip('Действия с операцией').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Редактировать'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionClassificationFields), findsOneWidget);
      await c.changeTransactionCategory('different', 'cafes');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(
        c.transactions.firstWhere((t) => t.id == 'different').categoryId,
        'cafes',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tags are selected, searchable and removed independently of service metadata',
    (tester) async {
      final c = await open(tester, width: 360);
      final first = await c.saveUserTag(name: 'универ', colorValue: 0xff00aa00);
      final second = await c.saveUserTag(name: 'обед', colorValue: 0xff0000aa);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Действия с операцией').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить тег'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#универ'));
      await tester.tap(find.text('#обед'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(
        c
            .tagsForTransaction(
              c.transactions.firstWhere((t) => t.id == 'different'),
            )
            .map((t) => t.id)
            .toSet(),
        {first.id, second.id},
      );
      await tester.tap(find.byTooltip('Фильтр по тегу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#универ'));
      await tester.pumpAndSettle();
      expect(find.text('Показано 1 из 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
