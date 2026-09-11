import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  final date = DateTime(2026, 9, 6, 12);
  const account = SynoballAccount(
    id: 'A',
    entityId: 'ent-user',
    name: 'Test bank',
    type: SynoballAccountType.checking,
    currency: 'RUB',
    balance: Money(minorUnits: 99999, currency: 'RUB'),
  );
  SynoballCore core() =>
      SynoballCore(initialState: const SynoballState(accounts: [account]));
  IngestionOutcome ingest(
    SynoballCore engine, {
    String provider = 'provider-1',
    String status = 'posted',
    int minor = 10025,
  }) => engine.ingest(
    StatementAdapter(),
    StatementInput(
      entityId: 'ent-user',
      receivedAt: date,
      rawPayload: 'synthetic',
      batchName: 'Test',
      account: account,
      transactions: [
        TransactionSeed(
          accountId: 'A',
          amount: Money(minorUnits: minor, currency: 'RUB'),
          direction: FinancialDirection.outflow,
          occurredAt: date,
          description: 'Coffee',
          merchant: 'Coffee',
          category: 'cafes',
          providerTransactionId: provider,
          tags: ['status-$status'],
          confidence: 1,
        ),
      ],
    ),
  );

  test(
    'provider replay after restart stays deleted and preserves original data',
    () {
      var engine = core();
      final id = ingest(engine).createdTransactionIds.single;
      final evidenceId = engine.state.evidence.single.id;
      engine.deleteTransaction(id, actorId: 'user');
      final deletedAt = engine.transactionById(id)!.updatedAt;
      engine = SynoballCore(
        initialState: SynoballState.fromJson(
          jsonDecode(jsonEncode(engine.state.toJson())),
        ),
      );
      final replay = ingest(engine, minor: 50000);
      expect(replay.createdTransactionIds, isEmpty);
      expect(replay.matchedTransactionIds, isEmpty);
      expect(replay.pendingCandidateIds, isEmpty);
      expect(replay.suppressedTransactionIds, [id]);
      for (var attempt = 0; attempt < 4; attempt++) {
        expect(ingest(engine, minor: 50000).suppressedTransactionIds, [id]);
      }
      expect(engine.state.evidence, hasLength(2));
      expect(engine.transactions, isEmpty);
      expect(engine.transactionById(id)!.amount.minorUnits, 10025);
      expect(engine.transactionById(id)!.updatedAt, deletedAt);
      expect(
        engine.state.evidence.map((item) => item.id),
        contains(evidenceId),
      );
      expect(engine.restoreDeletedTransaction(id, actorId: 'user'), isTrue);
      expect(engine.transactions.single.id, id);
      expect(engine.transactions.single.amount.minorUnits, 10025);
      expect(engine.transactions.single.effectiveCategory, 'cafes');
      expect(engine.restoreDeletedTransaction(id, actorId: 'user'), isFalse);
      expect(ingest(engine).createdTransactionIds, isEmpty);
      expect(
        engine.state.events.where(
          (event) => event.type == 'transaction.deleted',
        ),
        hasLength(1),
      );
      expect(
        engine.state.events.where(
          (event) => event.type == 'transaction.restored',
        ),
        hasLength(1),
      );
    },
  );

  for (final status in ['pending', 'cancelled']) {
    test('restoration preserves lifecycle $status rather than posting it', () {
      final engine = core();
      final id = ingest(engine, status: status).createdTransactionIds.single;
      final before = engine.transactionById(id)!.status;
      engine.deleteTransaction(id, actorId: 'user');
      engine.deleteTransaction(id, actorId: 'user');
      engine.restoreDeletedTransaction(id, actorId: 'user');
      expect(engine.transactionById(id)!.status, before);
      expect(
        engine.state.events.where(
          (event) => event.type == 'transaction.deleted',
        ),
        hasLength(1),
      );
    });
  }

  test(
    'similar new source ID requires review, not silent suppression or resurrection',
    () {
      final engine = core();
      final id = ingest(engine).createdTransactionIds.single;
      engine.deleteTransaction(id, actorId: 'user');
      final unknown = ingest(engine, provider: 'different-id');
      expect(unknown.createdTransactionIds, isEmpty);
      expect(unknown.suppressedTransactionIds, isEmpty);
      expect(unknown.pendingCandidateIds, hasLength(1));
      expect(
        engine.pendingCandidates.single.tags,
        contains('review-possible_deleted_transaction'),
      );
    },
  );

  test(
    'stale edit and old snapshot restore cannot bypass the trash command',
    () {
      final engine = core();
      final id = ingest(engine).createdTransactionIds.single;
      final stale = engine.transactionById(id)!;
      engine.deleteTransaction(id, actorId: 'user');
      expect(
        () => engine.updateTransaction(stale, actorId: 'user'),
        throwsStateError,
      );
      expect(() => engine.restoreTransaction(stale), throwsStateError);
      expect(engine.transactions, isEmpty);
    },
  );

  test(
    'restore can recover an operation whose imported account was undone',
    () {
      final engine = core();
      final id = ingest(engine).createdTransactionIds.single;
      engine.deleteTransaction(id, actorId: 'user');
      engine.removeAccountIfUnused('A');
      expect(engine.state.accounts, isEmpty);
      engine.restoreDeletedTransaction(id, actorId: 'user');
      expect(engine.state.accounts.single.id, 'A');
      expect(engine.state.accounts.single.isVirtual, isTrue);
      expect(engine.state.accounts.single.balance.minorUnits, 0);
      expect(engine.state.accounts.single.name, contains('Test bank'));
    },
  );

  test(
    'controller codec restart preserves trash, receipt and exact financial effect',
    () async {
      final engine = core();
      final id = ingest(engine).createdTransactionIds.single;
      engine.updateTransaction(
        engine
            .transactionById(id)!
            .copyWith(
              receiptId: 'receipt-1',
              userCategoryOverride: 'travel',
              merchantName: 'My title',
            ),
        actorId: 'user',
      );
      final stateJson = engine.state.toJson();
      stateJson['receipts'] = [
        SynoballReceipt(
          id: 'receipt-1',
          ingestionRecordId: 'test',
          purchasedAt: date,
          total: const Money(minorUnits: 10025, currency: 'RUB'),
          fiscalFingerprint: '1:2:3',
          rawText: 'synthetic',
          items: const [
            ReceiptItem(
              name: 'Coffee',
              quantity: 1,
              total: Money(minorUnits: 10025, currency: 'RUB'),
            ),
          ],
        ).toJson(),
      ];
      final data = UserFinancialData(
        user: const QestoUser(id: 'user', name: 'Test', defaultCurrency: 'RUB'),
        referenceDate: date,
        synoballState: SynoballState.fromJson(stateJson),
      );
      var controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: data,
      );
      await controller.deleteTransaction(id);
      expect(controller.transactions, isEmpty);
      expect(controller.trashedTransactions, hasLength(1));
      expect(
        controller
            .cashFlowForRange(
              from: DateTime(2026, 9, 1),
              toExclusive: DateTime(2026, 10, 1),
            )
            .netCashFlowMinor,
        0,
      );
      const codec = UserFinancialDataCodec();
      controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: codec.decode(codec.encode(controller.mergeInto(data))),
      );
      expect(controller.trashedTransactions.single.id, id);
      await controller.restoreTrashedTransactions([id, id]);
      expect(controller.trashedTransactions, isEmpty);
      expect(controller.transactions.single.amountMinor, 10025);
      expect(controller.transactions.single.categoryId, 'travel');
      expect(controller.transactions.single.merchant, 'My title');
      expect(
        controller.transactions.single.receipt!.items.single.name,
        'Coffee',
      );
      expect(controller.accounts.single.balanceMinor, 99999);
      expect(
        controller
            .cashFlowForRange(
              from: DateTime(2026, 9, 1),
              toExclusive: DateTime(2026, 10, 1),
            )
            .netCashFlowMinor,
        -10025,
      );
    },
  );
}
