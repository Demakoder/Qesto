import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/ai_export/data/ai_export_ids.dart';
import 'package:qesto/features/ai_export/data/ai_export_snapshot.dart';
import 'package:qesto/features/ai_export/domain/ai_export_mapper.dart';
import 'package:qesto/features/ai_export/domain/ai_export_models.dart';
import 'package:qesto/features/ai_export/domain/ai_export_v2.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/mocks/fixtures/empty_user_financial_data.dart';
import 'package:qesto/synoball/core/models.dart';
import 'ai_export_test.dart' as f;

const entity = f.privateEntity;
final now = DateTime.utc(2026, 9, 24, 12);
const bank = SynoballAccount(
  id: f.privateAccount,
  entityId: entity,
  name: 'PRIVATE_ACCOUNT 1234',
  type: SynoballAccountType.checking,
  currency: 'RUB',
  balance: Money(minorUnits: 0, currency: 'RUB'),
  institutionId: 'private-bank',
);
const virtual = SynoballAccount(
  id: 'sber-unassigned-private',
  entityId: entity,
  name: 'PRIVATE_UNKNOWN остаток неизвестен',
  type: SynoballAccountType.cash,
  currency: 'RUB',
  balance: Money(minorUnits: 0, currency: 'RUB'),
  isVirtual: true,
);

SourceEvidence evidence(
  String id,
  String transaction,
  SynoballSourceType type, {
  String? provider,
  String? record,
}) => SourceEvidence(
  id: id,
  transactionId: transaction,
  sourceType: type,
  ingestionRecordId: record ?? 'private-record-$id',
  confidence: 0.94,
  trust: SourceTrustLevel.bankStatement,
  observedAt: now,
  providerTransactionId: provider ?? 'PRIVATE_PROVIDER_$id',
);

IngestionRecord record(
  SourceEvidence e, {
  String institution = 'private-bank',
}) => IngestionRecord(
  id: e.ingestionRecordId,
  entityId: entity,
  sourceType: e.sourceType,
  receivedAt: now,
  rawPayloadId: 'PRIVATE_RAW',
  status: IngestionStatus.completed,
  adapterId: 'private-adapter',
  adapterVersion: '1',
  institutionId: institution,
);

BudgetController controller(
  List<CanonicalTransaction> rows, {
  List<SynoballAccount> accounts = const [bank],
  List<SourceEvidence> sources = const [],
  List<IngestionRecord>? records,
  List<SynoballEvent> events = const [],
  List<InvestmentAccount> investments = const [],
  List<DebtAccount> debts = const [],
}) => BudgetController(
  configuration: budgetConfiguration,
  financialData: emptyUserFinancialData.copyWith(
    user: const QestoUser(
      id: 'private-user',
      name: 'PRIVATE_USER',
      defaultCurrency: 'RUB',
    ),
    referenceDate: DateTime(2026, 9, 24),
    investmentAccounts: investments,
    debts: debts,
    synoballState: SynoballState(
      accounts: accounts,
      transactions: rows,
      evidence: sources,
      ingestionRecords: records ?? sources.map(record).toList(),
      events: events,
    ),
  ),
);

Future<Map<String, dynamic>> exported(
  BudgetController c, {
  AiExportVersion version = AiExportVersion.v2,
  AiExportIdProvider? ids,
  DateTime? start,
}) async {
  final snapshot = captureAiExportSnapshot(c, now: now);
  final selection = AiExportSelection(
    snapshot,
    AiExportSettings(
      period: StatisticsDateRange(
        start ?? DateTime(2026, 9, 1),
        DateTime(2026, 9, 24),
      ),
      version: version,
      detailLevel: AiExportDetailLevel.diagnostic,
    ),
  );
  ids ??= await AiExportIdStore(
    secureStore: f.MemoryExportSecrets(),
  ).forProfile(entity);
  final map = version == AiExportVersion.v1
      ? (await const AIExportV1Builder().build(
          selection,
          ids,
          generatedAt: now,
        )).toJson()
      : (await const AIExportV2Builder().build(
          selection,
          ids,
          generatedAt: now,
        )).toJson();
  final decoded = jsonDecode(jsonEncode(map)) as Map<String, dynamic>;
  expect(decoded['transactions'], hasLength(selection.transactions.length));
  final accIds = (decoded['accounts'] as List).map((a) => a['id']).toSet();
  final catIds = (decoded['categories'] as List).map((a) => a['id']).toSet();
  final txnIds = (decoded['transactions'] as List).map((a) => a['id']).toSet();
  for (final t in decoded['transactions']) {
    expect(t['accountId'] == null || accIds.contains(t['accountId']), isTrue);
    expect(t['categoryId'] == null || catIds.contains(t['categoryId']), isTrue);
    if (t['refund'] != null) {
      expect(
        t['refund']['originalTransactionId'] == null ||
            txnIds.contains(t['refund']['originalTransactionId']),
        isTrue,
      );
    }
  }
  return decoded;
}

