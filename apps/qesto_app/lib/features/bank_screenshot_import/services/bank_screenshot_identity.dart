import 'dart:convert';

import '../../../synoball/adapters/source_identity.dart';
import '../../../synoball/core/models.dart';
import '../domain/bank_screenshot_models.dart';

String screenshotFinancialKey(BankScreenshotCandidate row) =>
    sourceIdentity('shot-facts', [
      row.date.year,
      row.date.month,
      row.date.day,
      if (!row.dateOnly) ...[row.date.hour, row.date.minute, row.date.second],
      row.amountMinor.abs(),
      row.currency,
      row.kind.name,
      sourceIdentityText(row.merchant),
    ]);

BankScreenshotCandidate screenshotObservation(BankScreenshotCandidate row) =>
    row.copyWith(
      id: sourceIdentity('bank-shot-observation-v2', [
        row.imageHash,
        row.parserId,
        row.id,
        screenshotFinancialKey(row),
      ]),
      legacyProviderId: row.id,
    );

class ScreenshotIdentity {
  const ScreenshotIdentity({this.canonicalId, this.reviewReason});
  final String? canonicalId;
  final String? reviewReason;
}

ScreenshotIdentity resolveScreenshotIdentity(
  BankScreenshotCandidate row,
  SynoballState state,
) {
  if (row.legacyProviderId == null) return const ScreenshotIdentity();
  final records = {for (final r in state.ingestionRecords) r.id: r};
  final raw = {for (final r in state.rawPayloads) r.id: r};
  final targetIds = state.transactions
      .where((t) => t.accountId == row.accountId)
      .map((t) => t.id)
      .toSet();
  final aliases = <String>{};
  var possibleOverlap = false;
  for (final previous in state.candidates) {
    if (row.accountId != null && previous.accountId != row.accountId) continue;
    final record = records[previous.ingestionRecordId];
    if (record?.sourceType != SynoballSourceType.bankScreenshot) continue;
    final exactProvider = previous.providerTransactionId == row.id;
    final sameFacts =
        previous.amount.minorUnits == row.amountMinor.abs() &&
        previous.amount.currency == row.currency &&
        previous.occurredAt.year == row.date.year &&
        previous.occurredAt.month == row.date.month &&
        previous.occurredAt.day == row.date.day &&
        previous.direction ==
            (row.kind == BankScreenshotTransactionKind.income ||
                    row.kind == BankScreenshotTransactionKind.refund
                ? FinancialDirection.inflow
                : FinancialDirection.outflow) &&
        sourceIdentityText(previous.merchantGuess) ==
            sourceIdentityText(row.merchant);
    final imageTag = 'bank-screenshot-image:${row.imageHash}';
    var provenImage = previous.tags.contains(imageTag);
    var sameImageBatch = provenImage;
    if (!provenImage) {
      try {
        final payload = jsonDecode(raw[record?.rawPayloadId]?.body ?? 'null');
        final images = payload is Map ? payload['imageHashes'] : null;
        if (images is List) {
          sameImageBatch = images.contains(row.imageHash);
          provenImage = images.length == 1 && sameImageBatch;
        }
      } on FormatException {
        /* Missing legacy provenance is not proof. */
      }
    }
    if (sameFacts || sameImageBatch) possibleOverlap = true;
    // An old batch-level image list does not identify which image a row came from.
    final legacyExact =
        previous.providerTransactionId == row.legacyProviderId &&
        sameFacts &&
        provenImage;
    if (!exactProvider && !legacyExact) continue;
    for (final e in state.evidence) {
      if (e.ingestionRecordId == previous.ingestionRecordId &&
          e.providerTransactionId == previous.providerTransactionId &&
          targetIds.contains(e.transactionId)) {
        aliases.add(e.transactionId);
      }
    }
  }
  if (aliases.length == 1) {
    return ScreenshotIdentity(canonicalId: aliases.single);
  }
  return ScreenshotIdentity(
    reviewReason: possibleOverlap || aliases.length > 1
        ? 'Возможное пересечение с ранее загруженным скриншотом. '
              'Выберите строку только если это отдельная операция.'
        : null,
  );
}
