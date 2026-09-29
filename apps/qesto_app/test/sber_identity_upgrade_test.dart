import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_extractors.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/mocks/fixtures/empty_user_financial_data.dart';
import 'package:qesto/synoball/adapters/adapters.dart';
import 'package:qesto/synoball/adapters/source_identity.dart';
import 'package:qesto/synoball/adapters/transaction_inputs.dart';
import 'package:qesto/synoball/core/models.dart';
import 'package:qesto/synoball/core/synoball_core.dart';
import 'package:qesto/synoball/reconciliation/bank_web_identity_upgrade.dart';
import 'package:qesto/synoball/reconciliation/bank_web_identity_quality.dart';

final day = DateTime(2026, 8, 18);
const connection = 'fixture-profile';
final entity = 'ent-${emptyUserFinancialData.user.id}';
SynoballAccount account(String id, {bool virtual = false}) => SynoballAccount(
  id: id,
  entityId: entity,
  name: id,
  type: SynoballAccountType.checking,
  currency: 'RUB',
  balance: const Money(minorUnits: 0, currency: 'RUB'),
  isVirtual: virtual,
  connectionId: virtual ? null : connection,
  institutionId: 'sberbank',
);
List<SberTransactionFact> facts(int count) =>
    const SberExtractors().normalizeTransactionRows(
      [
        for (var i = 0; i < count; i++)
          {
            'id': 'bank-operation-$i',
            'text': 'Merchant A 90 ₽ Оплата товаров и услуг',
            'merchant': 'Merchant A',
            'operationType': 'Оплата товаров и услуг',
            'description': 'Merchant A · Оплата товаров и услуг',
            'amount': '90 ₽',
            'amountValue': 90,
            'dateIso': '2026-08-18',
          },
      ],
      range: SberSyncRange(
        from: day,
        toExclusive: day.add(const Duration(days: 1)),
        label: 'fixture',
      ),
    );
String modern(SberTransactionFact f) =>
    sourceIdentity('sber-operation-v2', [connection, f.sourceId]);
String provider(SberTransactionFact f) =>
    sourceIdentity('sber-provider-v1', [connection, f.sourceId]);
BankWebIdentityUpgrade proof(SberTransactionFact f) => BankWebIdentityUpgrade(
  canonicalId: modern(f),
  providerId: provider(f),
  legacyIds: f.legacyTransactionIds,
  amount: Money(minorUnits: f.amountMinor, currency: f.currency),
  direction: FinancialDirection.outflow,
  occurredAt: f.date,
  description: f.description,
);
SynoballCore core() => SynoballCore(
  initialState: SynoballState(
    accounts: [
      account('sber-account-a'),
      account('sber-account-b'),
      account('sber-unassigned-RUB', virtual: true),
    ],
  ),
);
void ingest(
  SynoballCore c,
  List<SberTransactionFact> rows, {
  bool legacy = false,
  String accountId = 'sber-unassigned-RUB',
}) {
  c.ingest(
    BankWebAdapter(),
    StatementInput(
      entityId: entity,
      connectionId: legacy ? null : connection,
      institutionId: legacy ? null : 'sberbank',
      receivedAt: DateTime(2026, 9, legacy ? 1 : 10),
      rawPayload: 'fixture',
      batchName: 'fixture',
      account: c.state.accounts.firstWhere((a) => a.id == accountId),
      transactions: [
        for (final f in rows)
          TransactionSeed(
            canonicalId: legacy ? f.legacyTransactionIds.last : modern(f),
            accountId: accountId,
            amount: Money(minorUnits: f.amountMinor, currency: f.currency),
            direction: FinancialDirection.outflow,
            occurredAt: f.date,
            description: f.description,
            merchant: f.merchant,
            confidence: 0.95,
            providerTransactionId: legacy
                ? f.legacyTransactionIds.last
                : provider(f),
            tags: [
              'sber-live',
              'sberbank',
              'legacy-type-expense',
              if (!legacy) 'sber-identity:v2',
            ],
          ),
      ],
    ),
  );
}

