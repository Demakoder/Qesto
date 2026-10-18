import 'dart:convert';

import '../core/models.dart';
import '../ingestion/adapter.dart';
import 'transaction_inputs.dart';
import 'notification_identity.dart';

abstract class _TransactionAdapter<T extends AdapterInputBase>
    implements SynoballAdapter<T> {
  _TransactionAdapter({SynoballIdFactory? ids})
    : ids = ids ?? SynoballIdFactory();

  final SynoballIdFactory ids;

  SourceTrustLevel get trust;
  bool get defaultRequiresConfirmation;
  List<TransactionSeed> seeds(T input);

  @override
  List<SynoballCapability> getCapabilities() => const [
    SynoballCapability.transactions,
  ];

  @override
  AdapterHealth healthCheck() =>
      AdapterHealth(healthy: true, checkedAt: DateTime.now());

  @override
  void validate(T input) {
    if (input.entityId.trim().isEmpty) {
      throw const FormatException('entityId is required');
    }
    if (input.rawPayload.isEmpty) {
      throw const FormatException('raw payload must be retained');
    }
    for (final seed in seeds(input)) {
      if (seed.amount.minorUnits <= 0) {
        throw const FormatException('amount must be positive; use direction');
      }
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(seed.amount.currency)) {
        throw const FormatException('ISO-4217 currency is required');
      }
      if (seed.accountId.isEmpty) {
        throw const FormatException('accountId is required');
      }
    }
  }

  @override
  AdaptedIngestion parse(T input) {
    validate(input);
    return normalize(input);
  }

  @override
  AdaptedIngestion normalize(T input) {
    final rawId = ids.next('raw');
    final ingestionId = ids.next('ing');
    final batch = buildBatch(input);
    final record = IngestionRecord(
      id: ingestionId,
      entityId: input.entityId,
      sourceType: sourceType,
      connectionId: input.connectionId,
      institutionId: input.institutionId,
      receivedAt: input.receivedAt,
      rawPayloadId: rawId,
      status: IngestionStatus.normalized,
      adapterId: id,
      adapterVersion: version,
      importBatchId: batch?.id,
    );
    final candidates = seeds(input)
        .map(
          (seed) => TransactionCandidate(
            id: ids.next('cand'),
            ingestionRecordId: ingestionId,
            entityId: input.entityId,
            accountId: seed.accountId,
            amount: seed.amount,
            direction: seed.direction,
            occurredAt: seed.occurredAt,
            rawDescription: seed.description,
            normalizedDescription: _normalizeText(seed.description),
            merchantGuess: seed.merchant,
            providerCategory: seed.providerCategory,
            categoryGuess: seed.category,
            userCategoryOverride: seed.userCategoryOverride,
            subcategoryId: seed.subcategoryId,
            providerTransactionId: seed.providerTransactionId,
            receiptId: seed.receiptId,
            transferDirection: seed.transferDirection,
            confidence: seed.confidence.clamp(0, 1).toDouble(),
            sourceTrust: trust,
            status: CandidateStatus.pending,
            tags: seed.tags,
            requiresConfirmation:
                defaultRequiresConfirmation || seed.requiresConfirmation,
            canonicalId: seed.canonicalId,
          ),
        )
        .toList(growable: false);
    return AdaptedIngestion(
      rawPayload: RawPayload(
        id: rawId,
        contentType: contentType,
        body: input.rawPayload,
        createdAt: input.receivedAt,
        redacted: rawPayloadRedacted,
      ),
      record: record,
      candidates: candidates,
      receipts: buildReceipts(input, ingestionId),
      importBatch: batch,
      accounts: buildAccounts(input),
      institutions: buildInstitutions(input),
      connections: buildConnections(input),
      consents: buildConsents(input),
    );
  }

  String get contentType => 'application/json';
  bool get rawPayloadRedacted => false;
  ImportBatch? buildBatch(T input) => null;
  List<SynoballReceipt> buildReceipts(T input, String ingestionId) => const [];
  List<SynoballAccount> buildAccounts(T input) => const [];
  List<Institution> buildInstitutions(T input) => const [];
  List<SynoballConnection> buildConnections(T input) => const [];
  List<SynoballConsent> buildConsents(T input) => const [];
}

class ManualInputAdapter extends _TransactionAdapter<ManualInput> {
  ManualInputAdapter({super.ids});

  @override
  String get id => 'manual-input';
  @override
  String get version => '1.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.manual;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.userConfirmed;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  List<TransactionSeed> seeds(ManualInput input) => [input.transaction];
}

class VoiceInputAdapter extends _TransactionAdapter<VoiceInput> {
  VoiceInputAdapter({super.ids});

