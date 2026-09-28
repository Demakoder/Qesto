import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/runtime/browser_controller.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_extractors.dart';
import 'package:qesto/features/bank_browser/sber/sber_readiness.dart';

void main() {
  const extractors = SberExtractors();
  final range = SberSyncRange(
    from: DateTime(2026, 8),
    toExclusive: DateTime(2026, 9),
    label: 'Август',
  );

  Map<String, dynamic> row({
    required String id,
    required String date,
    required int? amount,
    required String amountText,
    required String text,
    required String merchant,
    required String operationType,
    double? loyaltyAmount,
    String nonCashKind = '',
  }) => {
    'id': id,
    'dateIso': date,
    'date': date,
    'amountValue': amount,
    'amount': amountText,
    'text': text,
    'merchant': merchant,
    'description': merchant.isEmpty
        ? operationType
        : '$merchant · $operationType',
    'operationType': operationType,
    'loyaltyAmount': loyaltyAmount,
    'nonCashKind': nonCashKind,
    'ordinal': 0,
  };

  test('normalizes merchant, reward metadata and financial direction', () {
    final transactions = extractors.normalizeTransactionRows([
      row(
        id: 'purchase',
        date: '2026-08-10T12:00:00',
        amount: 500,
        amountText: '500 ₽',
        text: 'Самокаты +6 500 ₽ Оплата товаров и услуг',
        merchant: 'Самокаты',
        operationType: 'Оплата товаров и услуг',
        loyaltyAmount: 6,
      ),
      row(
        id: 'incoming',
        date: '2026-08-11T12:00:00',
        amount: 10000,
        amountText: '+10 000 ₽',
        text: 'Перевод от другого человека +10 000 ₽ Входящий перевод',
        merchant: 'Перевод от другого человека',
        operationType: 'Входящий перевод',
      ),
      row(
        id: 'outgoing',
        date: '2026-08-12T12:00:00',
        amount: 4000,
        amountText: '4 000 ₽',
        text: 'Получатель 4 000 ₽ Перевод по СБП',
        merchant: 'Получатель',
        operationType: 'Перевод по СБП',
      ),
      row(
        id: 'internal',
        date: '2026-08-13T12:00:00',
        amount: 20000,
        amountText: '20 000 ₽',
        text: 'Перевод между своими счетами 20 000 ₽',
        merchant: 'Между счетами',
        operationType: 'Перевод между своими счетами',
      ),
      row(
        id: 'refund',
        date: '2026-08-14T12:00:00',
        amount: 700,
        amountText: '700 ₽',
        text: 'Магазин 700 ₽ Возврат, отмена операций',
        merchant: 'Магазин',
        operationType: 'Возврат, отмена операций',
      ),
      row(
        id: 'reward-only',
        date: '2026-08-15T12:00:00',
        amount: null,
        amountText: '',
        text: 'Магазин +5 Начисление бонусов',
        merchant: 'Магазин',
        operationType: 'Начисление бонусов',
        loyaltyAmount: 5,
        nonCashKind: 'reward',
      ),
    ], range: range);

    expect(transactions, hasLength(5));
    final purchase = transactions.firstWhere(
      (item) => item.sourceId == 'purchase',
    );
    expect(purchase.merchant, 'Самокаты');
    expect(purchase.description, 'Самокаты · Оплата товаров и услуг');
    expect(purchase.loyaltyReward?.amount, 6);
    expect(purchase.description, isNot(contains('+6')));
    expect(purchase.direction, SberTransactionDirection.outflow);

    final incoming = transactions.firstWhere(
      (item) => item.sourceId == 'incoming',
    );
    expect(incoming.direction, SberTransactionDirection.inflow);
    expect(incoming.isTransfer, isTrue);
    expect(incoming.isInternalTransfer, isFalse);

    final outgoing = transactions.firstWhere(
      (item) => item.sourceId == 'outgoing',
    );
    expect(outgoing.direction, SberTransactionDirection.outflow);
    expect(outgoing.isTransfer, isTrue);
    expect(outgoing.isInternalTransfer, isFalse);

    final internal = transactions.firstWhere(
      (item) => item.sourceId == 'internal',
    );
    expect(internal.isInternalTransfer, isTrue);

    final refund = transactions.firstWhere((item) => item.sourceId == 'refund');
    expect(refund.status, 'REFUND');
    expect(refund.direction, SberTransactionDirection.inflow);
  });

  test('bank account-opening document proves a one-sided own transfer', () {
    final september = SberSyncRange(
      from: DateTime(2026, 9),
      toExclusive: DateTime(2026, 10),
      label: 'Сентябрь',
    );
    Map<String, dynamic> opening(String id, int amount) => {
      ...row(
        id: id,
        date: '2026-09-26T00:00:00',
        amount: amount,
        amountText: '$amount ₽',
        text:
            'Платёжный счёт •• 5023 $amount ₽ Накопительный счёт •• 1410 Открытие вклада/счета',
        merchant: 'Платёжный счёт',
        operationType: '',
      ),
      'bankOperationCode': 'UfsDepositOpen',
      'sourceProduct': 'Платёжный счёт •• 5023',
      'destinationProduct': 'Накопительный счёт •• 1410',
    };

    final own = extractors.normalizeTransactionRows([
      opening('opening-document', 15000),
    ], range: september).single;
    expect(own.isTransfer, isTrue);
    expect(own.isInternalTransfer, isTrue);
    expect(own.ownTransferSourceLastFour, '5023');
    expect(own.ownTransferDestinationLastFour, '1410');
    expect(own.isIncome, isFalse);

    final sameTitleWithoutProof = opening('ordinary', 15000)
      ..remove('bankOperationCode');
    final ordinary = extractors.normalizeTransactionRows([
      sameTitleWithoutProof,
    ], range: september).single;
    expect(ordinary.isInternalTransfer, isFalse);
    expect(ordinary.isIncome, isFalse);

    final outsideBank = opening('external', 15000)
      ..['bankOperationCode'] = 'ExternalPayment';
    expect(
      extractors
          .normalizeTransactionRows([outsideBank], range: september)
          .single
          .isInternalTransfer,
      isFalse,
    );

    for (final amount in [300, 4861]) {
      final ownBetweenAccounts = row(
        id: 'own-$amount',
        date: '2026-09-26T00:00:00',
        amount: amount,
        amountText: '$amount ₽',
        text:
            'Платёжный счёт •• 1794 $amount ₽ Платёжный счёт •• 5023 Между своими',
        merchant: 'Платёжный счёт',
        operationType: 'Между своими',
      );
      expect(
        extractors
            .normalizeTransactionRows([ownBetweenAccounts], range: september)
            .single
            .isInternalTransfer,
        isTrue,
      );
    }
  });

  test('separate savings products normalize as liquid stable accounts', () {
    final rows = [
      {
        'id': 'fixture-savings-rub-001',
        'kind': 'savings',
        'name': 'Накопительный счёт •• 1410',
        'identityText': 'Накопительный счёт •• 1410',
        'text': '15 000 ₽ Накопительный счёт •• 1410 12,5%',
        'balance': '15 000 ₽',
      },
      {
        'id': 'fixture-savings-eur-002',
        'kind': 'savings',
        'name': 'Сберегательный счет •• 3956',
        'identityText': 'Сберегательный счет •• 3956',
        'text': '0 € Сберегательный счет •• 3956 0,01%',
        'balance': '0 €',
      },
    ];
    final first = extractors.normalizeAccountRows(rows);
    final second = extractors.normalizeAccountRows(rows);
    expect(first, hasLength(2));
    expect(first.map((value) => value.id), second.map((value) => value.id));
    expect(first.first.type, AccountType.savings);
    expect(first.first.balanceMinor, 1500000);
    expect(first.first.lastFour, '1410');
    expect(first.last.type, AccountType.savings);
    expect(first.last.currency, 'EUR');
    expect(first.last.balanceMinor, 0);
  });

  test('fractional web amounts retain minor units', () {
    final value = row(
      id: 'cents',
      date: '2026-08-10T12:00:00',
      amount: null,
      amountText: '100,25 ₽',
      text: 'Coffee 100,25 ₽',
      merchant: 'Coffee',
      operationType: 'Оплата товаров и услуг',
    );
    value['amountValue'] = 100; // Legacy JS rounded this compatibility field.
    final result = extractors.normalizeTransactionRows([value], range: range);
    expect(result.single.amountMinor, 10025);
    expect(result.single.amount, 100);
  });

  test(
    'noncash records never turn their displayed account balance into money',
    () {
      for (final kind in ['reward', 'service']) {
        final value = row(
          id: kind,
          date: '2026-08-10T12:00:00',
          amount: 9000,
          amountText: '9 000 ₽',
          text: 'Информация. Баланс 9 000 ₽',
          merchant: 'Баланс',
          operationType: '',
          nonCashKind: kind,
        );
        expect(
          extractors.normalizeTransactionRows([value], range: range),
          isEmpty,
        );
      }
    },
  );

  test('rejects reward-looking merchant and respects selected period', () {
    final transactions = extractors.normalizeTransactionRows([
      row(
        id: 'bad-merchant',
        date: '2026-08-20T12:00:00',
        amount: 83,
        amountText: '83 ₽',
        text: '+0,6 Самокаты 83 ₽ Оплата товаров и услуг',
        merchant: '+0,6',
        operationType: 'Оплата товаров и услуг',
      ),
      row(
        id: 'outside',
        date: '2026-07-31T12:00:00',
        amount: 100,
        amountText: '100 ₽',
        text: 'Магазин 100 ₽ Оплата товаров и услуг',
        merchant: 'Магазин',
        operationType: 'Оплата товаров и услуг',
      ),
    ], range: range);

    expect(transactions, hasLength(1));
    expect(transactions.single.merchant, isNull);
    expect(transactions.single.description, 'Оплата товаров и услуг');
  });

  test(
    'diagnostics distinguish intentional exclusions from unreadable money',
    () {
      final base = row(
        id: 'accepted',
        date: '2026-08-10T12:00:00',
        amount: 100,
        amountText: '100,25 ₽',
        text: 'Магазин 100,25 ₽',
        merchant: 'Магазин',
        operationType: 'Оплата товаров и услуг',
      );
      final observations = [
        base,
        {...base, 'id': 'reward', 'nonCashKind': 'reward'},
        {...base, 'id': 'service', 'nonCashKind': 'service'},
        {...base, 'id': 'old', 'dateIso': '2026-07-31', 'date': '2026-07-31'},
        {...base, 'id': 'new', 'dateIso': '2026-09-01', 'date': '2026-09-01'},
        {...base, 'id': 'date', 'dateIso': '', 'date': ''},
        // Do not import 9000 from the balance when the purchase is still loading.
        {
          ...base,
          'id': 'money',
          'amount': '',
          'amountValue': null,
          'text': 'Магазин. Платёжный счёт: 9 000 ₽',
        },
        {...base, 'id': 'empty', 'text': ''},
      ];
      final result = extractors.diagnoseTransactionRows(
        observations,
        range: range,
      );
      expect(result.map((r) => r.outcome), [
        SberHistoryRowOutcome.accepted,
        SberHistoryRowOutcome.reward,
        SberHistoryRowOutcome.service,
        SberHistoryRowOutcome.outsidePeriod,
        SberHistoryRowOutcome.outsidePeriod,
        SberHistoryRowOutcome.missingDate,
        SberHistoryRowOutcome.missingAmount,
        SberHistoryRowOutcome.emptyText,
      ]);
      expect(result.where((r) => r.outcome.isError), hasLength(3));
      expect(result.map((r) => r.observationId).toSet(), hasLength(8));
      expect(
        extractors
            .normalizeTransactionRows(observations, range: range)
            .single
            .amountMinor,
        10025,
      );
    },
  );

  test('legacy unstructured amount remains readable', () {
    final value =
        row(
            id: 'legacy',
            date: '2026-08-10T12:00:00',
            amount: null,
            amountText: '',
            text: 'Магазин 100,25 ₽',
            merchant: 'Магазин',
            operationType: 'Оплата товаров и услуг',
          )
          ..remove('amount')
          ..remove('amountValue');
    expect(
      extractors
          .normalizeTransactionRows([value], range: range)
          .single
          .amountMinor,
      10025,
    );
  });

  for (final firstComplete in [false, true]) {
    test(
      'lazy observation keeps the complete row (firstComplete=$firstComplete)',
      () async {
        final complete = row(
          id: 'lazy',
          date: '2026-08-10T12:00:00',
          amount: 100,
          amountText: '100,25 ₽',
          text: 'Магазин 100,25 ₽',
          merchant: 'Магазин',
          operationType: 'Оплата товаров и услуг',
        );
        final incomplete = {
          ...complete,
          'amount': '',
          'amountValue': null,
          'text': 'Магазин. Платёжный счёт: 9 000 ₽',
        };
        final boundary = {
          ...complete,
          'id': 'older',
          'dateIso': '2026-07-31',
          'date': '2026-07-31',
        };
        final browser = _LazyHistoryBrowser([
          jsonEncode([firstComplete ? complete : incomplete]),
          jsonEncode([firstComplete ? incomplete : complete, boundary]),
        ]);
        final result = await extractors.transactions(
          browser,
          range: range,
          maxScrolls: 3,
        );
        expect(result.transactions.single.amountMinor, 10025);
        expect(result.rawRowsSeen, 2);
        expect(result.rejectedRows, 0);
        expect(result.outsidePeriodRows, 1);
        expect(
          result.diagnostics.where(
            (r) => r.outcome == SberHistoryRowOutcome.accepted,
          ),
          hasLength(1),
        );
        expect(result.rangeBoundaryReached, isTrue);
      },
    );
  }

  test('account fallback identity does not depend on a changing balance', () {
    final first = extractors.normalizeAccountRows([
      {
        'id': '',
        'name': 'Накопительный счёт',
        'kind': 'account',
        'text': 'Накопительный счёт Баланс 1 000 ₽',
        'balance': '1 000 ₽',
        'cards': <String>[],
      },
    ]).single;
    final second = extractors.normalizeAccountRows([
      {
        'id': '',
        'name': 'Накопительный счёт',
        'kind': 'account',
        'text': 'Накопительный счёт Баланс 7 500 ₽',
        'balance': '7 500 ₽',
        'cards': <String>[],
      },
    ]).single;

    expect(second.id, first.id);
    expect(second.balance, 7500);
  });

  test('linked card and its payment account become one capital account', () {
    final accounts = extractors.normalizeAccountRows([
      {
        'id': 'payment-account-route',
        'name': 'Платёжный счёт',
        'kind': 'account',
        'text': 'Платёжный счёт Баланс 10 000,25 ₽',
        'balance': '10 000,25 ₽',
        'cards': <String>['1234'],
      },
      {
        'id': 'card-route',
        'name': 'СберКарта',
        'kind': 'card',
        'text': 'СберКарта •• 1234 10 000,25 ₽',
        'balance': '10 000,25 ₽',
        'cards': <String>[],
      },
    ]);

    expect(accounts, hasLength(1));
    expect(accounts.single.linkedCardLastFours, contains('1234'));
    expect(accounts.single.balance, 10000);
    expect(accounts.single.balanceMinor, 1000025);
  });

  test(
    'history scrolling stops as soon as an older date is observed',
    () async {
      final browser = _HistoryBoundaryBrowser(
        jsonEncode([
          row(
            id: 'inside',
            date: '2026-08-10T12:00:00',
            amount: 500,
            amountText: '500 ₽',
            text: 'Магазин 500 ₽ Оплата товаров и услуг',
            merchant: 'Магазин',
            operationType: 'Оплата товаров и услуг',
          ),
          row(
            id: 'older',
            date: '2026-07-31T12:00:00',
            amount: 200,
            amountText: '200 ₽',
            text: 'Магазин 200 ₽ Оплата товаров и услуг',
            merchant: 'Магазин',
            operationType: 'Оплата товаров и услуг',
          ),
        ]),
      );

      final result = await extractors.transactions(
        browser,
        range: range,
        maxScrolls: 10,
      );

      expect(result.transactions, hasLength(1));
      expect(result.rawRowsSeen, 2);
      expect(result.rejectedRows, 0);
      expect(result.outsidePeriodRows, 1);
      expect(browser.historyReads, 1);
      expect(browser.scrollAttempts, 0);
    },
  );

  test('history walks virtualized rows before clicking load more', () async {
    final browser = _LoadMoreBeforeScrollBrowser(
      firstPayload: jsonEncode([
        row(
          id: 'newest',
          date: '2026-08-29T12:00:00',
          amount: 500,
          amountText: '500 ₽',
          text: 'Магазин 500 ₽ Оплата товаров и услуг',
          merchant: 'Магазин',
          operationType: 'Оплата товаров и услуг',
        ),
      ]),
      middlePayload: jsonEncode([
        row(
          id: 'next-day',
          date: '2026-08-20T12:00:00',
          amount: 700,
          amountText: '700 ₽',
          text: 'Аптека 700 ₽ Оплата товаров и услуг',
          merchant: 'Аптека',
          operationType: 'Оплата товаров и услуг',
        ),
      ]),
      expandedPayload: jsonEncode([
        row(
          id: 'range-boundary',
          date: '2026-07-31T12:00:00',
          amount: 200,
          amountText: '200 ₽',
          text: 'Кафе 200 ₽ Оплата товаров и услуг',
          merchant: 'Кафе',
          operationType: 'Оплата товаров и услуг',
        ),
      ]),
    );

    final result = await extractors.transactions(
      browser,
      range: range,
      maxScrolls: 10,
    );

    expect(result.transactions, hasLength(2));
    expect(result.loadMoreClicks, 1);
    expect(browser.scrollAttempts, 2);
  });

  test('virtual-list ordinal changes do not create duplicate operations', () {
    final first = row(
      id: '',
      date: '2026-08-20T12:00:00',
      amount: 700,
      amountText: '700 ₽',
      text: 'Аптека 700 ₽ Оплата товаров и услуг',
      merchant: 'Аптека',
      operationType: 'Оплата товаров и услуг',
    );
    first['observationKey'] =
        '/app/payments/sbp?documentId=stable-provider-document';
    final recycled = Map<String, dynamic>.from(first)..['ordinal'] = 17;

    final result = extractors.normalizeTransactionRows([
      first,
      recycled,
    ], range: range);

    expect(result, hasLength(1));
    expect(result.single.sourceId, isNotEmpty);
  });

  test(
    'browser script supports Cyrillic operation groups and strict month dates',
    () async {
      final browser = _ScriptCaptureBrowser();

      await extractors.visibleTransactions(browser, range: range);

      final script = browser.transactionScript!;
      expect(script, isNotNull);
      expect(script, contains('operationGroupLink'));
      expect(script, contains('section ul[aria-label] li > a[href]'));
      expect(script, contains('/app/payments/sbp'));
      expect(script, isNot(contains('[aria-label*="операци" i]')));
      expect(script, contains('январ[ья]'));
      expect(
        script,
        contains('if (!text && !operationLinks.includes(original)) return;'),
      );
      expect(
        script.replaceAll(RegExp(r'\s'), ''),
        isNot(contains('if(!text||!date||')),
      );
      expect(
        script.indexOf('const labelledGroup'),
        lessThan(script.indexOf('const own')),
      );
    },
  );

  test('SBP ticket purchase remains a monetary external outflow', () {
    final transactions = extractors.normalizeTransactionRows([
      row(
        id: '0007-ticket-purchase',
        date: '2026-08-13T00:00:00',
        amount: 26358,
        amountText: '26 358 ₽',
        text:
            'KUPIBILET.RU город Санкт-Петербург RUS 26 358 ₽ '
            'Оплата по QR-коду СБП',
        merchant: 'KUPIBILET.RU город Санкт-Петербург RUS',
        operationType: 'Оплата по QR-коду СБП',
      ),
    ], range: range);

    expect(transactions, hasLength(1));
    expect(transactions.single.amount, 26358);
    expect(transactions.single.direction, SberTransactionDirection.outflow);
    expect(transactions.single.isTransfer, isTrue);
    expect(transactions.single.isInternalTransfer, isFalse);
  });

  test(
    'reports an incomplete range when pagination is still present',
    () async {
      final browser = _IncompleteHistoryBrowser(
        jsonEncode([
          row(
            id: 'newest',
            date: '2026-08-29T12:00:00',
            amount: 500,
            amountText: '500 ₽',
            text: 'Магазин 500 ₽ Оплата товаров и услуг',
            merchant: 'Магазин',
            operationType: 'Оплата товаров и услуг',
          ),
        ]),
      );

      final result = await extractors.transactions(
        browser,
        range: range,
        maxScrolls: 1,
      );

      expect(result.transactions, hasLength(1));
      expect(result.rangeBoundaryReached, isFalse);
      expect(result.hasMoreRows, isTrue);
    },
  );

  test('slow history request is awaited without repeated clicks', () async {
    final first = jsonEncode([
      row(
        id: 'a',
        date: '2026-08-10',
        amount: 100,
        amountText: '100 ₽',
        text: 'Shop',
        merchant: 'Shop',
        operationType: 'Оплата товаров и услуг',
      ),
    ]);
    final boundary = jsonEncode([
      row(
        id: 'b',
        date: '2026-07-31',
        amount: 100,
        amountText: '100 ₽',
        text: 'Shop',
        merchant: 'Shop',
        operationType: 'Оплата товаров и услуг',
      ),
    ]);
    final browser = _MultiPageLoadMoreBrowser([
      first,
      boundary,
    ], pendingReads: 18);
    final result = await const SberExtractors(
      readiness: SberReadiness(
        timeout: Duration(seconds: 1),
        pollInterval: Duration(milliseconds: 2),
      ),
    ).transactions(browser, range: range);
    expect(result.rangeBoundaryReached, isTrue);
    expect(browser.loadMoreClicks, 1);
  });

  test(
    'stalled history request stays partial and is not clicked again',
    () async {
      final first = jsonEncode([
        row(
          id: 'a',
          date: '2026-08-10',
          amount: 100,
          amountText: '100 ₽',
          text: 'Shop',
          merchant: 'Shop',
          operationType: 'Оплата товаров и услуг',
        ),
      ]);
      final browser = _MultiPageLoadMoreBrowser([
        first,
        '[]',
      ], pendingReads: 100000);
      final result = await const SberExtractors(
        readiness: SberReadiness(
          timeout: Duration(milliseconds: 40),
          pollInterval: Duration(milliseconds: 2),
        ),
      ).transactions(browser, range: range);
      expect(result.hasMoreRows, isTrue);
      expect(result.transactions, hasLength(1));
      expect(browser.loadMoreClicks, 1);
    },
  );

  test('history waits for and follows every load-more page', () async {
    final browser = _MultiPageLoadMoreBrowser([
      jsonEncode([
        row(
          id: 'newest',
          date: '2026-08-29T12:00:00',
          amount: 500,
          amountText: '500 ₽',
          text: 'Магазин 500 ₽ Оплата товаров и услуг',
          merchant: 'Магазин',
          operationType: 'Оплата товаров и услуг',
        ),
      ]),
      jsonEncode([
        row(
          id: 'newest',
          date: '2026-08-29T12:00:00',
          amount: 500,
          amountText: '500 ₽',
          text: 'Магазин 500 ₽ Оплата товаров и услуг',
          merchant: 'Магазин',
          operationType: 'Оплата товаров и услуг',
        ),
        row(
          id: 'middle',
          date: '2026-08-18T12:00:00',
          amount: 700,
          amountText: '700 ₽',
          text: 'Аптека 700 ₽ Оплата товаров и услуг',
          merchant: 'Аптека',
          operationType: 'Оплата товаров и услуг',
        ),
      ]),
      jsonEncode([
        row(
          id: 'newest',
          date: '2026-08-29T12:00:00',
          amount: 500,
          amountText: '500 ₽',
          text: 'Магазин 500 ₽ Оплата товаров и услуг',
          merchant: 'Магазин',
          operationType: 'Оплата товаров и услуг',
        ),
        row(
          id: 'middle',
          date: '2026-08-18T12:00:00',
          amount: 700,
          amountText: '700 ₽',
          text: 'Аптека 700 ₽ Оплата товаров и услуг',
          merchant: 'Аптека',
          operationType: 'Оплата товаров и услуг',
        ),
        row(
          id: 'oldest-inside',
          date: '2026-08-02T12:00:00',
          amount: 300,
          amountText: '300 ₽',
          text: 'Кафе 300 ₽ Оплата товаров и услуг',
          merchant: 'Кафе',
          operationType: 'Оплата товаров и услуг',
        ),
        row(
          id: 'range-boundary',
          date: '2026-07-31T12:00:00',
          amount: 200,
          amountText: '200 ₽',
          text: 'Метро 200 ₽ Оплата товаров и услуг',
          merchant: 'Метро',
          operationType: 'Оплата товаров и услуг',
        ),
      ]),
    ]);

    final result = await extractors.transactions(
      browser,
      range: range,
      maxScrolls: 20,
    );

    expect(result.transactions, hasLength(3));
    expect(result.loadMoreClicks, 2);
    expect(browser.scrollAttempts, 2);
  });
}

