import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/benefits/deal_details_screen.dart';

void main() {
  testWidgets('экран промокода показывает код и условия', (tester) async {
    final deal = Deal(
      id: 'promo-1',
      userId: 'public-feed',
      kind: DealKind.coupon,
      category: 'Супермаркеты',
      title: 'Скидка в Перекрёстке',
      description: 'Скидка на первый заказ.',
      visualKey: 'groceries',
      badge: '15%',
      promoCode: 'PEREK15',
      merchantName: 'Перекрёсток',
      targetUrl: 'https://example.com/deal',
      sourceUrl: 'https://t.me/skidki/1',
      discountType: 'percent',
      discountValue: 15,
      minimumOrder: 1000,
      maximumDiscount: 500,
      customerType: 'new',
      validUntil: DateTime(2026, 8, 31),
      confidence: 95,
    );

    await tester.pumpWidget(MaterialApp(home: DealDetailsScreen(deal: deal)));

    expect(find.text('Промокод'), findsOneWidget);
    expect(find.text('PEREK15'), findsOneWidget);
    expect(find.text('Условия'), findsOneWidget);
    expect(find.byKey(const Key('copy-promo-code')), findsOneWidget);
    expect(find.textContaining('Минимальный заказ'), findsOneWidget);
    expect(find.textContaining('новых пользователей'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-deal-target')), findsOneWidget);
  });
}
