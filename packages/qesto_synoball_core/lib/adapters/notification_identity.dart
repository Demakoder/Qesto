import 'dart:convert';

import '../core/models.dart';
import 'source_identity.dart';
import 'transaction_inputs.dart';

const notificationIdentityReviewTag = 'notification-identity:review';

/// The Android key identifies a notification slot, not a bank operation.
/// A new slot revision may be a second purchase, or just updated UI text.
/// Preserve both possibilities until the user resolves an ambiguous revision.
TransactionSeed notificationSeed({
  required TransactionSeed seed,
  required String entityId,
  required String packageName,
  required String notificationKey,
  required SynoballSourceType sourceType,
  required SynoballState history,
}) {
  final providerId = sourceIdentity('notification-v2', [
    entityId,
    seed.accountId,
    sourceType.name,
    packageName,
    notificationKey,
    seed.occurredAt.toUtc().microsecondsSinceEpoch,
    seed.amount.minorUnits,
    seed.amount.currency,
    seed.direction.name,
    sourceIdentityText(seed.merchant),
  ]);
  final records = {for (final r in history.ingestionRecords) r.id: r};
  final raw = {for (final r in history.rawPayloads) r.id: r};
  final targets = {for (final t in history.transactions) t.id: t};
  final aliases = <String>{};
  var reusedSlot = false;
  var pendingExact = false;
  var exactV2 = false;
  for (final previous in history.candidates) {
    if (previous.entityId != entityId || previous.accountId != seed.accountId) {
      continue;
    }
    final record = records[previous.ingestionRecordId];
    if (record == null || record.sourceType != sourceType) continue;
    Map<String, dynamic>? payload;
    try {
      final body = jsonDecode(raw[record.rawPayloadId]?.body ?? 'null');
      if (body is Map<String, dynamic>) payload = body;
    } on FormatException {
      // Legacy evidence with no readable origin must never become an alias.
    }
    if (payload?['packageName'] != packageName ||
        payload?['notificationKey'] != notificationKey) {
      if ((payload?['packageName'] == null ||
              payload?['notificationKey'] == null) &&
          previous.providerTransactionId == notificationKey) {
        reusedSlot = true;
      }
      continue;
    }
    reusedSlot = true;
    final sameObservation =
        previous.amount.minorUnits == seed.amount.minorUnits &&
        previous.amount.currency == seed.amount.currency &&
        previous.direction == seed.direction &&
        previous.occurredAt.isAtSameMomentAs(seed.occurredAt) &&
        sourceIdentityText(previous.merchantGuess) ==
            sourceIdentityText(seed.merchant);
    if (!sameObservation) continue;
    if (previous.status == CandidateStatus.pending) {
      pendingExact = true;
    }
    for (final evidence in history.evidence) {
      if (evidence.ingestionRecordId != previous.ingestionRecordId ||
          evidence.sourceType != sourceType ||
          evidence.providerTransactionId != previous.providerTransactionId) {
        continue;
      }
      final target = targets[evidence.transactionId];
      if (target == null ||
          target.entityId != entityId ||
          target.accountId != seed.accountId ||
          target.amount.currency != seed.amount.currency) {
        continue;
      }
      aliases.add(target.id);
      if (previous.providerTransactionId == providerId) exactV2 = true;
    }
  }
  final ambiguous =
      aliases.length > 1 || (aliases.isEmpty && (reusedSlot || pendingExact));
  return TransactionSeed(
    canonicalId: aliases.length == 1 && !exactV2
        ? aliases.single
        : seed.canonicalId,
    accountId: seed.accountId,
    amount: seed.amount,
    direction: seed.direction,
    occurredAt: seed.occurredAt,
    description: seed.description,
    merchant: seed.merchant,
    providerCategory: seed.providerCategory,
    category: seed.category,
    userCategoryOverride: seed.userCategoryOverride,
    subcategoryId: seed.subcategoryId,
    providerTransactionId: providerId,
    receiptId: seed.receiptId,
    transferDirection: seed.transferDirection,
    tags: [
      ...seed.tags,
      sourceType == SynoballSourceType.smsNotification
          ? 'sms-notification'
          : 'android-notification',
      if (ambiguous) notificationIdentityReviewTag,
    ],
    confidence: seed.confidence,
    requiresConfirmation: seed.requiresConfirmation || ambiguous,
  );
}