class _HistoryBoundaryBrowser extends BrowserController {
  _HistoryBoundaryBrowser(this.payload)
    : super(
        profile: BankProfile(
          id: 'sber-test-profile',
          bankId: 'sber',
          displayName: 'Сбер',
          createdAt: DateTime(2026),
          lastOpenedAt: DateTime(2026),
          lastKnownUrl: Uri.parse('https://online.sberbank.ru/app/operations'),
        ),
        bank: BankConnectorRegistry.sber,
        profileManager: BrowserProfileManager(),
        onNotice: (_) {},
      );

  final String payload;
  var historyReads = 0;
  var scrollAttempts = 0;

  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    if (script.contains('page readiness without reload')) return 'ready';
    if (script.contains('visible transaction facts')) {
      historyReads += 1;
      return payload;
    }
    if (script.contains('advance a visible read-only history list')) {
      scrollAttempts += 1;
      return '1';
    }
    return '0';
  }
}

class _ScriptCaptureBrowser extends BrowserController {
  _ScriptCaptureBrowser()
    : super(
        profile: BankProfile(
          id: 'sber-script-capture-profile',
          bankId: 'sber',
          displayName: 'Сбер',
          createdAt: DateTime(2026),
          lastOpenedAt: DateTime(2026),
          lastKnownUrl: Uri.parse('https://online.sberbank.ru/app/operations'),
        ),
        bank: BankConnectorRegistry.sber,
        profileManager: BrowserProfileManager(),
        onNotice: (_) {},
      );

