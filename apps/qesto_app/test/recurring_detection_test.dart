import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

CanonicalTransaction recurringFixture(
  int index,
  DateTime date, {
  int amount = 49900,
  String name = 'Unknown Cloud Service',
  String entity = 'ent-test',
  String currency = 'RUB',
  CanonicalTransactionStatus status = CanonicalTransactionStatus.posted,
  FinancialDirection direction = FinancialDirection.outflow,
  FinancialEventType event = FinancialEventType.observed,
  List<String> tags = const [],
}) => CanonicalTransaction(
  id: '$entity-$index',
  entityId: entity,
  accountId: 'acc-$entity',
  status: status,
  amount: Money(minorUnits: amount, currency: currency),
  direction: direction,
  occurredAt: date,
  rawDescription: name,
  normalizedDescription: name.toLowerCase(),
  merchantName: name,
  eventType: event,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  fieldTrust: SourceTrustLevel.bankStatement,
  tags: tags,
);

List<CanonicalTransaction> monthlyFixture({
  List<int>? amounts,
  List<String>? names,
  List<DateTime>? dates,
}) => [
  for (var i = 0; i < (dates?.length ?? 4); i++)
    recurringFixture(
      i,
      dates?[i] ?? DateTime(2026, i + 1, 5),
      amount: amounts?[i] ?? 49900,
      name: names?[i] ?? 'Unknown Cloud Service',
    ),
];

