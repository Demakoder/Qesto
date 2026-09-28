import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/encrypted_local_key_value_store.dart';
import 'package:qesto/features/ai_export/data/ai_export_ids.dart';
import 'package:qesto/features/ai_export/data/ai_export_snapshot.dart';
import 'package:qesto/features/ai_export/domain/ai_export_mapper.dart';
import 'package:qesto/features/ai_export/domain/ai_export_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/features/statistics/domain/services/statistics_period_range.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/mocks/fixtures/empty_user_financial_data.dart';
import 'package:qesto/synoball/core/models.dart';

class MemoryExportSecrets implements SecureStringStore {
  final values = <String, String>{};
  int writes = 0;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }
}

const privateAccount = 'private-bank-resource-9876';
const privateEntity = 'ent-private-user';

CanonicalTransaction exportFixtureTransaction(
  String id, {
  DateTime? date,
  CanonicalTransactionStatus status = CanonicalTransactionStatus.posted,
  List<String> tags = const [],
  String? category = 'groceries',
  FinancialDirection direction = FinancialDirection.outflow,
  String? transferDirection,
  String currency = 'RUB',
  String account = privateAccount,
  FinancialEventType eventType = FinancialEventType.observed,
}) => CanonicalTransaction(
  id: id,
  entityId: privateEntity,
  accountId: account,
  status: status,
  amount: Money(minorUnits: 120025, currency: currency),
  direction: direction,
  occurredAt: date ?? DateTime(2026, 9, 22, 15, 30),
  rawDescription: 'PRIVATE_RAW_DESCRIPTION',
  normalizedDescription: 'PRIVATE_NORMALIZED',
  merchantName: 'PRIVATE_MERCHANT',
  synoballCategory: category,
  eventType: eventType,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  fieldTrust: SourceTrustLevel.userConfirmed,
  tags: tags,
  transferDirection: transferDirection,
);

BudgetController exportFixtureController(List<CanonicalTransaction> rows) =>
    BudgetController(
      configuration: budgetConfiguration,
      financialData: emptyUserFinancialData.copyWith(
        user: const QestoUser(
          id: 'private-user',
          name: 'PRIVATE_USER',
          defaultCurrency: 'RUB',
        ),
        referenceDate: DateTime(2026, 9, 23),
        categoryCustomizations: const [
          BudgetCategoryCustomization(
            categoryId: 'groceries',
            name: 'PRIVATE_CATEGORY',
            iconKey: 'cart',
            colorValue: 0xff123456,
          ),
        ],
        synoballState: SynoballState(
          accounts: const [
            SynoballAccount(
              id: privateAccount,
              entityId: privateEntity,
              name: 'PRIVATE_ACCOUNT 9876',
              type: SynoballAccountType.checking,
              currency: 'RUB',
              balance: Money(minorUnits: 1000025, currency: 'RUB'),
              connectionId: 'PRIVATE_CONNECTION',
              externalId: 'PRIVATE_PROVIDER',
            ),
            SynoballAccount(
              id: 'private-virtual',
              entityId: privateEntity,
              name: 'PRIVATE_VIRTUAL',
              type: SynoballAccountType.other,
              currency: 'USD',
              balance: Money(minorUnits: 0, currency: 'USD'),
              isVirtual: true,
            ),
          ],
          transactions: rows,
        ),
      ),
    );