  String? transactionScript;

  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    if (script.contains('page readiness without reload')) return 'ready';
    if (script.contains('visible transaction facts')) {
      transactionScript = script;
      return '[]';
    }
    return '0';
  }
}

class _LazyHistoryBrowser extends _HistoryBoundaryBrowser {
  _LazyHistoryBrowser(this.pages) : super('[]');
  final List<String> pages;
  var nextRead = 0;

  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    if (script.contains('visible transaction facts')) {
      return pages[nextRead++];
    }
    return super.evaluateConnectorJavascript(script, mode: mode);
  }
}

class _IncompleteHistoryBrowser extends BrowserController {
  _IncompleteHistoryBrowser(this.payload)
    : super(
        profile: BankProfile(
          id: 'sber-incomplete-profile',
          bankId: 'sber',
          displayName: 'Сбер',
          createdAt: DateTime(2026),
          lastOpenedAt: DateTime(2026),
          lastKnownUrl: Uri.parse('https://online.sberbank.ru/app/operations'),
        ),
        bank: BankConnectorRegistry.sber,
        profileManager: BrowserProfileManager(),
        onNotice: (_) {},
      );

  final String payload;

  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    if (script.contains('page readiness without reload')) return 'ready';
    if (script.contains('visible transaction facts')) return payload;
    if (script.contains('detect remaining read-only history pagination')) {
      return '1';
    }
    return '0';
  }
}