  @override
  String get id => 'voice-input';
  @override
  String get version => '1.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.manualVoice;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.modelInference;
  @override
  bool get defaultRequiresConfirmation => true;
  @override
  List<TransactionSeed> seeds(VoiceInput input) => [input.transaction];
  @override
  AdaptedIngestion normalize(VoiceInput input) {
    final adapted = super.normalize(input);
    return _withRawBody(
      adapted,
      jsonEncode({
        'transcript': input.transcript,
        'userCorrections': input.userCorrections,
      }),
    );
  }
}

class AndroidNotificationAdapter
    extends _TransactionAdapter<AndroidNotificationInput> {
  AndroidNotificationAdapter({super.ids, this.history = const SynoballState()});

  final SynoballState history;

  @override
  String get id => 'android-notification';
  @override
  String get version => '2.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.androidNotification;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.androidNotification;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  List<TransactionSeed> seeds(AndroidNotificationInput input) => [
    notificationSeed(
      seed: input.transaction,
      entityId: input.entityId,
      packageName: input.packageName,
      notificationKey: input.notificationKey,
      sourceType: sourceType,
      history: history,
    ),
  ];
  @override
  String get contentType => 'text/plain; charset=utf-8';

  @override
  AdaptedIngestion normalize(AndroidNotificationInput input) {
    final adapted = super.normalize(input);
    return _withRawBody(
      adapted,
      jsonEncode({
        'packageName': input.packageName,
        'notificationKey': input.notificationKey,
        'notification': input.rawPayload,
      }),
    );
  }
}

class SmsNotificationAdapter extends _TransactionAdapter<SmsNotificationInput> {
  SmsNotificationAdapter({super.ids, this.history = const SynoballState()});

  final SynoballState history;

  @override
  String get id => 'sms-notification';
  @override
  String get version => '2.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.smsNotification;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.androidNotification;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  List<TransactionSeed> seeds(SmsNotificationInput input) => [
    notificationSeed(
      seed: input.transaction,
      entityId: input.entityId,
      packageName: input.packageName,
      notificationKey: input.notificationKey,
      sourceType: sourceType,
      history: history,
    ),
  ];
  @override
  String get contentType => 'text/plain; charset=utf-8';

  @override
  AdaptedIngestion normalize(SmsNotificationInput input) {
    final adapted = super.normalize(input);
    return _withRawBody(
      adapted,
      jsonEncode({
        'packageName': input.packageName,
        'notificationKey': input.notificationKey,
        'sender': input.sender,
        'notification': input.rawPayload,
      }),
    );
  }
}

class BankScreenshotAdapter extends _TransactionAdapter<BankScreenshotInput> {
  BankScreenshotAdapter({super.ids});

  @override
  String get id => 'bank-screenshot';
  @override
  String get version => '1.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.bankScreenshot;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.userConfirmed;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  bool get rawPayloadRedacted => true;
  @override
  List<TransactionSeed> seeds(BankScreenshotInput input) => input.transactions;

  @override
  ImportBatch buildBatch(BankScreenshotInput input) => ImportBatch(
    id: ids.next('batch'),
    entityId: input.entityId,
    name: input.batchName,
    sourceType: sourceType,
    createdAt: input.receivedAt,
    status: ImportBatchStatus.processing,
    totalRecords: input.transactions.length,
    createdTransactions: 0,
    matchedTransactions: 0,
    failedRecords: 0,
  );

  @override
  AdaptedIngestion normalize(BankScreenshotInput input) {
    final adapted = super.normalize(input);
    return _withRawBody(
      adapted,
      jsonEncode({
        'source': 'local-bank-screenshot-ocr',
        'imageHashes': input.imageHashes,
        'parserIds': input.parserIds,
        'candidateCount': input.transactions.length,
        'rawTextRetained': false,
      }),
    );
  }
}

class ReceiptAdapter extends _TransactionAdapter<ReceiptInput> {
  ReceiptAdapter({super.ids});

  @override
  String get id => 'receipt';
  @override
  String get version => '1.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.receipt;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.receipt;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  List<TransactionSeed> seeds(ReceiptInput input) => [input.transaction];
  @override
  String get contentType => 'text/plain; charset=utf-8';

  @override
  List<SynoballReceipt> buildReceipts(
    ReceiptInput input,
    String ingestionId,
  ) => [
    SynoballReceipt(
      id: input.transaction.receiptId ?? 'receipt-${input.fiscalFingerprint}',
      ingestionRecordId: ingestionId,
      purchasedAt: input.transaction.occurredAt,
      total: input.transaction.amount,
      fiscalFingerprint: input.fiscalFingerprint,
      rawText: input.rawText,
      merchant: input.merchant,
      items: input.items,
      confidence: input.confidence,
      userCorrections: input.userCorrections,
    ),
  ];
}

