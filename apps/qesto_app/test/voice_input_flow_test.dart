import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/voice_input/domain/voice_transaction_draft_parser.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  const parser = VoiceTransactionDraftParser();

  test(
    'Android confirmed preview posts once and survives save retry',
    () async {
      var failSave = true;
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'voice-user',
            name: 'Test',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 9, 6),
        ),
        onChanged: () async {
          if (failSave) throw StateError('Synthetic disk failure');
        },
      );
      final transaction = BudgetTransaction(
        id: 'voice-command-1',
        userId: 'voice-user',
        accountId: controller.accounts.first.id,
        date: DateTime(2026, 9, 6),
        amount: 350,
        currency: 'RUB',
        type: TransactionType.expense,
        merchant: 'Coffee',
        categoryId: 'cafes',
        comment: 'Coffee 350',
      );
      await expectLater(
        controller.addImportedTransactions([
          transaction,
        ], confirmedVoiceInput: true),
        throwsStateError,
      );
      failSave = false;
      await controller.addImportedTransactions([
        transaction,
      ], confirmedVoiceInput: true);
      expect(controller.pendingCandidates, isEmpty);
      expect(controller.transactions.single.amount, 350);
      expect(
        controller.synoballState.transactions.single.amount.minorUnits,
        35000,
      );
      expect(
        controller.synoballState.evidence.single.sourceType,
        SynoballSourceType.manualVoice,
      );
    },
  );

  test('voice phrase extracts amount, merchant and category', () {
    final draft = parser.parse('Кофе 350 рублей в Surf Coffee');

    expect(draft.amountRubles, 350);
    expect(draft.merchant, 'Surf Coffee');
    expect(draft.categoryId, 'cafes');
  });

  test('voice candidate is not posted before explicit confirmation', () async {
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: UserFinancialData(
        user: const QestoUser(
          id: 'voice-user',
          name: 'Voice test',
          defaultCurrency: 'RUB',
        ),
        referenceDate: DateTime(2026, 8, 13),
      ),
    );

    final candidateId = await controller.addVoiceCandidate(
      transcript: 'Кофе 350 рублей в Surf Coffee',
      amountMinor: 35000,
      currency: 'RUB',
      accountId: controller.accounts.first.id,
      occurredAt: DateTime(2026, 8, 13),
      merchant: 'Surf Coffee',
      categoryId: 'cafes',
    );

    expect(controller.transactions, isEmpty);
    expect(controller.pendingCandidates.single.id, candidateId);
    expect(
      controller.synoballState.ingestionRecords
          .singleWhere(
            (record) =>
                record.id ==
                controller.pendingCandidates.single.ingestionRecordId,
          )
          .sourceType,
      SynoballSourceType.manualVoice,
    );

    await controller.confirmVoiceCandidate(candidateId);

    expect(controller.pendingCandidates, isEmpty);
    expect(controller.transactions.single.amount, 350);
    expect(controller.transactions.single.merchant, 'Surf Coffee');
    expect(controller.transactions.single.categoryId, 'cafes');
  });
}