void main() {
  const engine = EnrichmentEngine();
  test('A: unknown monthly merchant is detected, stable ID ignores tariff', () {
    final stream = engine.detectRecurring(monthlyFixture()).single;
    expect(stream.frequency, RecurrenceFrequency.monthly);
    expect(stream.isTentative, isFalse);
    expect(stream.nextExpectedAt, DateTime(2026, 5, 5));
    final changed = engine
        .detectRecurring(monthlyFixture(amounts: [49900, 49900, 54900, 54900]))
        .single;
    expect(changed.id, stream.id);
    expect(changed.typicalAmount.minorUnits, 54900);
  });
  test(
    'B: date jitter is calendar-based, time of day cannot shorten a day',
    () {
      final dates = [
        DateTime(2026, 1, 5, 23),
        DateTime(2026, 2, 4, 1),
        DateTime(2026, 3, 6, 23),
        DateTime(2026, 4, 5, 1),
      ];
      expect(
        engine.detectRecurring(monthlyFixture(dates: dates)).single.frequency,
        RecurrenceFrequency.monthly,
      );
    },
  );
  test('C: tariff change stays in one series', () {
    final s = engine
        .detectRecurring(monthlyFixture(amounts: [39900, 39900, 44900, 44900]))
        .single;
    expect(s.transactionIds, hasLength(4));
    expect(s.typicalAmount.minorUnits, 44900);
  });
  test(
    'D: reseller / FX price variation needs periodicity, not a service name',
    () {
      final s = engine
          .detectRecurring(
            monthlyFixture(
              amounts: [204800, 211200, 207400, 215100],
              names: List.filled(4, 'Independent Merchant'),
            ),
          )
          .single;
      expect(s.confidence, greaterThan(0.8));
      expect(s.title, 'Independent Merchant');
    },
  );
  test('E: normalized aliases do not equate other Yandex services to Plus', () {
    final series = monthlyFixture(
      names: ['YANDEX*PLUS', 'YM*YANDEX PLUS', 'Яндекс Плюс', 'Yandex.Plus'],
    );
    expect(engine.detectRecurring(series).single.title, 'Яндекс Плюс');
    expect(
      engine.enrich(series.first).merchantId,
      engine.enrich(series[2]).merchantId,
    );
    expect(engine.detectRecurring([series.first]), isEmpty);
    expect(
      engine.detectRecurring([
        series.first,
        series[1].copyWith(merchantName: 'YANDEX SCOOTERS'),
        series[2].copyWith(merchantName: 'YANDEX PAY'),
      ]),
      isEmpty,
    );
  });
  test('E2: punctuation variants of an unknown merchant are grouped', () {
    expect(
      engine.detectRecurring(
        monthlyFixture(
          names: ['NOVA*CLOUD', 'Nova Cloud', 'nova.cloud', 'NOVA-CLOUD'],
        ),
      ),
      hasLength(1),
    );
  });
  test(
    'F: one missing period reduces confidence without destroying pattern',
    () {
      final regular = engine.detectRecurring(monthlyFixture()).single;
      final missed = engine
          .detectRecurring(
            monthlyFixture(
              dates: [
                DateTime(2026, 1, 5),
                DateTime(2026, 2, 5),
                DateTime(2026, 4, 5),
                DateTime(2026, 5, 5),
              ],
            ),
          )
          .single;
      expect(missed.frequency, RecurrenceFrequency.monthly);
      expect(missed.confidence, lessThan(regular.confidence));
      expect(missed.nextExpectedAt, DateTime(2026, 6, 5));
    },
  );
  for (final merchant in ['Supermarket', 'Taxi Company']) {
    test('G/H: irregular frequent $merchant is not a recurring stream', () {
      final days = [1, 2, 4, 5, 8, 8, 11, 13, 17, 18, 22, 23, 23, 28, 30];
      final items = [
        for (var i = 0; i < days.length; i++)
          recurringFixture(
            i,
            DateTime(2026, 1, days[i]),
            amount: 10000 + (i * 3713) % 89000,
            name: merchant,
          ),
      ];
      expect(engine.detectRecurring(items), isEmpty);
      // Even stable amounts do not make irregular shopping a subscription.
      expect(
        engine.detectRecurring(
          items.map(
            (t) => t.copyWith(
              amount: const Money(minorUnits: 49900, currency: 'RUB'),
            ),
          ),
        ),
        isEmpty,
      );
    });
  }
  test(
    'I: refunds / pending / internal transfers / inferred facts are excluded',
    () {
      for (final tag in [
        'refund',
        'legacy-type-refund',
        'sber-status-refund',
        'qesto-internal-transfer',
        'legacy-type-savingsTransfer',
        'excel-period-aggregate',
        'qesto-non-cash',
        'sber-loyalty-only',
        'qesto-potential-duplicate',
        'qesto-unconfirmed',
      ]) {
        expect(
          engine.detectRecurring(
            monthlyFixture().map((t) => t.copyWith(tags: [tag])),
          ),
          isEmpty,
        );
      }
      for (final status in [
        CanonicalTransactionStatus.pending,
        CanonicalTransactionStatus.deleted,
        CanonicalTransactionStatus.reversed,
      ]) {
        expect(
          engine.detectRecurring(
            monthlyFixture().map((t) => t.copyWith(status: status)),
          ),
          isEmpty,
        );
      }
      expect(
        engine.detectRecurring(
          monthlyFixture().map(
            (t) => t.copyWith(direction: FinancialDirection.inflow),
          ),
        ),
        isEmpty,
      );
      expect(
        engine.detectRecurring(
          monthlyFixture().map(
            (t) => t.copyWith(
              transferDirection: 'outgoing',
              tags: ['legacy-type-transfer', 'qesto-external-transfer'],
            ),
          ),
        ),
        hasLength(1),
      );
      expect(
        engine.detectRecurring([
          for (var i = 0; i < 4; i++)
            recurringFixture(
              i,
              DateTime(2026, i + 1, 5),
              event: FinancialEventType.expected,
            ),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'J: repeated canonical input never raises occurrence count/confidence',
    () {
      final items = monthlyFixture();
      final once = engine.detectRecurring(items).single;
      final many = engine.detectRecurring([
        ...items,
        ...items,
        ...items,
      ]).single;
      expect(many.toJson(), once.toJson());
      // Distinct IDs on the same day are NOT destructively deduplicated either.
      expect(
        engine.detectRecurring([
          ...items,
          recurringFixture(99, items.last.occurredAt),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'two monthly observations are tentative; one or two weekly are not enough',
    () {
      final items = monthlyFixture().take(2).toList();
      final s = engine.detectRecurring(items).single;
      expect(s.isTentative, isTrue);
      expect(s.confidence, lessThanOrEqualTo(0.7));
      final core = SynoballCore(
        initialState: SynoballState(transactions: items),
      );
      final financial = const FinancialStateService().calculate(
        state: core.state,
        entityId: 'ent-test',
        asOf: DateTime(2026, 2, 10),
      );
      expect(financial.mandatoryExpenses.minorUnits, 0);
      expect(engine.detectRecurring(items.take(1)), isEmpty);
      expect(
        engine.detectRecurring([
          items.first,
          items.last.copyWith(occurredAt: DateTime(2026, 1, 12)),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'weekly, quarterly, yearly work; biweekly has no model enum, not guessed',
    () {
      for (final entry in {
        RecurrenceFrequency.weekly: [
          DateTime(2026, 1, 1),
          DateTime(2026, 1, 8),
          DateTime(2026, 1, 15),
        ],
        RecurrenceFrequency.quarterly: [
          DateTime(2025, 1, 31),
          DateTime(2025, 4, 30),
          DateTime(2025, 7, 31),
        ],
        RecurrenceFrequency.yearly: [
          DateTime(2024, 2, 29),
          DateTime(2025, 2, 28),
          DateTime(2026, 2, 28),
        ],
      }.entries) {
        expect(
          engine
              .detectRecurring(monthlyFixture(dates: entry.value))
              .single
              .frequency,
          entry.key,
        );
      }
      expect(
        engine.detectRecurring(
          monthlyFixture(
            dates: [
              DateTime(2026, 1, 1),
              DateTime(2026, 1, 15),
              DateTime(2026, 1, 29),
            ],
          ),
        ),
        isEmpty,
      );
    },
  );
  test('calendar-end clamp, year boundary and UTC are preserved', () {
    final s = engine
        .detectRecurring(
          monthlyFixture(
            dates: [
              DateTime.utc(2025, 11, 30, 17),
              DateTime.utc(2025, 12, 31, 17),
              DateTime.utc(2026, 1, 31, 17),
            ],
          ),
        )
        .single;
    expect(s.nextExpectedAt, DateTime.utc(2026, 2, 28, 17));
  });
  test(
    'currency/entity separation; account change alone does not split merchant',
    () {
      final items = monthlyFixture();
      expect(
        engine.detectRecurring([
          items[0],
          items[1].copyWith(accountId: 'new-card'),
          items[2],
          items[3],
        ]),
        hasLength(1),
      );
      expect(
        engine.detectRecurring([
          items[0],
          recurringFixture(1, DateTime(2026, 2, 5), entity: 'other'),
          recurringFixture(2, DateTime(2026, 3, 5), currency: 'USD'),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'restoration recomputes cached series without touching financial facts',
    () {
      final items = monthlyFixture(amounts: [39900, 39900, 44900, 44900]);
      final core = SynoballCore(
        initialState: SynoballState(transactions: items),
      );
      expect(core.state.recurringStreams, hasLength(1));
      for (var i = 0; i < items.length; i++) {
        final before = items[i].toJson()
          ..remove('isRecurring')
          ..remove('recurringStreamId');
        final after = core.state.transactions[i].toJson()
          ..remove('isRecurring')
          ..remove('recurringStreamId');
        expect(after, before);
      }
      final restored = SynoballCore(
        initialState: SynoballState.fromJson(core.state.toJson()),
      );
      expect(restored.state.toJson(), core.state.toJson());
    },
  );
  test(
    'opt-in diagnostics explain rejection without financial identifiers',
    () {
      final diagnostics = <RecurringDiagnostic>[];
      engine.detectRecurring(
        monthlyFixture(amounts: [10000, 990000, 10000, 800000]),
        onDiagnostic: diagnostics.add,
      );
      expect(diagnostics.single.reason, 'incoherent_amounts');
      expect(diagnostics.single.occurrences, 4);
      diagnostics.clear();
      engine.detectRecurring(monthlyFixture(), onDiagnostic: diagnostics.add);
      expect(diagnostics.single.reason, 'detected');
      expect(diagnostics.single.intervalScore, 1);
      expect(diagnostics.single.amountScore, 1);
      expect(diagnostics.single.confidence, greaterThan(0.8));
    },
  );
  test(
    'J2: reimport through adapter/core preserves a single series and evidence',
    () {
      final core = SynoballCore();
      const account = SynoballAccount(
        id: 'test-account',
        entityId: 'ent-test',
        name: 'Test',
        type: SynoballAccountType.card,
        currency: 'RUB',
        balance: Money(minorUnits: 0, currency: 'RUB'),
      );
      StatementInput input() => StatementInput(
        entityId: 'ent-test',
        receivedAt: DateTime(2026, 5),
        rawPayload: 'sanitized fixture',
        batchName: 'fixture',
        account: account,
        transactions: [
          for (final t in monthlyFixture(amounts: [39900, 39900, 44900, 44900]))
            TransactionSeed(
              accountId: account.id,
              amount: t.amount,
              direction: t.direction,
              occurredAt: t.occurredAt,
              description: t.rawDescription,
              merchant: t.merchantName,
              providerTransactionId: t.id,
              confidence: 1,
            ),
        ],
      );
      core.ingest(StatementAdapter(), input());
      final before = core.state.recurringStreams.single.toJson();
      final result = core.ingest(StatementAdapter(), input());
      expect(result.createdTransactionIds, isEmpty);
      expect(core.transactions, hasLength(4));
      expect(core.state.recurringStreams.single.toJson(), before);
      expect(core.state.evidence, everyElement(isA<SourceEvidence>()));
    },
  );
}