void main() {
  BudgetController make(
    List<CanonicalTransaction> rows, {
    List<SynoballAccount> accounts = const [bank],
    List<SourceEvidence> sources = const [],
    List<IngestionRecord>? records,
    List<SynoballEvent> events = const [],
    List<InvestmentAccount> investments = const [],
    List<DebtAccount> debts = const [],
  }) {
    final c = controller(
      rows,
      accounts: accounts,
      sources: sources,
      records: records,
      events: events,
      investments: investments,
      debts: debts,
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'v2 real zero is known, unknown virtual zero is null and not cash',
    () async {
      final data = await exported(make([], accounts: [bank, virtual]));
      expect(data['schemaVersion'], 'qesto.ai-export.v2');
      final accounts = data['accounts'] as List;
      final real = accounts.firstWhere((a) => a['isVirtual'] == false);
      final unknown = accounts.firstWhere((a) => a['isVirtual'] == true);
      expect(real['latestStoredBalance']['value'], '0.00');
      expect(real['latestStoredBalance']['status'], 'known');
      expect(unknown['latestStoredBalance']['value'], isNull);
      expect(unknown['latestStoredBalance']['capturedAt'], isNull);
      expect(unknown['resolutionStatus'], 'unresolved');
      expect(unknown['type'], 'bank_account');
      expect(data['dataQuality']['balancesCompleteness'], 'partial');
    },
  );

  test(
    'a custom real account name is not evidence of an unknown balance',
    () async {
      const a = SynoballAccount(
        id: 'real',
        entityId: entity,
        name: 'Неизвестные расходы',
        type: SynoballAccountType.cash,
        currency: 'RUB',
        balance: Money(minorUnits: 0, currency: 'RUB'),
      );
      final data = await exported(make([], accounts: [a]));
      expect(data['accounts'][0]['latestStoredBalance']['status'], 'known');
      expect(data['accounts'][0]['resolutionStatus'], 'resolved');
      expect(data['accounts'][0]['type'], 'cash');
    },
  );

  test(
    'stale investment balance and no fabricated portfolio/cost basis',
    () async {
      const account = SynoballAccount(
        id: 'broker',
        entityId: entity,
        name: 'PRIVATE_BROKER',
        type: SynoballAccountType.brokerage,
        currency: 'RUB',
        balance: Money(minorUnits: 35400, currency: 'RUB'),
      );
      final c = make(
        [],
        accounts: [account],
        investments: [
          InvestmentAccount(
            id: 'investment',
            userId: 'private-user',
            linkedAccountId: 'broker',
            name: 'PRIVATE_BROKER',
            type: InvestmentAccountType.brokerage,
            currency: 'RUB',
            currentBalance: 354,
            status: InvestmentAccountStatus.active,
            source: InvestmentDataSource.api,
            createdAt: DateTime(2026),
            updatedAt: now,
            lastBalanceUpdateAt: DateTime.utc(2026, 9, 1),
          ),
        ],
      );
      final a = (await exported(c))['accounts'][0];
      expect(a['type'], 'brokerage');
      expect(a['balanceNature'], 'asset');
      expect(a['latestStoredBalance']['status'], 'stale');
      expect(a['brokerage'], {
        'portfolioValue': null,
        'cashBalance': null,
        'costBasis': null,
      });
    },
  );

  test('loan liability and explicit principal/payment only', () async {
    const account = SynoballAccount(
      id: 'loan',
      entityId: entity,
      name: 'PRIVATE_LOAN',
      type: SynoballAccountType.loan,
      currency: 'RUB',
      balance: Money(minorUnits: 230000, currency: 'RUB'),
    );
    final data = await exported(
      make(
        [],
        accounts: [account],
        debts: [
          DebtAccount(
            id: 'debt',
            userId: 'private-user',
            name: 'PRIVATE_DEBT',
            type: DebtType.personalLoan,
            currency: 'RUB',
            currentBalance: 2300,
            currentPrincipal: 2000,
            status: DebtStatus.active,
            source: DebtSource.bank,
            dataQuality: DebtDataQuality.verified,
            confidence: 1,
            createdAt: now,
            updatedAt: now,
            linkedAccountId: 'loan',
          ),
        ],
      ),
    );
    expect(data['accounts'][0]['balanceNature'], 'liability');
    expect(
      data['accounts'][0]['loan']['outstandingPrincipal']['value'],
      '2000.00',
    );
    expect(data['accounts'][0]['loan']['nextPayment'], isNull);
  });

  for (final kind in ['expense', 'income', 'internal']) {
    test('financial semantics $kind', () async {
      final t = f.exportFixtureTransaction(
        't',
        direction: kind == 'income'
            ? FinancialDirection.inflow
            : FinancialDirection.outflow,
        tags: kind == 'internal' ? ['qesto-internal-transfer'] : [],
        transferDirection: kind == 'internal' ? 'outgoing' : null,
      );
      final data = await exported(make([t]));
      final row = data['transactions'][0];
      expect(
        row['cashFlowTreatment'],
        kind == 'income'
            ? 'externalInflow'
            : kind == 'internal'
            ? 'internalTransfer'
            : 'externalOutflow',
      );
      expect(row['amount']['value'], '1200.25');
      if (kind == 'internal') {
        expect(row['transfer']['matchingStatus'], 'unmatched');
      }
    });
  }

  test(
    'linked transfer sides use one private ID and real counterparty accounts',
    () async {
      const account2 = SynoballAccount(
        id: 'second',
        entityId: entity,
        name: 'PRIVATE_SECOND',
        type: SynoballAccountType.savings,
        currency: 'RUB',
        balance: Money(minorUnits: 0, currency: 'RUB'),
      );
      final out = f.exportFixtureTransaction(
        'out',
        tags: ['qesto-internal-transfer'],
        transferDirection: 'outgoing',
      );
      final inc = f.exportFixtureTransaction(
        'in',
        account: 'second',
        direction: FinancialDirection.inflow,
        tags: ['qesto-internal-transfer'],
        transferDirection: 'incoming',
      );
      final data = await exported(
        make(
          [out, inc],
          accounts: [bank, account2],
          events: [
            SynoballEvent(
              id: 'PRIVATE_LINK',
              type: 'transaction.transfer-linked',
              entityId: entity,
              occurredAt: now,
              payload: {
                'outgoingTransactionId': 'out',
                'incomingTransactionId': 'in',
              },
            ),
          ],
        ),
      );
      final rows = data['transactions'] as List;
      expect(rows[0]['transfer']['transferId'], matches('^trf_[a-f0-9]{64}\$'));
      expect(
        rows[0]['transfer']['transferId'],
        rows[1]['transfer']['transferId'],
      );
      expect(
        rows[0]['transfer']['counterpartyAccountId'],
        rows[1]['accountId'],
      );
    },
  );

  for (final matched in [true, false]) {
    test(
      'refund ${matched ? "matched inherits category" : "unmatched remains refund"}',
      () async {
        final original = f.exportFixtureTransaction(
          'purchase',
          date: DateTime(2026, 9, 20),
        );
        final refund = f
            .exportFixtureTransaction(
              'refund',
              direction: FinancialDirection.inflow,
              category: 'other',
              tags: ['refund'],
            )
            .copyWith(merchantName: 'OTHER_MERCHANT');
        final data = await exported(
          make(
            [if (matched) original, refund],
            events: [
              if (matched)
                SynoballEvent(
                  id: 'PRIVATE_REFUND_LINK',
                  type: 'transaction.refund-linked',
                  entityId: entity,
                  subjectId: 'refund',
                  occurredAt: now,
                  payload: {'originalTransactionId': 'purchase'},
                ),
            ],
          ),
        );
        final r = (data['transactions'] as List).firstWhere(
          (t) => t['type'] == 'refund',
        );
        expect(r['cashFlowTreatment'], 'refund');
        expect(
          r['refund']['matchingStatus'],
          matched ? 'matched' : 'unmatched',
        );
        if (matched) {
          expect(r['categoryId'], data['transactions'][0]['categoryId']);
        }
      },
    );
  }

  test(
    'refund target outside period does not create a dangling reference',
    () async {
      final data = await exported(
        make(
          [
            f.exportFixtureTransaction('original', date: DateTime(2026, 8, 20)),
            f.exportFixtureTransaction(
              'refund',
              direction: FinancialDirection.inflow,
              tags: ['refund'],
            ),
          ],
          events: [
            SynoballEvent(
              id: 'link',
              type: 'transaction.refund-linked',
              entityId: entity,
              subjectId: 'refund',
              occurredAt: now,
              payload: {'originalTransactionId': 'original'},
            ),
          ],
        ),
      );
      expect(data['transactions'], hasLength(1));
      expect(
        data['transactions'][0]['refund']['originalTransactionId'],
        isNull,
      );
      expect(
        data['transactions'][0]['refund']['originalTransactionScope'],
        'outside_period',
      );
    },
  );

  test(
    'one canonical purchase from statement + notification exports once',
    () async {
      final sources = [
        evidence('s', 'purchase', SynoballSourceType.statement),
        evidence('n', 'purchase', SynoballSourceType.androidNotification),
      ];
      final c = make([
        f.exportFixtureTransaction('purchase'),
      ], sources: sources);
      final before = jsonEncode(c.synoballState.toJson());
      final data = await exported(c);
      expect(data['transactions'], hasLength(1));
      expect(data['transactions'][0]['provenance'], {
        'sourceTypes': ['android_notification', 'bank_statement'],
        'evidenceCount': 2,
        'merged': true,
      });
      expect(data['transactions'][0]['deduplication']['status'], 'merged');
      expect(jsonEncode(c.synoballState.toJson()), before);
      expect(jsonEncode(data), isNot(contains('PRIVATE_')));
    },
  );

  test('two real identical purchases in one source stay separate', () async {
    final data = await exported(
      make(
        [f.exportFixtureTransaction('one'), f.exportFixtureTransaction('two')],
        sources: [
          evidence('1', 'one', SynoballSourceType.statement),
          evidence('2', 'two', SynoballSourceType.statement),
        ],
      ),
    );
    expect(data['transactions'], hasLength(2));
    expect(data['dataQuality']['hasPossibleDuplicates'], isFalse);
  });

  test(
    'cross-source similarity is only a possible duplicate, not a merge',
    () async {
      final data = await exported(
        make(
          [
            f.exportFixtureTransaction('one'),
            f.exportFixtureTransaction('two'),
          ],
          sources: [
            evidence('1', 'one', SynoballSourceType.statement),
            evidence('2', 'two', SynoballSourceType.androidNotification),
          ],
        ),
      );
      expect(data['transactions'], hasLength(2));
      expect(data['dataQuality']['hasPossibleDuplicates'], isTrue);
      final rows = data['transactions'] as List;
      expect(rows[0]['deduplication']['status'], 'possible_duplicate');
      expect(
        rows[0]['deduplication']['groupId'],
        rows[1]['deduplication']['groupId'],
      );
    },
  );

  test(
    'exact scoped identity resolves virtual duplicate to a real account; v1 stays available',
    () async {
      final c = make(
        [
          f.exportFixtureTransaction('a-old', account: virtual.id),
          f.exportFixtureTransaction('b-real'),
        ],
        accounts: [bank, virtual],
        sources: [
          evidence(
            '1',
            'a-old',
            SynoballSourceType.bankWeb,
            provider: 'PRIVATE_EXACT',
          ),
          evidence(
            '2',
            'b-real',
            SynoballSourceType.bankWeb,
            provider: 'PRIVATE_EXACT',
          ),
        ],
      );
      final ids = await AiExportIdStore(
        secureStore: f.MemoryExportSecrets(),
      ).forProfile(entity);
      final data = await exported(c, ids: ids);
      expect(data['transactions'], hasLength(1));
      expect(
        data['transactions'][0]['id'],
        await ids.id('transaction', 'a-old'),
      );
      expect(
        data['transactions'][0]['accountId'],
        await ids.id('account', bank.id),
      );
      expect(data['transactions'][0]['accountResolution'], 'resolved');
      final legacy = await exported(c, ids: ids, version: AiExportVersion.v1);
      expect(legacy['schemaVersion'], 'qesto.ai-export.v1');
      expect(legacy['transactions'], hasLength(2));
      expect(legacy['transactions'][0], isNot(contains('provenance')));
    },
  );

  test('same provider ID from different banks cannot merge', () async {
    final sources = [
      evidence('1', 'one', SynoballSourceType.bankWeb, provider: 'shared'),
      evidence('2', 'two', SynoballSourceType.bankWeb, provider: 'shared'),
    ];
    final data = await exported(
      make(
        [f.exportFixtureTransaction('one'), f.exportFixtureTransaction('two')],
        sources: sources,
        records: [
          record(sources[0]),
          record(sources[1], institution: 'other-bank'),
        ],
      ),
    );
    expect(data['transactions'], hasLength(2));
  });

  test(
    'user category correction is authoritative and explicitly marked',
    () async {
      final t = f
          .exportFixtureTransaction('t', tags: ['user-field:category'])
          .copyWith(userCategoryOverride: 'transport', categoryConfidence: 1);
      final data = await exported(make([t]));
      expect(data['transactions'][0]['userEdited'], isTrue);
      expect(data['transactions'][0]['userEditedFields'], ['categoryId']);
      expect(data['transactions'][0]['categoryAssignment']['source'], 'user');
      expect(data['categories'][0]['origin'], 'system');
    },
  );

  test(
    'date-only has no fictitious midnight; explicit real midnight retained',
    () async {
      final data = await exported(
        make([
          f.exportFixtureTransaction('date', date: DateTime(2026, 9, 20)),
          f.exportFixtureTransaction(
            'time',
            date: DateTime.utc(2026, 9, 21),
            tags: ['time-precision:datetime'],
          ),
        ]),
      );
      expect(data['transactions'][0]['occurredAt'], isNull);
      expect(data['transactions'][0]['occurredDate'], '2026-09-20');
      expect(data['transactions'][0]['timePrecision'], 'date');
      expect(data['transactions'][1]['occurredAt'], '2026-09-21T00:00:00.000Z');
      expect(data['transactions'][1]['timePrecision'], 'datetime');
    },
  );

  test(
    'observed statement time exact; notification receive time approximate',
    () async {
      final data = await exported(
        make(
          [f.exportFixtureTransaction('time')],
          sources: [evidence('1', 'time', SynoballSourceType.statement)],
        ),
      );
      expect(data['transactions'][0]['timePrecision'], 'datetime');
      final approximate = await exported(
        make(
          [f.exportFixtureTransaction('time')],
          sources: [
            evidence('1', 'time', SynoballSourceType.androidNotification),
          ],
        ),
      );
      expect(approximate['transactions'][0]['timePrecision'], 'approximate');
    },
  );

  for (final verified in [false, true]) {
    test(
      'history ${verified ? "verified full range" : "not verified by import alone"}',
      () async {
        final data = await exported(
          make(
            [f.exportFixtureTransaction('t')],
            events: [
              if (verified)
                SynoballEvent(
                  id: 'verification',
                  type: 'history.verified',
                  entityId: entity,
                  subjectId: bank.id,
                  occurredAt: now,
                  payload: {
                    'status': 'complete',
                    'startDate': '2026-09-01',
                    'endDateInclusive': '2026-09-24',
                  },
                ),
            ],
          ),
        );
        expect(
          data['dataQuality']['historyCompleteness'],
          verified ? 'complete' : 'not_verified',
        );
      },
    );
  }

  test(
    'no fabricated confidence when no evidence, IDs stable across versions',
    () async {
      final c = make([f.exportFixtureTransaction('t')]);
      final ids = await AiExportIdStore(
        secureStore: f.MemoryExportSecrets(),
      ).forProfile(entity);
      final v1 = await exported(c, ids: ids, version: AiExportVersion.v1);
      final v2 = await exported(c, ids: ids);
      expect(v1['transactions'][0]['id'], v2['transactions'][0]['id']);
      expect(v2['transactions'][0]['confidence'], isEmpty);
      expect(v2['transactions'][0]['deduplication']['confidence'], isNull);
      expect(v2['transactions'][0]['deduplication']['status'], 'unresolved');
    },
  );

  test('possible duplicate preserves low source confidence', () async {
    final weak = SourceEvidence(
      id: 'weak',
      transactionId: 'two',
      sourceType: SynoballSourceType.androidNotification,
      ingestionRecordId: 'weak-record',
      confidence: 0.68,
      trust: SourceTrustLevel.androidNotification,
      observedAt: now,
      providerTransactionId: 'weak-provider',
    );
    final data = await exported(
      make(
        [f.exportFixtureTransaction('one'), f.exportFixtureTransaction('two')],
        sources: [evidence('1', 'one', SynoballSourceType.statement), weak],
      ),
    );
    expect(data['transactions'], hasLength(2));
    expect(data['transactions'][0]['deduplication']['confidence'], 0.68);
  });

  test(
    'virtual bridge cannot collapse operations on two different real accounts',
    () async {
      const second = SynoballAccount(
        id: 'second',
        entityId: entity,
        name: 'Second',
        type: SynoballAccountType.checking,
        currency: 'RUB',
        balance: Money(minorUnits: 0, currency: 'RUB'),
      );
      final data = await exported(
        make(
          [
            f.exportFixtureTransaction('a-real'),
            f.exportFixtureTransaction('b-virtual', account: virtual.id),
            f.exportFixtureTransaction('c-real', account: second.id),
          ],
          accounts: [bank, virtual, second],
          sources: [
            evidence('1', 'a-real', SynoballSourceType.bankWeb, provider: 'p1'),
            evidence(
              '2',
              'b-virtual',
              SynoballSourceType.bankWeb,
              provider: 'p1',
            ),
            evidence(
              '3',
              'b-virtual',
              SynoballSourceType.bankWeb,
              provider: 'p2',
            ),
            evidence('4', 'c-real', SynoballSourceType.bankWeb, provider: 'p2'),
          ],
        ),
      );
      expect(data['transactions'], hasLength(3));
      expect(data['dataQuality']['hasPossibleDuplicates'], isTrue);
    },
  );

  test('snapshot metadata does not retain canonical raw descriptions', () {
    final snapshot = captureAiExportSnapshot(
      make([f.exportFixtureTransaction('t')]),
    );
    expect(snapshot.canonical!.transactions, isEmpty);
    expect(() => snapshot.canonical!.facts.clear(), throwsUnsupportedError);
  });

  test(
    'conflicting user edits on exact identity stay available for review',
    () async {
      final data = await exported(
        make(
          [
            f
                .exportFixtureTransaction('one', tags: ['user-field:category'])
                .copyWith(userCategoryOverride: 'transport'),
            f
                .exportFixtureTransaction('two', tags: ['user-field:category'])
                .copyWith(userCategoryOverride: 'groceries'),
          ],
          sources: [
            evidence('1', 'one', SynoballSourceType.bankWeb, provider: 'same'),
            evidence('2', 'two', SynoballSourceType.bankWeb, provider: 'same'),
          ],
        ),
      );
      expect(data['transactions'], hasLength(2));
      expect(data['dataQuality']['hasPossibleDuplicates'], isTrue);
    },
  );

  test(
    'verification is scoped to full range and invalidated by later mutation',
    () async {
      final event = SynoballEvent(
        id: 'verified',
        type: 'history.verified',
        entityId: entity,
        subjectId: bank.id,
        occurredAt: DateTime(2026, 9, 20),
        payload: {
          'status': 'complete',
          'startDate': '2026-09-01',
          'endDateInclusive': '2026-09-24',
        },
      );
      final data = await exported(
        make(
          [
            f
                .exportFixtureTransaction('t')
                .copyWith(updatedAt: DateTime(2026, 9, 22)),
          ],
          events: [event],
        ),
      );
      expect(data['dataQuality']['historyCompleteness'], 'not_verified');
      final wider = await exported(
        make([], events: [event]),
        start: DateTime(2026, 8, 1),
      );
      expect(wider['dataQuality']['historyCompleteness'], 'not_verified');
    },
  );
}