class _LoadMoreBeforeScrollBrowser extends BrowserController {
  _LoadMoreBeforeScrollBrowser({
    required this.firstPayload,
    required this.middlePayload,
    required this.expandedPayload,
  }) : super(
         profile: BankProfile(
           id: 'sber-load-more-profile',
           bankId: 'sber',
           displayName: 'Сбер',
           createdAt: DateTime(2026),
           lastOpenedAt: DateTime(2026),
           lastKnownUrl: Uri.parse('https://online.sberbank.ru/app/operations'),
         ),
         bank: BankConnectorRegistry.sber,
         profileManager: BrowserProfileManager(),
         onNotice: (_) {},
       );

  final String firstPayload;
  final String middlePayload;
  final String expandedPayload;
  var historyReads = 0;
  var loadMoreAttempts = 0;
  var scrollAttempts = 0;
  var walkedMiddle = false;
  var expanded = false;

  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    if (script.contains('page readiness without reload')) return 'ready';
    if (script.contains('visible transaction facts')) {
      historyReads += 1;
      if (expanded) return expandedPayload;
      return walkedMiddle ? middlePayload : firstPayload;
    }
    if (script.contains('expand only the read-only operation history')) {
      loadMoreAttempts += 1;
      if (loadMoreAttempts != 1) return '0';
      expanded = true;
      return '1';
    }
    if (script.contains('advance a visible read-only history list')) {
      scrollAttempts += 1;
      if (walkedMiddle) return '0';
      walkedMiddle = true;
      return '1';
    }
    return '0';
  }
}

