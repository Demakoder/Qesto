import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/voice_input/domain/voice_transaction_draft_parser.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  const parser = VoiceTransactionDraftParser();

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
