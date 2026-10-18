import 'dart:convert';

import 'package:qesto_synoball_core/qesto_synoball_core.dart';

/// Synthetic IDs only. Production factory behavior is not overridden globally.
class ParityIds extends SynoballIdFactory {
  ParityIds() : super(clock: () => parityNow);
  var _next = 0;

  @override
  String next(String prefix) => '$prefix-parity-${++_next}';
}

final parityNow = DateTime.utc(2026, 9, 8, 12);
const parityAccount = SynoballAccount(
  id: 'account-existing-001',
  entityId: 'entity-existing-001',
  name: 'Synthetic bank account',
  type: SynoballAccountType.checking,
  currency: 'RUB',
  balance: Money(minorUnits: 987654, currency: 'RUB'),
);

/// Kept business dates, source hashes, all IDs, raw/provenance and money intact.
/// Only the old core's uninjectable wall-clock bookkeeping is normalized.
Map<String, dynamic> normalizeParityState(SynoballState state) {
  final json = jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>;
  for (final transaction in json['transactions'] as List) {
    transaction['createdAt'] = '<core-clock>';
    transaction['updatedAt'] = '<core-clock>';
  }
  for (final key in ['events', 'auditEntries']) {
    for (final entry in json[key] as List) {
      entry['occurredAt'] = '<core-clock>';
      final payload = entry['payload'];
      if (payload is Map && payload.containsKey('changedAt')) {
        payload['changedAt'] = '<core-clock>';
      }
    }
  }
  return json;
}

class _Scenario {
  final ids = ParityIds();
  late SynoballCore core = SynoballCore(
    initialState: const SynoballState(accounts: [parityAccount]),
    ids: ids,
  );
  final steps = <Map<String, dynamic>>[];

  TransactionSeed seed(
    String? provider, {
    String accountId = 'account-existing-001',
    int minor = 10025,
    String currency = 'RUB',
    FinancialDirection direction = FinancialDirection.outflow,
    List<String> tags = const [],
    String? canonicalId,
    DateTime? occurredAt,
  }) => TransactionSeed(
    accountId: accountId,
    amount: Money(minorUnits: minor, currency: currency),
    direction: direction,
    occurredAt: occurredAt ?? parityNow,
    description: 'Synthetic Coffee',
    merchant: 'Synthetic Coffee',
    category: 'cafes',
    confidence: 1,
    providerTransactionId: provider,
    canonicalId: canonicalId,
    tags: tags,
  );

  void record(String label, [IngestionOutcome? result]) => steps.add({
    'step': label,
    if (result != null)
      'outcome': {
        'ingestionRecordId': result.ingestionRecordId,
        'created': result.createdTransactionIds,
        'matched': result.matchedTransactionIds,
        'pending': result.pendingCandidateIds,
        'batch': result.importBatchId,
        'warnings': result.warnings,
        'failed': result.failedCandidateIds,
        'resolved': result.resolvedTransactionIds,
        'suppressed': result.suppressedTransactionIds,
      },
    'state': normalizeParityState(core.state),
  });

  IngestionOutcome statement(
    List<TransactionSeed> seeds, {
    SynoballAccount account = parityAccount,
    String? connectionId,
    bool web = false,
  }) => core.ingest(
    web ? BankWebAdapter(ids: ids) : StatementAdapter(ids: ids),
    StatementInput(
      entityId: parityAccount.entityId,
      receivedAt: parityNow.add(const Duration(hours: 1)),
      rawPayload: '{"synthetic":"statement"}',
      batchName: 'Synthetic statement',
      transactions: seeds,
      account: account,
      connectionId: connectionId,
      institutionId: 'synthetic-bank',
    ),
  );

  IngestionOutcome notify({String key = 'slot-001'}) => core.ingest(
    AndroidNotificationAdapter(ids: ids, history: core.state),
    AndroidNotificationInput(
      entityId: parityAccount.entityId,
      receivedAt: parityNow,
      rawPayload: 'Synthetic notification only',
      packageName: 'test.synthetic.bank',
      notificationKey: key,
      transaction: seed(null),
      institutionId: 'synthetic-bank',
    ),
  );

  void restart() {
    core = SynoballCore(
      initialState: SynoballState.fromJson(
        jsonDecode(jsonEncode(core.state.toJson())) as Map<String, dynamic>,
      ),
      ids: ids,
    );
    record('serialized-and-restored');
  }
}

