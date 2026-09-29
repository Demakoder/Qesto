import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statement_import/data/bank_statement_file_service.dart';
import 'package:qesto/features/statement_import/domain/bank_statement_models.dart';
import 'package:qesto/features/statement_import/presentation/statement_import_screen.dart';
import 'package:qesto/features/statement_import/services/universal_excel_statement_adapter.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'excel_source_identity_test.dart' show identityWorkbook;

void main() {
  testWidgets(
    'renamed Excel requires a logical source and reuses legacy operation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final budget = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Test',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 9, 6),
        ),
      );
      addTearDown(budget.dispose);
      final original = const UniversalExcelStatementAdapter().parse(
        bytes: identityWorkbook(),
        fileName: 'original.xlsx',
        referenceDate: DateTime(2026, 9, 6),
      );
      final row = original.transactions.single;
      const account = QestoAccount(
        id: 'excel-legacy-account',
        userId: 'user',
        title: 'Прежняя книга',
        balance: 321,
        currency: 'RUB',
        type: AccountType.other,
      );
      final period = budget.periodForOrCreate(row.operationDate);
      await budget.importStatement(
        account: account,
        transactions: [
          BudgetTransaction(
            id: row.excelLegacyId!,
            userId: 'user',
            accountId: account.id,
            date: row.operationDate,
            amount: row.roundedRubles,
            currency: row.currency,
            type: TransactionType.expense,
            categoryId: row.category.categoryId,
            merchant: row.merchant,
            description: row.description,
            tags: const ['excel-import'],
          ),
        ],
        exactMinorById: {row.excelLegacyId!: row.amountMinor.abs()},
        createdPeriodIds: {period.id},
        actionTitle: 'Legacy Excel',
        rawPayload:
            '{"fileName":"original.xlsx","source":"qesto-excel-adapter-v1"}',
      );
      final renamed = const UniversalExcelStatementAdapter().parse(
        bytes: identityWorkbook(leadingRows: 3),
        fileName: 'renamed.xlsx',
        referenceDate: DateTime(2026, 9, 6),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => StatementImportScreen(
                      controller: budget,
                      pickerMode: StatementPickerMode.excel,
                      fileService: const _File(),
                      excelAdapter: _Adapter(renamed),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-excel-file')));
      await tester.pumpAndSettle();
      expect(find.text('Выберите источник таблицы'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('import-statement-transactions')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Прежняя книга').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Уже добавленных операций: 1'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('import-statement-transactions')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(budget.transactions, hasLength(1));
      expect(budget.transactions.single.id, row.excelLegacyId);
      expect(budget.transactions.single.amountMinor, 10025);
      expect(budget.accounts.single.balance, 321);
    },
  );
}

class _File extends BankStatementFileService {
  const _File();
  @override
  Future<ExtractedStatementFile?> pickStatement({
    StatementPickerMode mode = StatementPickerMode.all,
  }) async => ExtractedStatementFile(
    fileName: 'renamed.xlsx',
    kind: StatementFileKind.excel,
    bytes: Uint8List(1),
  );
}

class _Adapter extends UniversalExcelStatementAdapter {
  const _Adapter(this.statement);
  final ParsedBankStatement statement;
  @override
  Future<ParsedBankStatement> parseInBackground({
    required Uint8List bytes,
    required String fileName,
    DateTime? referenceDate,
    int? yearOverride,
  }) async => statement;
}
