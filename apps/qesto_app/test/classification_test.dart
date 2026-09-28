import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/ai_export/data/ai_export_snapshot.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';

const account = QestoAccount(
  id: 'account',
  userId: 'test',
  title: 'Test account',
  balance: 1000,
  currency: 'RUB',
  type: AccountType.bankCard,
);
CanonicalTransaction classificationTransaction(
  String id, {
  String merchant = 'Пятёрочка',
  FinancialDirection direction = FinancialDirection.outflow,
  String entity = 'ent-test',
  List<String> tags = const [],
  int day = 10,
  String category = 'groceries',
}) => CanonicalTransaction(
  id: id,
  entityId: entity,
  accountId: account.id,
  eventType: FinancialEventType.observed,
  amount: const Money(minorUnits: 43050, currency: 'RUB'),
  direction: direction,
  status: CanonicalTransactionStatus.posted,
  occurredAt: DateTime(2026, 9, day),
  merchantName: merchant,
  rawDescription: merchant,
  normalizedDescription: merchant,
  synoballCategory: category,
  fieldTrust: SourceTrustLevel.bankStatement,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  tags: tags,
);
UserFinancialData classificationData({List<CanonicalTransaction>? rows}) =>
    UserFinancialData(
      user: const QestoUser(id: 'test', name: 'Test', defaultCurrency: 'RUB'),
      referenceDate: DateTime(2026, 9, 25),
      accounts: const [account],
      synoballState: SynoballState(
        accounts: const [
          SynoballAccount(
            id: 'account',
            entityId: 'ent-test',
            name: 'Test account',
            type: SynoballAccountType.card,
            currency: 'RUB',
            balance: Money(minorUnits: 100000, currency: 'RUB'),
          ),
        ],
        transactions:
            rows ??
            [
              classificationTransaction('one'),
              classificationTransaction(
                'two',
                merchant: 'PYATEROCHKA 123 MOSCOW',
                day: 11,
              ),
              classificationTransaction(
                'different',
                merchant: 'Private cafe',
                day: 12,
              ),
            ],
      ),
    );
BudgetController classificationController({UserFinancialData? data}) =>
    BudgetController(
      configuration: budgetConfiguration,
      financialData: data ?? classificationData(),
    );

Future<int> statement(
  BudgetController c,
  String id, {
  String merchant = 'Пятёрочка',
  int day = 22,
  bool bankWeb = false,
  List<String> tags = const [],
}) => c.importStatement(
  account: account,
  createdPeriodIds: {},
  actionTitle: 'Synthetic import',
  bankWebSource: bankWeb,
  connectionId: bankWeb ? 'test-connection' : null,
  transactions: [
    BudgetTransaction(
      id: id,
      userId: 'test',
      accountId: 'account',
      date: DateTime(2026, 9, day),
      amount: 430,
      exactAmountMinor: 43050,
      currency: 'RUB',
      type: TransactionType.expense,
      categoryId: 'groceries',
      merchant: merchant,
      description: merchant,
      tags: tags,
    ),
  ],
  providerTransactionIdsByTransactionId: {id: 'provider-$id'},
);

