import 'dart:convert';
import 'dart:io';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/synoball/adapters/qesto_legacy_bridge.dart';
import 'package:qesto/synoball/analytics/qesto_read_model.dart';
import 'package:qesto/features/transaction_import/services/sber_transaction_projection.dart';

const syntheticUser = 'synthetic-4a-user';

class SyntheticBookkeeping {
  const SyntheticBookkeeping(this.time);
  final DateTime time;
  DateTime now() => time;
}

class SyntheticIds extends SynoballIdFactory {
  SyntheticIds(this.seed);
  final String seed;
  int _n = 0;
  @override
  String next(String prefix) => '$prefix-synthetic-$seed-${++_n}';
}

UserFinancialData syntheticFixture({
  int count = 3,
  String fixturePath =
      '../storage_feasibility/test/fixtures/container_profile_v7.json',
}) {
  const codec = UserFinancialDataCodec();
  final raw = File(fixturePath).readAsStringSync();
  final data = codec.decode(raw.replaceAll('demo-user', syntheticUser));
  final seeds = data.synoballState!.transactions;
  final canonical = [
    for (var i = 0; i < count; i++)
      CanonicalTransaction.fromJson({
        ...seeds[i % 3].toJson(),
        'id': 'container-tx-$i',
        'entityId': 'ent-$syntheticUser',
        'status': i == 2 ? 'deleted' : 'posted',
        'occurredAt': DateTime.utc(
          2026,
          9,
          1,
        ).add(Duration(days: i % 30, minutes: i)).toIso8601String(),
        'merchantName': i % 3 == 0 ? 'Synthetic Market' : 'Synthetic Income',
        'userCategoryOverride': i % 3 == 0 ? 'sport' : null,
        'synoballCategory': i % 3 == 0 ? 'sport' : 'business',
        'tags': [
          if (i % 3 == 0) 'user-field:category',
          'user-field:note',
          'user-label:qa',
          'sberbank',
          'sber-classification:v2',
        ],
      }),
  ];
  final classification = ClassificationSettings(
    customCategories: const [
      BudgetCategory(
        id: 'fitness-custom',
        name: 'Synthetic fitness',
        iconKey: 'sport',
        colorValue: 0xff7744aa,
      ),
    ],
    tags: const [
      UserTransactionTag(id: 'qa', name: 'QA', colorValue: 0xff336699),
    ],
    redirects: const {'sport': 'fitness-custom'},
    rules: [
      MerchantCategoryRule(
        id: 'synthetic-rule',
        entityId: 'ent-$syntheticUser',
        merchantKey: const EnrichmentEngine().merchantIdentity(canonical[1])!,
        merchantLabel: 'Synthetic Income',
        categoryId: 'fitness-custom',
        direction: canonical[1].direction,
      ),
    ],
  );
  final core = SynoballCore(
    initialState: SynoballState(
      entities: [
        const SynoballEntity(
          id: 'ent-$syntheticUser',
          type: SynoballEntityType.person,
          displayName: 'Synthetic user',
        ),
      ],
      accounts: [
        for (final a in data.accounts)
          const QestoLegacyBridge().accountFromQesto(a),
      ],
      rawPayloads: [
        RawPayload(
          id: 'synthetic-raw-4a',
          contentType: 'text/plain',
          body: 'Synthetic provenance',
          createdAt: DateTime.utc(2026, 10, 12),
        ),
      ],
      transactions: canonical,
    ),
    categoryPolicy: classification.policy,
  );
  final read = const QestoReadModelService().build(core.state);
  return data.copyWith(
    classification: classification,
    accounts: read.accounts,
    transactions: projectSberTransactions(
      read.transactions,
      classification.policy,
    ).toList(),
    synoballState: core.state,
  );
}

String encodeSynthetic({
  int count = 3,
  String fixturePath =
      '../storage_feasibility/test/fixtures/container_profile_v7.json',
}) => const UserFinancialDataCodec().encode(
  syntheticFixture(count: count, fixturePath: fixturePath),
);

// Runtime audit IDs/times differ by process. Financial facts and all existing
// records are compared intact; only newly generated bookkeeping is normalized.
Object? financialComparable(String json) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  final core = root['synoball'] as Map<String, dynamic>;
  for (final t in core['transactions'] as List) {
    t['updatedAt'] = 'bookkeeping-time';
  }
  for (final key in ['events', 'auditEntries']) {
    for (final e in core[key] as List) {
      e['id'] = 'bookkeeping-id';
      e['occurredAt'] = 'bookkeeping-time';
    }
  }
  return root;
}