class StatementAdapter extends _TransactionAdapter<StatementInput> {
  StatementAdapter({super.ids});

  @override
  String get id => 'statement';
  @override
  String get version => '1.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.statement;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.bankStatement;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  List<TransactionSeed> seeds(StatementInput input) => input.transactions;
  @override
  List<SynoballAccount> buildAccounts(StatementInput input) => [input.account];

  @override
  ImportBatch buildBatch(StatementInput input) => ImportBatch(
    id: ids.next('batch'),
    entityId: input.entityId,
    name: input.batchName,
    sourceType: sourceType,
    createdAt: input.receivedAt,
    status: ImportBatchStatus.processing,
    totalRecords: input.transactions.length,
    createdTransactions: 0,
    matchedTransactions: 0,
    failedRecords: 0,
  );
}

class BankWebAdapter extends _TransactionAdapter<StatementInput> {
  BankWebAdapter({super.ids});

  @override
  String get id => 'bank-web';
  @override
  String get version => '1.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.bankWeb;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.directApi;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  List<TransactionSeed> seeds(StatementInput input) => input.transactions;
  @override
  List<SynoballAccount> buildAccounts(StatementInput input) => [input.account];

  @override
  ImportBatch buildBatch(StatementInput input) => ImportBatch(
    id: ids.next('batch'),
    entityId: input.entityId,
    name: input.batchName,
    sourceType: sourceType,
    createdAt: input.receivedAt,
    status: ImportBatchStatus.processing,
    totalRecords: input.transactions.length,
    createdTransactions: 0,
    matchedTransactions: 0,
    failedRecords: 0,
  );
}

class LegacyQestoAdapter extends _TransactionAdapter<LegacyInput> {
  LegacyQestoAdapter({super.ids});

  @override
  String get id => 'legacy-qesto';
  @override
  String get version => '1.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.legacy;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.userConfirmed;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  List<TransactionSeed> seeds(LegacyInput input) => input.transactions;
  @override
  List<SynoballAccount> buildAccounts(LegacyInput input) => input.accounts;
  @override
  List<SynoballReceipt> buildReceipts(LegacyInput input, String ingestionId) =>
      input.receipts
          .map(
            (value) => SynoballReceipt(
              id: value.id,
              ingestionRecordId: ingestionId,
              purchasedAt: value.purchasedAt,
              total: value.total,
              fiscalFingerprint: value.fiscalFingerprint,
              rawText: value.rawText,
              merchant: value.merchant,
              items: value.items,
            ),
          )
          .toList(growable: false);
}

class CbrOpenFinanceAdapter extends _TransactionAdapter<CbrOpenFinanceInput> {
  CbrOpenFinanceAdapter({super.ids});

  @override
  String get id => 'ru-cbr-open-finance';
  @override
  String get version => 'mock-1.0.0';
  @override
  SynoballSourceType get sourceType => SynoballSourceType.regulatedApi;
  @override
  SourceTrustLevel get trust => SourceTrustLevel.regulatedApi;
  @override
  bool get defaultRequiresConfirmation => false;
  @override
  List<TransactionSeed> seeds(CbrOpenFinanceInput input) => input.transactions;
  @override
  List<SynoballAccount> buildAccounts(CbrOpenFinanceInput input) =>
      input.accounts;
  @override
  List<Institution> buildInstitutions(CbrOpenFinanceInput input) => [
    input.institution,
  ];
  @override
  List<SynoballConnection> buildConnections(CbrOpenFinanceInput input) => [
    input.connection,
  ];
  @override
  List<SynoballConsent> buildConsents(CbrOpenFinanceInput input) => [
    input.consent,
  ];
  @override
  List<SynoballCapability> getCapabilities() => const [
    SynoballCapability.accounts,
    SynoballCapability.balances,
    SynoballCapability.transactions,
  ];
}

String _normalizeText(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .trim();

AdaptedIngestion _withRawBody(AdaptedIngestion value, String body) =>
    AdaptedIngestion(
      rawPayload: RawPayload(
        id: value.rawPayload.id,
        contentType: 'application/json',
        body: body,
        createdAt: value.rawPayload.createdAt,
        redacted: value.rawPayload.redacted,
      ),
      record: value.record,
      candidates: value.candidates,
      receipts: value.receipts,
      importBatch: value.importBatch,
      accounts: value.accounts,
      institutions: value.institutions,
      connections: value.connections,
      consents: value.consents,
      warnings: value.warnings,
    );