void main() {
  test('rapid category/tag IDs never collide', () async {
    final c = classificationController();
    addTearDown(c.dispose);
    final tagIds = <String>{}, categoryIds = <String>{};
    for (var i = 0; i < 30; i++) {
      tagIds.add((await c.saveUserTag(name: 'Tag $i', colorValue: 0)).id);
      categoryIds.add(
        (await c.createCategory(
          name: 'Category $i',
          iconKey: 'cart',
          colorValue: 0,
        )).id,
      );
    }
    expect(tagIds, hasLength(30));
    expect(categoryIds, hasLength(30));
  });
  test(
    'merge repairs legacy projected Sber category in canonical export',
    () async {
      final c = classificationController(
        data: classificationData(
          rows: [
            classificationTransaction(
              'legacy',
              category: 'other',
              tags: ['sberbank'],
            ),
          ],
        ),
      );
      addTearDown(c.dispose);
      expect(c.transactions.single.categoryId, 'groceries');
      await c.updateTransaction(
        c.transactions.single.copyWith(comment: 'Note only'),
      );
      expect(c.synoballState.transactions.single.userCategoryOverride, isNull);
      await c.mergeCategories('groceries', 'cafes');
      expect(c.transactions.single.categoryId, 'cafes');
      expect(c.synoballState.transactions.single.effectiveCategory, 'cafes');
      expect(
        captureAiExportSnapshot(c).transactions.single.categoryId,
        'cafes',
      );
    },
  );
  test(
    'category merge preserves recurring detection, exact cash flow and balances',
    () async {
      final c = classificationController(
        data: classificationData(
          rows: [
            for (var m = 6; m <= 9; m++)
              classificationTransaction(
                'monthly-$m',
              ).copyWith(occurredAt: DateTime(2026, m, 10)),
          ],
        ),
      );
      addTearDown(c.dispose);
      expect(c.synoballState.recurringStreams, hasLength(1));
      final before = c
          .cashFlowForRange(
            from: DateTime(2026, 6),
            toExclusive: DateTime(2026, 10),
          )
          .netCashFlowMinor;
      final balance = c.accounts.single.balanceMinor;
      await c.mergeCategories('groceries', 'cafes');
      expect(c.synoballState.recurringStreams, hasLength(1));
      expect(
        c
            .cashFlowForRange(
              from: DateTime(2026, 6),
              toExclusive: DateTime(2026, 10),
            )
            .netCashFlowMinor,
        before,
      );
      expect(c.accounts.single.balanceMinor, balance);
    },
  );
  test('new manually selected category overrides merchant rule', () async {
    final c = classificationController();
    addTearDown(c.dispose);
    await c.changeTransactionCategory(
      'one',
      'cafes',
      scope: CategoryChangeScope.always,
    );
    await c.addExpense(
      period: c.periods.first,
      amount: 777,
      date: DateTime(2026, 9, 24),
      categoryId: 'education',
      accountId: account.id,
      title: 'Пятёрочка',
    );
    final added = c.synoballState.transactions.firstWhere(
      (t) => t.occurredAt.day == 24,
    );
    expect(added.userCategoryOverride, 'education');
    expect(added.effectiveCategory, 'education');
  });
  test(
    'same policy used by notifications, SMS, receipts, screenshots and voice',
    () async {
      final c = classificationController();
      addTearDown(c.dispose);
      await c.changeTransactionCategory(
        'one',
        'cafes',
        scope: CategoryChangeScope.always,
      );
      final core = SynoballCore(
        initialState: c.synoballState,
        categoryPolicy: c.classification.policy,
      );
      TransactionSeed seed(int day) => TransactionSeed(
        accountId: 'account',
        amount: Money(minorUnits: 43050 + day * 50000, currency: 'RUB'),
        direction: FinancialDirection.outflow,
        occurredAt: DateTime(2026, 9, day),
        description: 'PYATEROCHKA',
        confidence: 1,
        merchant: 'PYATEROCHKA 123 MOSCOW',
        category: 'groceries',
        providerTransactionId: 'new-$day',
      );
      core.ingest(
        AndroidNotificationAdapter(),
        AndroidNotificationInput(
          entityId: 'ent-test',
          receivedAt: DateTime(2026, 9, 20),
          rawPayload: 'Synthetic',
          notificationKey: 'n20',
          packageName: 'ru.sberbankmobile',
          transaction: seed(20),
        ),
      );
      core.ingest(
        SmsNotificationAdapter(),
        SmsNotificationInput(
          entityId: 'ent-test',
          receivedAt: DateTime(2026, 9, 21),
          rawPayload: 'Synthetic',
          notificationKey: 'n21',
          packageName: 'sms',
          sender: '900',
          transaction: seed(21),
        ),
      );
      core.ingest(
        ReceiptAdapter(),
        ReceiptInput(
          entityId: 'ent-test',
          receivedAt: DateTime(2026, 9, 22),
          rawPayload: 'Synthetic',
          rawText: 'Synthetic receipt',
          fiscalFingerprint: 'fixture-only',
          transaction: seed(22),
        ),
      );
      core.ingest(
        BankScreenshotAdapter(),
        BankScreenshotInput(
          entityId: 'ent-test',
          receivedAt: DateTime(2026, 9, 23),
          rawPayload: 'Synthetic',
          batchName: 'Fixture screenshot',
          imageHashes: ['fixture'],
          parserIds: ['fixture'],
          transactions: [seed(23)],
        ),
      );
      final voice = core.ingest(
        VoiceInputAdapter(),
        VoiceInput(
          entityId: 'ent-test',
          receivedAt: DateTime(2026, 9, 24),
          rawPayload: 'Synthetic',
          transcript: 'Synthetic',
          transaction: seed(24),
        ),
      );
      for (final candidate in voice.pendingCandidateIds) {
        core.confirmCandidate(candidate, actorId: 'test');
      }
      final added = core.transactions
          .where((t) => t.occurredAt.day >= 20)
          .toList();
      expect(added, hasLength(5));
      expect(added.map((t) => t.effectiveCategory), everyElement('cafes'));
      expect(added.map((t) => t.userCategoryOverride), everyElement(isNull));
    },
  );
  test(
    'unknown merchant cannot create broad rule; merges are transitive and safe',
    () async {
      final c = classificationController(
        data: classificationData(
          rows: [classificationTransaction('unknown', merchant: 'Операция')],
        ),
      );
      addTearDown(c.dispose);
      expect(c.canCreateMerchantRule('unknown'), isFalse);
      expect(
        () => c.changeTransactionCategory(
          'unknown',
          'cafes',
          scope: CategoryChangeScope.always,
        ),
        throwsStateError,
      );
      expect(
        () => c.mergeCategories('groceries', 'groceries'),
        throwsArgumentError,
      );
      await c.mergeCategories('groceries', 'cafes');
      await c.mergeCategories('cafes', 'education');
      expect(c.transactions.single.categoryId, 'education');
      expect(c.categoryById('groceries').id, 'education');
      final core = SynoballCore(
        initialState: c.synoballState,
        categoryPolicy: c.classification.policy,
      );
      core.restoreTransaction(classificationTransaction('unknown'));
      expect(core.transactionById('unknown')!.effectiveCategory, 'education');
    },
  );
  test(
    'single manual assignment, same category lock, note edit is not category lock',
    () async {
      final data = classificationData();
      final c = classificationController(
        data: data.copyWith(
          synoballState: SynoballState(
            accounts: data.synoballState!.accounts,
            transactions: [
              data.synoballState!.transactions.first.copyWith(
                subcategoryId: 'Молочные продукты',
              ),
              ...data.synoballState!.transactions.skip(1),
            ],
          ),
        ),
      );
      addTearDown(c.dispose);
      await c.updateTransaction(
        c.transactions.first.copyWith(comment: 'Just a note'),
      );
      expect(c.synoballState.transactions.first.userCategoryOverride, isNull);
      await c.changeTransactionCategory('one', 'groceries');
      expect(
        c.synoballState.transactions.first.subcategoryId,
        'Молочные продукты',
      );
      expect(
        c.synoballState.transactions.first.userCategoryOverride,
        'groceries',
      );
      await c.changeTransactionCategory('one', 'cafes');
      expect(c.synoballState.transactions.first.subcategoryId, isNull);
      expect(c.transactions.first.categoryId, 'cafes');
      await c.updateTransactions(
        c.transactions.where((t) => t.id != 'one'),
        explicitCategorySelection: true,
      );
      expect(
        c.synoballState.transactions
            .where((t) => t.id != 'one')
            .map((t) => t.userCategoryOverride),
        everyElement('groceries'),
      );
      expect(
        c.transactions.where((t) => t.id != 'one').map((t) => t.categoryId),
        everyElement('groceries'),
      );
    },
  );
  test(
    'bulk uses normalized identity, direction and entity, no arbitrary contains',
    () async {
      final c = classificationController(
        data: classificationData(
          rows: [
            classificationTransaction('one', merchant: 'Campus canteen'),
            classificationTransaction(
              'two',
              merchant: 'CAMPUS CANTEEN',
              day: 11,
            ),
            classificationTransaction(
              'other',
              merchant: 'Campus canteen supplier',
            ),
            classificationTransaction(
              'in',
              merchant: 'Campus canteen',
              direction: FinancialDirection.inflow,
            ),
            classificationTransaction(
              'entity',
              merchant: 'Campus canteen',
              entity: 'ent-other',
            ),
          ],
        ),
      );
      addTearDown(c.dispose);
      expect(
        await c.changeTransactionCategory(
          'one',
          'cafes',
          scope: CategoryChangeScope.history,
        ),
        2,
      );
      expect(
        c.transactions.where((t) => t.categoryId == 'cafes').map((t) => t.id),
        ['one', 'two'],
      );
      expect(c.classification.rules, isEmpty);
    },
  );
  for (final bankWeb in [false, true]) {
    test(
      'rule on staged ${bankWeb ? 'bank web' : 'statement'} import and manual/tags survive repeat',
      () async {
        final c = classificationController();
        addTearDown(c.dispose);
        await c.changeTransactionCategory(
          'one',
          'cafes',
          scope: CategoryChangeScope.always,
        );
        expect(c.classification.rules, hasLength(1));
        await statement(c, 'new', bankWeb: bankWeb, tags: ['sberbank']);
        var added = c.transactions.firstWhere((t) => t.date.day == 22);
        expect(added.categoryId, 'cafes');
        final tag1 = await c.saveUserTag(
          name: 'универ',
          colorValue: 0xff123456,
        );
        final tag2 = await c.saveUserTag(name: 'обед', colorValue: 0xffabcdef);
        await c.setTransactionTags(added.id, {tag1.id, tag2.id});
        await c.changeTransactionCategory(added.id, 'education');
        final beforeCount = c.transactions.length;
        await statement(c, 'new', bankWeb: bankWeb, tags: ['sberbank']);
        added = c.transactions.firstWhere((t) => t.date.day == 22);
        expect(c.transactions.length, beforeCount);
        expect(added.categoryId, 'education');
        expect(c.tagsForTransaction(added), hasLength(2));
        expect(added.tags, contains('sberbank'));
        await c.setTransactionTags(added.id, {tag2.id});
        await statement(
          c,
          'new',
          bankWeb: bankWeb,
          tags: ['sberbank', '$userLabelPrefix${tag1.id}'],
        );
        expect(
          c
              .tagsForTransaction(
                c.transactions.firstWhere((t) => t.id == added.id),
              )
              .map((t) => t.id),
          [tag2.id],
        );
      },
    );
  }
  test(
    'custom category stable ID, rule edits/deletion, codec restart and export metadata',
    () async {
      final c = classificationController();
      addTearDown(c.dispose);
      final custom = await c.createCategory(
        name: 'Столовая',
        iconKey: 'cafe',
        colorValue: 0xff123456,
      );
      await c.changeTransactionCategory(
        'one',
        custom.id,
        scope: CategoryChangeScope.always,
      );
      await c.updateCategoryAppearance(
        categoryId: custom.id,
        name: 'Обеды',
        iconKey: 'cart',
        colorValue: 0xffabcdef,
      );
      expect(c.transactions.first.categoryId, custom.id);
      expect(c.categoryById(custom.id).name, 'Обеды');
      final encoded = const UserFinancialDataCodec().encode(
        c.mergeInto(classificationData()),
      );
      final restored = classificationController(
        data: const UserFinancialDataCodec().decode(encoded),
      );
      addTearDown(restored.dispose);
      expect(restored.categoryById(custom.id).name, 'Обеды');
      expect(restored.classification.rules.single.categoryId, custom.id);
      expect(
        captureAiExportSnapshot(restored).categoryNames[custom.id],
        'Обеды',
      );
      await restored.updateCategoryRule(
        restored.classification.rules.single.id,
        categoryId: 'education',
      );
      await statement(restored, 'new');
      expect(
        restored.transactions.firstWhere((t) => t.date.day == 22).categoryId,
        'education',
      );
      await restored.updateCategoryRule(
        restored.classification.rules.single.id,
      );
      await statement(restored, 'newer', day: 23);
      expect(
        restored.transactions.firstWhere((t) => t.date.day == 23).categoryId,
        'groceries',
      );
      expect(
        restored.transactions.firstWhere((t) => t.id == 'one').categoryId,
        custom.id,
      );
    },
  );
  test('system rename stable, validation and empty custom delete', () async {
    final c = classificationController();
    addTearDown(c.dispose);
    await c.updateCategoryAppearance(
      categoryId: 'groceries',
      name: 'Еда дома',
      iconKey: 'cart',
      colorValue: 0xff123456,
    );
    expect(c.transactions.first.categoryId, 'groceries');
    expect(
      () => c.createCategory(name: '   ', iconKey: 'cart', colorValue: 0),
      throwsArgumentError,
    );
    expect(
      () => c.createCategory(name: 'еда дома', iconKey: 'cart', colorValue: 0),
      throwsArgumentError,
    );
    final custom = await c.createCategory(
      name: 'Empty',
      iconKey: 'cart',
      colorValue: 0,
    );
    await c.deleteCategory(custom.id);
    expect(c.categories.any((v) => v.id == custom.id), isFalse);
    expect(() => c.deleteCategory('groceries'), throwsStateError);
  });
  test(
    'safe merge covers trash, plans, rules, budgets, future import and restore',
    () async {
      final c = classificationController();
      addTearDown(c.dispose);
      final custom = await c.createCategory(
        name: 'Meals',
        iconKey: 'cafe',
        colorValue: 0,
      );
      await c.changeTransactionCategory(
        'one',
        custom.id,
        scope: CategoryChangeScope.always,
      );
      await c.deleteTransaction('two');
      await c.setCategoryBudget(
        period: c.periods.first,
        categoryId: custom.id,
        plannedAmount: 1000,
      );
      await c.setCategoryBudget(
        period: c.periods.first,
        categoryId: 'cafes',
        plannedAmount: 2000,
      );
      await c.addUpcoming(
        UpcomingExpense(
          id: 'plan',
          userId: 'test',
          budgetPeriodId: c.periods.first.id,
          title: 'Lunch plan',
          amount: 500,
          currency: 'RUB',
          plannedDate: DateTime(2026, 9, 28),
          source: UpcomingExpenseSource.manual,
          categoryId: custom.id,
        ),
      );
      expect(() => c.deleteCategory(custom.id), throwsStateError);
      final money = c.synoballState.transactions
          .map((t) => t.amount.minorUnits)
          .toList();
      final dates = c.synoballState.transactions
          .map((t) => t.occurredAt)
          .toList();
      await c.mergeCategories(custom.id, 'cafes');
      expect(c.classification.rules.single.categoryId, 'cafes');
      expect(c.trashedTransactions.single.effectiveCategory, 'cafes');
      expect(c.categoryBudgets.single.plannedAmount, 3000);
      expect(c.categoryBudgets.single.categoryId, 'cafes');
      expect(c.upcomingExpenses.single.categoryId, 'cafes');
      expect(c.upcomingExpenses.single.amount, 500);
      expect(
        c.synoballState.transactions.map((t) => t.amount.minorUnits),
        money,
      );
      expect(c.synoballState.transactions.map((t) => t.occurredAt), dates);
      await c.restoreTrashedTransactions(['two']);
      expect(
        c.transactions.firstWhere((t) => t.id == 'two').categoryId,
        'cafes',
      );
      await statement(c, 'new');
      expect(
        c.transactions.firstWhere((t) => t.date.day == 22).categoryId,
        'cafes',
      );
      await c.mergeCategories('groceries', 'cafes');
      expect(c.hiddenSystemCategories.map((c) => c.id), contains('groceries'));
      await statement(
        c,
        'other-new',
        merchant: 'Other store',
        day: 23,
        tags: ['sberbank'],
      );
      expect(c.transactions.every((t) => t.categoryId != 'groceries'), isTrue);
      await c.restoreSystemCategory('groceries');
      expect(c.categories.any((c) => c.id == 'groceries'), isTrue);
    },
  );
  test(
    'tags rename, delete from trash and undo snapshots cannot resurrect deleted tag',
    () async {
      final c = classificationController();
      addTearDown(c.dispose);
      final tag = await c.saveUserTag(name: 'First', colorValue: 0);
      await c.setTransactionTags('one', {tag.id});
      final snapshot = c.synoballState.transactions.first;
      await c.saveUserTag(id: tag.id, name: 'Renamed', colorValue: 0xff123456);
      expect(c.tagsForTransaction(c.transactions.first).single.name, 'Renamed');
      await c.deleteTransaction('one');
      await c.deleteUserTag(tag.id);
      expect(
        c.trashedTransactions.single.tags.where(
          (s) => s.startsWith(userLabelPrefix),
        ),
        isEmpty,
      );
      await c.restoreTrashedTransactions(['one']);
      expect(c.transactions, hasLength(3));
      final core = SynoballCore(
        initialState: c.synoballState,
        categoryPolicy: c.classification.policy,
      );
      core.restoreTransaction(snapshot);
      expect(
        core
            .transactionById('one')!
            .tags
            .where((s) => s.startsWith(userLabelPrefix)),
        isEmpty,
      );
    },
  );
  test(
    'legacy v6 profile migrates additively, financial clear resets classification',
    () async {
      final root =
          jsonDecode(
                const UserFinancialDataCodec().encode(classificationData()),
              )
              as Map<String, dynamic>;
      root['schemaVersion'] = 6;
      root.remove('classification');
      final data = const UserFinancialDataCodec().decode(jsonEncode(root));
      expect(data.classification.customCategories, isEmpty);
      expect(data.synoballState!.transactions, hasLength(3));
      final c = classificationController(data: data);
      addTearDown(c.dispose);
      await c.createCategory(name: 'Custom', iconKey: 'cafe', colorValue: 0);
      await c.clearAllFinancialData();
      expect(c.classification.customCategories, isEmpty);
      expect(c.classification.rules, isEmpty);
      expect(c.classification.tags, isEmpty);
      expect(c.categories.length, budgetConfiguration.categories.length);
    },
  );
}
