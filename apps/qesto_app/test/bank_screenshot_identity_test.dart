import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_screenshot_import/domain/bank_screenshot_models.dart';
import 'package:qesto/features/bank_screenshot_import/services/bank_screenshot_identity.dart';
import 'package:qesto/features/bank_screenshot_import/services/bank_screenshot_import_service.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  BankScreenshotCandidate row({
    String image = 'image-a',
    String currency = 'RUB',
    String account = 'A',
  }) => BankScreenshotCandidate(
    id: 'bank-shot-legacy-fingerprint',
    imageHash: image,
    parserId: 'generic-v1',
    merchant: 'Coffee',
    amountMinor: 10025,
    currency: currency,
    date: DateTime(2026, 8, 10),
    kind: BankScreenshotTransactionKind.expense,
    categoryId: 'cafe',
    confidence: 1,
    accountId: account,
  );
  SynoballCore core() => SynoballCore(
    initialState: SynoballState(
      accounts: [
        for (final id in ['A', 'B'])
          SynoballAccount(
            id: id,
            entityId: 'E',
            name: id,
            type: SynoballAccountType.checking,
            currency: 'RUB',
            balance: const Money(minorUnits: 0, currency: 'RUB'),
          ),
      ],
    ),
  );
  IngestionOutcome ingest(
    SynoballCore core,
    BankScreenshotCandidate row, {
    List<String>? images,
    bool legacy = false,
  }) => core.ingest(
    BankScreenshotAdapter(),
    BankScreenshotInput(
      entityId: 'E',
      receivedAt: DateTime(2026, 9, 6),
      rawPayload: 'redacted',
      batchName: 'Screenshot',
      imageHashes: images ?? [row.imageHash],
      parserIds: [row.parserId],
      transactions: [
        TransactionSeed(
          canonicalId: resolveScreenshotIdentity(row, core.state).canonicalId,
          providerTransactionId: row.id,
          accountId: row.accountId!,
          amount: Money(minorUnits: row.amountMinor, currency: row.currency),
          direction: FinancialDirection.outflow,
          occurredAt: row.date,
          description: row.merchant,
          merchant: row.merchant,
          confidence: 1,
          tags: [if (!legacy) 'bank-screenshot-image:${row.imageHash}'],
        ),
      ],
    ),
  );

  test(
    'image observation identity includes currency even if legacy hash omits it',
    () {
      expect(
        screenshotObservation(row()).id,
        isNot(screenshotObservation(row(currency: 'USD')).id),
      );
      expect(
        screenshotObservation(row()).id,
        isNot(screenshotObservation(row(image: 'image-b')).id),
      );
    },
  );
  for (final deleted in [false, true]) {
    test(
      'single-image legacy replay preserves canonical identity/trash ($deleted)',
      () {
        final engine = core();
        final id = ingest(
          engine,
          row(),
          legacy: true,
        ).createdTransactionIds.single;
        if (deleted) engine.deleteTransaction(id, actorId: 'user');
        final observed = screenshotObservation(row());
        final result = ingest(engine, observed);
        expect(result.resolvedTransactionIds, [id]);
        expect(result.createdTransactionIds, isEmpty);
        expect(engine.state.transactions, hasLength(1));
        if (deleted) expect(result.suppressedTransactionIds, [id]);
        expect(ingest(engine, observed).resolvedTransactionIds, [id]);
      },
    );
  }
  test('identical text on another image is review, not a legacy alias', () {
    final engine = core();
    ingest(engine, row(), legacy: true);
    final result = resolveScreenshotIdentity(
      screenshotObservation(row(image: 'image-b')),
      engine.state,
    );
    expect(result.canonicalId, isNull);
    expect(result.reviewReason, isNotNull);
  });
  test(
    'legacy batch image list does not prove the origin of an individual row',
    () {
      final engine = core();
      ingest(engine, row(), legacy: true, images: ['image-a', 'image-b']);
      final result = resolveScreenshotIdentity(
        screenshotObservation(row()),
        engine.state,
      );
      expect(result.canonicalId, isNull);
      expect(result.reviewReason, isNotNull);
    },
  );
  test('known different account prevents legacy alias', () {
    final engine = core();
    ingest(engine, row(), legacy: true);
    final result = resolveScreenshotIdentity(
      screenshotObservation(row(account: 'B')),
      engine.state,
    );
    expect(result.canonicalId, isNull);
    expect(result.reviewReason, isNull);
  });
  test(
    'explicit distinct-purchase confirmation can retain both equal purchases',
    () {
      final engine = core();
      ingest(engine, screenshotObservation(row()));
      final second = screenshotObservation(row(image: 'image-b'));
      expect(
        resolveScreenshotIdentity(second, engine.state).reviewReason,
        isNotNull,
      );
      expect(ingest(engine, second).createdTransactionIds, hasLength(1));
      expect(engine.transactions, hasLength(2));
    },
  );
  test('image without content hash is not silently deduplicated', () {
    final result = const BankScreenshotImportService().parseAll([
      ExtractedBankScreenshot(
        imageHash: '',
        capturedAt: DateTime(2026, 9, 6),
        lines: const [],
      ),
    ]);
    expect(result.candidates, isEmpty);
    expect(result.warnings.single, contains('отпечатка'));
  });
}
