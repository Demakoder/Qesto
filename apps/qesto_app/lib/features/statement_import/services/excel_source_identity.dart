import '../../../synoball/adapters/source_identity.dart';
import '../../../synoball/core/models.dart';
import '../domain/bank_statement_models.dart';

String excelObservationKey({
  required DateTime date,
  required int amountMinor,
  required String currency,
  required bool incoming,
  required String merchant,
  required String description,
  required bool aggregate,
  required bool capital,
}) => sourceIdentity('excel-observation-v2', [
  // Excel contains calendar dates, not a device-local capture timestamp.
  date.year, date.month, date.day, date.hour, date.minute, date.second,
  amountMinor.abs(), currency.toUpperCase(), incoming,
  sourceIdentityText(merchant),
  sourceIdentityText(description.replaceAll(' · агрегировано за период', '')),
  aggregate, capital,
]);

class ExcelRowIdentity {
  const ExcelRowIdentity({
    required this.canonicalId,
    this.existing = false,
    this.reviewReason,
  });
  final String canonicalId;
  final bool existing;
  final String? reviewReason;
}

/// Explicit workbook/account scope + exact source observations. Never use a
/// user's edited canonical amount/title to guess aliases for legacy rows.
Map<String, ExcelRowIdentity> resolveExcelRows({
  required List<ParsedStatementTransaction> rows,
  required String accountId,
  required String currency,
  required SynoballState history,
}) {
  final targets = {for (final t in history.transactions) t.id: t};
  final records = {for (final r in history.ingestionRecords) r.id: r};
  final evidence = <String, Set<String>>{};
  for (final e in history.evidence) {
    if (e.sourceType != SynoballSourceType.statement) continue;
    final target = targets[e.transactionId];
    if (target == null || target.accountId != accountId) continue;
    (evidence['${e.ingestionRecordId}|${e.providerTransactionId}'] ??= {}).add(
      target.id,
    );
  }
  final byObservation = <String, Set<String>>{};
  final byProvider = <String, Set<String>>{};
  final byCell = <String, Set<String>>{};
  for (final c in history.candidates) {
    if (c.accountId != accountId ||
        !c.tags.contains('excel-import') ||
        records[c.ingestionRecordId]?.sourceType !=
            SynoballSourceType.statement) {
      continue;
    }
    final ids = evidence['${c.ingestionRecordId}|${c.providerTransactionId}'];
    if (ids == null || ids.isEmpty) continue;
    final key = excelObservationKey(
      date: c.occurredAt,
      amountMinor: c.amount.minorUnits,
      currency: c.amount.currency,
      incoming: c.direction == FinancialDirection.inflow,
      merchant: c.merchantGuess ?? '',
      description: c.rawDescription,
      aggregate: c.tags.contains('excel-period-aggregate'),
      capital: c.tags.contains('excel-capital-allocation'),
    );
    (byObservation[key] ??= {}).addAll(ids);
    if (c.providerTransactionId != null) {
      (byProvider[c.providerTransactionId!] ??= {}).addAll(ids);
    }
    for (final tag in c.tags.where((tag) => tag.startsWith('excel-cell:'))) {
      (byCell[tag.substring('excel-cell:'.length)] ??= {}).addAll(ids);
    }
  }
  final counts = <String, int>{};
  for (final row in rows) {
    final key = row.excelObservationKey ?? row.id;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final result = <String, ExcelRowIdentity>{};
  for (final row in rows) {
    final observation = row.excelObservationKey ?? row.id;
    final exact = byProvider[row.id] ?? const <String>{};
    final similar = byObservation[observation] ?? const <String>{};
    var canonicalId = sourceIdentity('excel-transaction-v2', [
      accountId,
      row.id,
    ]);
    String? reason;
    var existing = false;
    if (row.currency != currency) {
      reason = 'Валюта строки отличается от валюты выбранного источника';
    } else if (exact.length > 1 ||
        (similar.length > 1 && exact.isEmpty) ||
        (similar.isNotEmpty &&
            counts[observation] != similar.length &&
            (similar.length > 1 || counts[observation]! > 1))) {
      reason =
          'Неоднозначные одинаковые строки: изменилось их число или нет устойчивого ID';
    } else if (exact.length == 1) {
      canonicalId = exact.single;
      existing = true;
    } else if (similar.length == 1) {
      canonicalId = similar.single;
      existing = true;
    } else if (row.excelLegacyId != null &&
        (byProvider[row.excelLegacyId]?.isNotEmpty == true ||
            byCell[row.excelLegacyId]?.isNotEmpty == true)) {
      reason =
          'В прежней ячейке другая операция. Автоматическая замена отключена';
    }
    result[row.id] = ExcelRowIdentity(
      canonicalId: canonicalId,
      existing: existing,
      reviewReason: reason,
    );
  }
  return result;
}