void main() {
  test(
    'same provider unresolved to resolved and repeat retains canonical ID',
    () {
      final c = core(), rows = facts(1);
      ingest(c, rows);
      final id = c.state.transactions.single.id;
      ingest(c, rows, accountId: 'sber-account-a');
      ingest(c, rows, accountId: 'sber-account-a');
      expect(c.state.transactions, hasLength(1));
      expect(c.state.transactions.single.id, id);
      expect(c.state.transactions.single.accountId, 'sber-account-a');
    },
  );
  test(
    'three equal real payments remain three after resolution, not six or one',
    () {
      final c = core(), rows = facts(3);
      ingest(c, rows);
      ingest(c, rows, accountId: 'sber-account-a');
      expect(c.state.transactions, hasLength(3));
      expect(c.state.transactions.map((t) => t.accountId).toSet(), {
        'sber-account-a',
      });
    },
  );
  test(
    'legacy upgrade repairs three mirrored pairs with retained evidence and stable IDs',
    () {
      final c = core(), rows = facts(3);
      ingest(c, rows, legacy: true, accountId: 'sber-account-a');
      ingest(c, rows);
      expect(c.state.transactions, hasLength(6));
      expect(bankWebIdentityAmbiguities(c.state, entity), hasLength(1));
      final original = jsonEncode(c.state.toJson());
      final result = const BankWebIdentityReconciler().apply(
        c.state,
        entityId: entity,
        connectionId: connection,
        institutionId: 'sberbank',
        upgrades: rows.map(proof),
      );
      expect(jsonEncode(c.state.toJson()), original);
      expect(result.state.transactions, hasLength(3));
      expect(
        result.state.transactions.map((t) => t.id).toSet(),
        rows.map((f) => f.legacyTransactionIds.last).toSet(),
      );
      expect(result.state.evidence, hasLength(6));
      expect(
        result.state.events.where(
          (e) => e.type == 'transaction.identity-reconciled',
        ),
        hasLength(3),
      );
      final replay = SynoballCore(initialState: result.state);
      ingest(replay, rows);
      expect(replay.state.transactions, hasLength(3));
      expect(bankWebIdentityAmbiguities(replay.state, entity), isEmpty);
    },
  );
  test(
    'two real accounts and conflicting scope never merge despite a legacy bridge',
    () {
      final c = core(), rows = facts(1);
      ingest(c, rows, legacy: true, accountId: 'sber-account-a');
      ingest(c, rows, accountId: 'sber-account-b');
      for (final scope in [connection, 'different-profile']) {
        final result = const BankWebIdentityReconciler().apply(
          c.state,
          entityId: entity,
          connectionId: scope,
          institutionId: 'sberbank',
          upgrades: rows.map(proof),
        );
        expect(result.state.transactions, hasLength(2));
        expect(result.targets, isEmpty);
      }
    },
  );
  test('hash collision / two provider claims and absent proof fail closed', () {
    final c = core(), rows = facts(2);
    ingest(c, rows, legacy: true, accountId: 'sber-account-a');
    ingest(c, rows);
    final a = proof(rows.first), b = proof(rows.last);
    final collision = BankWebIdentityUpgrade(
      canonicalId: b.canonicalId,
      providerId: b.providerId,
      legacyIds: a.legacyIds,
      amount: b.amount,
      direction: b.direction,
      occurredAt: b.occurredAt,
      description: b.description,
    );
    final result = const BankWebIdentityReconciler().apply(
      c.state,
      entityId: entity,
      connectionId: connection,
      institutionId: 'sberbank',
      upgrades: [a, collision],
    );
    expect(result.state.transactions, hasLength(4));
    expect(result.targets, isEmpty);
  });
  test('user edits and trash are not overwritten by identity repair', () {
    for (final deleted in [true, false]) {
      final c = core(), rows = facts(1);
      ingest(c, rows, legacy: true, accountId: 'sber-account-a');
      ingest(c, rows);
      final json = c.state.toJson();
      final list = json['transactions'] as List;
      (list.last as Map)[deleted ? 'status' : 'tags'] = deleted
          ? 'deleted'
          : ['sber-live', 'sber-identity:v2', 'user-field:category'];
      final state = SynoballState.fromJson(json);
      final result = const BankWebIdentityReconciler().apply(
        state,
        entityId: entity,
        connectionId: connection,
        institutionId: 'sberbank',
        upgrades: rows.map(proof),
      );
      expect(jsonEncode(result.state.toJson()), jsonEncode(state.toJson()));
    }
  });
  test(
    'controller import performs root repair and second import is idempotent',
    () async {
      final c = core(), rows = facts(3);
      ingest(c, rows, legacy: true, accountId: 'sber-account-a');
      ingest(c, rows);
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: emptyUserFinancialData.copyWith(synoballState: c.state),
      );
      addTearDown(controller.dispose);
      final snapshot = SberSyncSnapshot(
        connectionId: connection,
        observedAt: DateTime(2026, 9, 24),
        accounts: const [],
        transactions: rows,
        oldestTransaction: day,
        newestTransaction: day,
        pendingCount: 0,
        pageType: SberPageType.transactions,
      );
      await controller.importSberSnapshot(snapshot);
      await controller.importSberSnapshot(snapshot);
      expect(controller.synoballState.transactions, hasLength(3));
      expect(controller.transactions, hasLength(3));
      expect(
        controller.synoballState.transactions.every(
          (t) => t.accountId == 'sber-account-a',
        ),
        isTrue,
      );
    },
  );
  test(
    'retained manual category survives; linked duplicate remains for review',
    () {
      final c = core(), rows = facts(1);
      ingest(c, rows, legacy: true, accountId: 'sber-account-a');
      ingest(c, rows);
      final json = c.state.toJson();
      ((json['transactions'] as List).first as Map)['userCategoryOverride'] =
          'user-category';
      final state = SynoballState.fromJson(json);
      final repaired = const BankWebIdentityReconciler().apply(
        state,
        entityId: entity,
        connectionId: connection,
        institutionId: 'sberbank',
        upgrades: rows.map(proof),
      );
      expect(
        repaired.state.transactions.single.userCategoryOverride,
        'user-category',
      );
      final protected = const BankWebIdentityReconciler().apply(
        state,
        entityId: entity,
        connectionId: connection,
        institutionId: 'sberbank',
        upgrades: rows.map(proof),
        protectedTransactionIds: {modern(rows.single)},
      );
      expect(protected.state.transactions, hasLength(2));
      expect(protected.targets, isEmpty);
    },
  );
}