Map<String, List<Map<String, dynamic>>> runParityScenarios() {
  final cases = <String, List<Map<String, dynamic>>>{};
  void scenario(String name, void Function(_Scenario s) run) {
    final s = _Scenario();
    run(s);
    cases[name] = s.steps;
  }

  scenario('repeated-stable-provider', (s) {
    s.record('first', s.statement([s.seed('bank-existing-001')]));
    s.record('repeated', s.statement([s.seed('bank-existing-001')]));
    s.restart();
    s.record(
      'repeated-after-restore',
      s.statement([s.seed('bank-existing-001')]),
    );
  });
  scenario('two-similar-distinct-purchases', (s) {
    s.record('first', s.statement([s.seed('bank-001')]));
    s.record(
      'same-amount-time-different-provider',
      s.statement([s.seed('bank-002')]),
    );
    s.record(
      'one-kopeck-different',
      s.statement([s.seed('bank-003', minor: 10026)]),
    );
  });
  scenario('notification-statement-receipt', (s) {
    s.record('notification', s.notify());
    s.record('statement', s.statement([s.seed('bank-001')]));
    s.record(
      'receipt',
      s.core.ingest(
        ReceiptAdapter(ids: s.ids),
        ReceiptInput(
          entityId: parityAccount.entityId,
          receivedAt: parityNow.add(const Duration(hours: 2)),
          rawPayload: 'Synthetic receipt',
          transaction: s.seed('fiscal-001'),
          fiscalFingerprint: 'synthetic-fiscal-001',
          rawText: 'Synthetic Coffee 100.25 RUB',
          merchant: 'Synthetic Coffee',
          items: const [
            ReceiptItem(
              name: 'Coffee',
              total: Money(minorUnits: 10025, currency: 'RUB'),
            ),
          ],
        ),
      ),
    );
    s.restart();
  });
  scenario('user-overrides-and-field-locks', (s) {
    s.record('source', s.statement([s.seed('bank-001')]));
    final original = s.core.transactions.single;
    s.core.updateTransaction(
      original.copyWith(
        amount: const Money(minorUnits: 50123, currency: 'RUB'),
        merchantName: 'User title',
        normalizedDescription: 'User description',
        userNote: 'User note',
        userCategoryOverride: 'sport',
        tags: [
          'user-field:amount',
          'user-field:merchant',
          'user-field:description',
          'user-field:note',
          'user-field:category',
        ],
      ),
      actorId: 'synthetic-user',
    );
    s.record('manual-edit');
    s.record('reimport', s.statement([s.seed('bank-001')]));
    s.restart();
  });
  for (final lifecycle in ['posted', 'pending', 'cancelled']) {
    scenario('trash-replay-restore-$lifecycle', (s) {
      s.record(
        'original',
        s.statement([
          s.seed('bank-001', tags: ['status-$lifecycle']),
        ]),
      );
      final id = s.core.state.transactions.single.id;
      s.core.deleteTransaction(id, actorId: 'synthetic-user');
      s.record('deleted');
      s.restart();
      s.record(
        'source-replay',
        s.statement([s.seed('bank-001', minor: 50000)]),
      );
      if (!s.core.restoreDeletedTransaction(id, actorId: 'synthetic-user')) {
        throw StateError('Expected explicit restoration');
      }
      s.record('explicit-restore');
      s.record(
        'reimport-after-restore',
        s.statement([
          s.seed('bank-001', tags: ['status-$lifecycle']),
        ]),
      );
    });
  }
  for (final reverse in [false, true]) {
    scenario('ambiguous-cross-source-batch-$reverse', (s) {
      s.record('notification', s.notify());
      final rows = [s.seed('bank-001'), s.seed('bank-002')];
      s.record(
        'ambiguous-batch',
        s.statement(reverse ? rows.reversed.toList() : rows),
      );
      s.restart();
    });
  }
  scenario('unconfirmed-deleted-identity-needs-review', (s) {
    s.record('original', s.statement([s.seed('bank-001')]));
    s.core.deleteTransaction(
      s.core.transactions.single.id,
      actorId: 'synthetic-user',
    );
    s.record('deleted');
    s.record('similar-new-provider', s.statement([s.seed('bank-002')]));
  });
  scenario('same-provider-different-source-scope', (s) {
    s.record(
      'connection-one',
      s.statement([s.seed('provider-same')], connectionId: 'connection-one'),
    );
    s.record(
      'connection-two',
      s.statement([s.seed('provider-same')], connectionId: 'connection-two'),
    );
  });
  scenario('manual-ids-remain-distinct', (s) {
    for (final id in ['existing-manual-001', 'existing-manual-002']) {
      s.record(
        id,
        s.core.ingest(
          ManualInputAdapter(ids: s.ids),
          ManualInput(
            entityId: parityAccount.entityId,
            receivedAt: parityNow,
            rawPayload: 'Synthetic manual input',
            transaction: s.seed(null, canonicalId: id),
          ),
        ),
      );
    }
    s.restart();
  });
  scenario('money-currencies-directions-and-types', (s) {
    for (final currency in ['RUB', 'USD', 'EUR', 'CNY']) {
      final account = SynoballAccount(
        id: 'account-$currency',
        entityId: parityAccount.entityId,
        name: 'Synthetic $currency',
        type: SynoballAccountType.savings,
        currency: currency,
        balance: Money(minorUnits: 1500025, currency: currency),
      );
      s.record(
        currency,
        s.statement(
          [
            s.seed(
              'expense-$currency',
              accountId: account.id,
              currency: currency,
              minor: 486122,
            ),
            s.seed(
              'income-$currency',
              accountId: account.id,
              currency: currency,
              minor: 1500025,
              direction: FinancialDirection.inflow,
            ),
            s.seed(
              'own-transfer-$currency',
              accountId: account.id,
              currency: currency,
              minor: 1500000,
              tags: ['sber-own-transfer', 'transfer'],
            ),
          ],
          account: account,
          web: true,
        ),
      );
    }
    s.restart();
  });
  return cases;
}

Map<String, dynamic> parityIdentityVectors() => {
  'source': sourceIdentity('parity-v1', [
    'existing-account-001',
    'operation-001',
    486122,
    'RUB',
  ]),
  'normalizedText': sourceIdentityText('  SYNTHETIC КОФЕ Ёж  '),
};
