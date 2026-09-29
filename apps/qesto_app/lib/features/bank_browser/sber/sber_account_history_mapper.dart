import 'sber_connector_models.dart';

/// A filtered history is evidence of product ownership only for the exact bank
/// operation, not for every payment with the same title/amount.
class SberAccountHistoryMapper {
  static String? key(SberTransactionFact value) =>
      value.sourceId.isEmpty || value.sourceId == value.fingerprint
      ? null
      : '${value.sourceId}|${value.date.toIso8601String()}|${value.amountMinor}|'
            '${value.currency}|${value.isIncome}';

  final _owners = <String, Set<String>>{};

  void observe(String canonicalAccount, Iterable<SberTransactionFact> scoped) {
    for (final row in scoped) {
      final identity = key(row);
      if (identity == null || row.accountId.isEmpty) continue;
      _owners.putIfAbsent(identity, () => {}).add(canonicalAccount);
    }
  }

  List<SberTransactionFact> apply(Iterable<SberTransactionFact> global) => [
    for (final row in global) _apply(row),
  ];

  SberTransactionFact _apply(SberTransactionFact row) {
    final owners = _owners[key(row)];
    if (row.accountId.isNotEmpty || owners == null || owners.length != 1) {
      return row;
    }
    return row.withAccount(owners.single);
  }

  int get conflicts =>
      _owners.values.where((owners) => owners.length > 1).length;
}
