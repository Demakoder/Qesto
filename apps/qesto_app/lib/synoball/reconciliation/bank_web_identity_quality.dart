import '../core/models.dart';

/// Review signal only. Equal economic facts never authorize a merge. Restrict
/// this check to legacy/scoped bank-web identity generations and account gaps.
List<Set<String>> bankWebIdentityAmbiguities(
  SynoballState state,
  String entityId,
) {
  final accounts = {for (final a in state.accounts) a.id: a};
  final records = {for (final r in state.ingestionRecords) r.id: r};
  final evidence = <String, List<SourceEvidence>>{};
  for (final e in state.evidence) {
    evidence.putIfAbsent(e.transactionId, () => []).add(e);
  }
  final buckets = <Object, List<CanonicalTransaction>>{};
  for (final t in state.transactions) {
    if (t.entityId != entityId ||
        t.status != CanonicalTransactionStatus.posted ||
        !t.tags.contains('sber-live')) {
      continue;
    }
    final sources = evidence[t.id] ?? const [];
    if (sources.isEmpty ||
        sources.any((e) => e.sourceType != SynoballSourceType.bankWeb)) {
      continue;
    }
    final scopes = sources.map((e) {
      final r = records[e.ingestionRecordId];
      return (
        r?.connectionId ?? accounts[t.accountId]?.connectionId,
        r?.institutionId ?? accounts[t.accountId]?.institutionId,
      );
    }).toSet();
    if (scopes.length != 1 ||
        scopes.single.$1 == null ||
        scopes.single.$2 == null) {
      continue;
    }
    final key = (
      scopes.single,
      t.occurredAt,
      t.amount.minorUnits,
      t.amount.currency,
      t.direction,
      t.rawDescription,
    );
    buckets.putIfAbsent(key, () => []).add(t);
  }
  return [
    for (final group in buckets.values)
      if (group.any(
            (t) =>
                !t.tags.contains('sber-identity:v2') &&
                accounts[t.accountId]?.isVirtual == false,
          ) &&
          group.any(
            (t) =>
                t.tags.contains('sber-identity:v2') &&
                accounts[t.accountId]?.isVirtual == true,
          ))
        group.map((t) => t.id).toSet(),
  ];
}