void main() {
  final range = StatisticsDateRange(
    DateTime(2026, 9, 1),
    DateTime(2026, 9, 23),
  );
  Future<Map<String, dynamic>> export(
    BudgetController c, {
    bool hidden = true,
  }) async {
    final snapshot = captureAiExportSnapshot(c);
    final ids = await AiExportIdStore(
      secureStore: MemoryExportSecrets(),
    ).forProfile(snapshot.profileScope);
    final document = await const AiExportMapper().build(
      AiExportSelection(
        snapshot,
        AiExportSettings(
          period: range,
          hideTransactionNames: hidden,
          hideAccountNames: hidden,
        ),
      ),
      ids,
    );
    return jsonDecode(jsonEncode(document.toJson())) as Map<String, dynamic>;
  }

  test('schema allowlist, exact money, links and whole JSON privacy', () async {
    final c = exportFixtureController([
      exportFixtureTransaction('PRIVATE_TX_ID'),
    ]);
    addTearDown(c.dispose);
    final before = jsonEncode(c.synoballState.toJson());
    final data = await export(c);
    final encoded = jsonEncode(data);
    expect(data.keys.toSet(), {
      'schemaVersion',
      'generatedAt',
      'period',
      'privacy',
      'selection',
      'accounts',
      'categories',
      'transactions',
    });
    expect(data['schemaVersion'], 'qesto.ai-export.v1');
    expect(data['privacy']['idScope'], 'persistent_pseudonymous');
    final row = (data['transactions'] as List).single;
    expect(row['amount'], {'value': '1200.25', 'currency': 'RUB'});
    expect(
      (data['accounts'] as List).any((a) => a['id'] == row['accountId']),
      isTrue,
    );
    expect(data['categories'][0]['id'], row['categoryId']);
    expect(data['categories'][0]['name'], 'Продукты');
    for (final value in [
      'PRIVATE_',
      privateAccount,
      privateEntity,
      '9876',
      'groceries',
      'rawDescription',
      'sourceEvidence',
      'tags',
      'connectionId',
      'receiptId',
    ]) {
      expect(encoded, isNot(contains(value)), reason: value);
    }
    expect(jsonEncode(c.synoballState.toJson()), before);
    final visible = await export(c, hidden: false);
    expect(visible['transactions'][0]['name'], 'PRIVATE_MERCHANT');
    expect(jsonEncode(visible), isNot(contains('PRIVATE_RAW_DESCRIPTION')));
    expect(jsonEncode(visible), isNot(contains('PRIVATE_PROVIDER')));
  });

  test(
    'HMAC stable across exports/restarts, profile/type separation, no raw IDs',
    () async {
      final secrets = MemoryExportSecrets();
      final store = AiExportIdStore(secureStore: secrets);
      final pair = await Future.wait([
        store.forProfile('p'),
        store.forProfile('p'),
      ]);
      final original = await pair.first.id('account', 'guessable-bank-id');
      final restarted = await AiExportIdStore(
        secureStore: secrets,
      ).forProfile('p');
      expect(await restarted.id('account', 'guessable-bank-id'), original);
      expect(await pair.last.id('account', 'guessable-bank-id'), original);
      expect(secrets.writes, 1);
      for (final type in ['transaction', 'category']) {
        expect(await restarted.id(type, 'guessable-bank-id'), isNot(original));
        expect(await restarted.id(type, 'x'), await pair.first.id(type, 'x'));
      }
      expect(await restarted.id('account', 'different'), isNot(original));
      expect(
        await (await store.forProfile(
          'other',
        )).id('account', 'guessable-bank-id'),
        isNot(original),
      );
      expect(original, matches(RegExp(r'^acc_[a-f0-9]{64}$')));
      secrets.values[AiExportIdStore.storageKey] = 'invalid-key';
      await expectLater(
        AiExportIdStore(secureStore: secrets).forProfile('p'),
        throwsA(isA<AiExportKeyException>()),
      );
      expect(secrets.writes, 1);
    },
  );

  test(
    'period inclusive boundaries, preview equals file, frozen snapshot',
    () async {
      final c = exportFixtureController([
        exportFixtureTransaction(
          'before',
          date: DateTime(2026, 8, 31, 23, 59, 59),
        ),
        exportFixtureTransaction('start', date: DateTime(2026, 9, 1)),
        exportFixtureTransaction(
          'end',
          date: DateTime(2026, 9, 23, 23, 59, 59),
        ),
        exportFixtureTransaction('after', date: DateTime(2026, 9, 24)),
      ]);
      addTearDown(c.dispose);
      final snapshot = captureAiExportSnapshot(c);
      final selection = AiExportSelection(
        snapshot,
        AiExportSettings(period: range),
      );
      expect(selection.transactions.map((t) => t.id), ['start', 'end']);
      final ids = await AiExportIdStore(
        secureStore: MemoryExportSecrets(),
      ).forProfile('p');
      final doc = await const AiExportMapper().build(selection, ids);
      expect(doc.transactions.length, selection.transactions.length);
      expect(doc.accounts.length, selection.accounts.length);
      expect(doc.categories.length, selection.categoryIds.length);
      expect(() => snapshot.categoryNames.clear(), throwsUnsupportedError);
      expect(() => snapshot.transactions.clear(), throwsUnsupportedError);
      expect(
        () => AiExportSelection(
          snapshot,
          AiExportSettings(
            period: StatisticsDateRange(
              DateTime(2026, 9, 2),
              DateTime(2026, 9, 1),
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'excludes lifecycle/non-cash/unconfirmed/inferred, keeps financial types',
    () async {
      final c = exportFixtureController([
        exportFixtureTransaction('expense'),
        exportFixtureTransaction(
          'income',
          direction: FinancialDirection.inflow,
        ),
        exportFixtureTransaction(
          'refund',
          direction: FinancialDirection.inflow,
          tags: ['refund'],
        ),
        exportFixtureTransaction(
          'internal',
          direction: FinancialDirection.neutral,
          transferDirection: 'outgoing',
          tags: ['qesto-internal-transfer'],
        ),
        exportFixtureTransaction('external', transferDirection: 'outgoing'),
        exportFixtureTransaction(
          'pending',
          status: CanonicalTransactionStatus.pending,
        ),
        exportFixtureTransaction(
          'deleted',
          status: CanonicalTransactionStatus.deleted,
        ),
        exportFixtureTransaction(
          'reversed',
          status: CanonicalTransactionStatus.reversed,
        ),
        exportFixtureTransaction('cancelled', tags: ['status-cancelled']),
        exportFixtureTransaction('points', tags: ['qesto-non-cash']),
        exportFixtureTransaction('unconfirmed', tags: ['qesto-unconfirmed']),
        exportFixtureTransaction(
          'expected',
          eventType: FinancialEventType.expected,
        ),
      ]);
      addTearDown(c.dispose);
      final data = await export(c);
      final rows = data['transactions'] as List;
      expect(rows, hasLength(5));
      expect(
        rows.map((r) => r['type']),
        containsAll(['expense', 'income', 'refund', 'transfer']),
      );
      expect(
        rows.where((r) => r['cashFlowTreatment'] == 'internalTransfer'),
        hasLength(1),
      );
      expect(
        rows.where((r) => r['cashFlowTreatment'] == 'externalOutflow'),
        hasLength(2),
      );
      expect(data['selection']['excluded'], {
        'pending': 1,
        'deleted': 1,
        'cancelled': 2,
        'nonMonetary': 1,
        'unconfirmed': 1,
        'nonObserved': 1,
      });
    },
  );

  test(
    'null category, private custom categories, unresolved and virtual accounts, currencies',
    () async {
      final c = exportFixtureController([
        exportFixtureTransaction(
          'usd',
          currency: 'USD',
          account: 'private-virtual',
          category: null,
        ),
        exportFixtureTransaction(
          'eur',
          currency: 'EUR',
          account: 'missing',
          category: 'PRIVATE_CUSTOM_CATEGORY',
        ),
        exportFixtureTransaction('cny', currency: 'CNY'),
      ]);
      addTearDown(c.dispose);
      final data = await export(c);
      final rows = data['transactions'] as List;
      expect(rows.map((r) => r['amount']['currency']).toSet(), {
        'USD',
        'EUR',
        'CNY',
      });
      expect(
        rows.singleWhere(
          (r) => r['accountResolution'] == 'unresolved',
        )['accountId'],
        isNull,
      );
      expect(
        rows.singleWhere(
          (r) => r['accountResolution'] == 'virtual',
        )['categoryId'],
        isNull,
      );
      expect(jsonEncode(data), isNot(contains('PRIVATE_CUSTOM_CATEGORY')));
    },
  );

  test('empty and large histories are not truncated', () async {
    for (final count in [0, 10000]) {
      final c = exportFixtureController(
        List.generate(count, (i) => exportFixtureTransaction('private-$i')),
      );
      final data = await export(c);
      expect(data['transactions'], hasLength(count));
      c.dispose();
    }
  });

  test('shared presets preserve calendar semantics including all time', () {
    final expected = {
      StatisticsPeriodPreset.last30Days: DateTime(2026, 8, 25),
      StatisticsPeriodPreset.threeMonths: DateTime(2026, 7),
      StatisticsPeriodPreset.sixMonths: DateTime(2026, 4),
      StatisticsPeriodPreset.last12Months: DateTime(2025, 10),
      StatisticsPeriodPreset.allTime: DateTime(2024, 2, 3),
    };
    for (final e in expected.entries) {
      final range = statisticsPeriodRange(
        preset: e.key,
        reference: DateTime(2026, 9, 23),
        transactionDates: [DateTime(2024, 2, 3)],
      )!;
      expect(range.start, e.value);
      expect(range.end, DateTime(2026, 9, 23));
    }
    expect(
      statisticsPeriodRange(
        preset: StatisticsPeriodPreset.custom,
        reference: DateTime(2026),
      ),
      isNull,
    );
  });
}