class _MultiPageLoadMoreBrowser extends BrowserController {
  _MultiPageLoadMoreBrowser(this.pages, {this.pendingReads = 3})
    : super(
        profile: BankProfile(
          id: 'sber-multi-page-profile',
          bankId: 'sber',
          displayName: 'Сбер',
          createdAt: DateTime(2026),
          lastOpenedAt: DateTime(2026),
          lastKnownUrl: Uri.parse('https://online.sberbank.ru/app/operations'),
        ),
        bank: BankConnectorRegistry.sber,
        profileManager: BrowserProfileManager(),
        onNotice: (_) {},
      );

  final List<String> pages;
  final int pendingReads;
  var currentPage = 0;
  var loadMoreClicks = 0;
  var scrollAttempts = 0;
  var _pendingReads = 0;

  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    if (script.contains('page readiness without reload')) return 'ready';
    if (script.contains('visible transaction facts')) {
      if (_pendingReads > 0) {
        _pendingReads -= 1;
        if (_pendingReads == 0 && currentPage < pages.length - 1) {
          currentPage += 1;
        }
      }
      return pages[currentPage];
    }
    if (script.contains('expand only the read-only operation history')) {
      if (currentPage >= pages.length - 1 || _pendingReads > 0) return '0';
      loadMoreClicks += 1;
      // Model React/virtual-list latency: several reads still expose the old
      // page after a successful button click.
      _pendingReads = pendingReads;
      return '1';
    }
    if (script.contains('advance a visible read-only history list')) {
      scrollAttempts += 1;
      return '0';
    }
    return '0';
  }
}
