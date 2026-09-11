import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/statement_import/domain/bank_statement_models.dart';
import 'package:qesto/features/statement_import/services/excel_source_identity.dart';
import 'package:qesto/features/statement_import/services/universal_excel_statement_adapter.dart';
import 'package:qesto/synoball/synoball.dart';

Uint8List identityWorkbook({
  int leadingRows = 0,
  int copies = 1,
  int year = 2026,
  int rubles = 100,
}) {
  final book = Excel.createExcel();
  final sheet = book['Sheet1'];
  void cell(int row, int column, CellValue value) => sheet.updateCell(
    CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    value,
  );
  cell(leadingRows, 0, TextCellValue('Дата'));
  cell(leadingRows, 1, TextCellValue('Описание'));
  cell(leadingRows, 2, TextCellValue('Расход'));
  for (var n = 1; n <= copies; n++) {
    cell(leadingRows + n, 0, DateCellValue(year: year, month: 8, day: 10));
    cell(leadingRows + n, 1, TextCellValue('Кофе'));
    cell(leadingRows + n, 2, DoubleCellValue(rubles + .25));
  }
  return Uint8List.fromList(book.encode()!);
}

void main() {
  ParsedBankStatement parse({
    String name = 'old.xlsx',
    int offset = 0,
    int copies = 1,
    int year = 2026,
    int rubles = 100,
  }) => const UniversalExcelStatementAdapter().parse(
    bytes: identityWorkbook(
      leadingRows: offset,
      copies: copies,
      year: year,
      rubles: rubles,
    ),
    fileName: name,
    referenceDate: DateTime(2026, 9, 6),
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
  Map<String, ExcelRowIdentity> resolve(
    SynoballCore engine,
    ParsedBankStatement statement, {
    String account = 'A',
  }) => resolveExcelRows(
    rows: statement.transactions,
    accountId: account,
    currency: 'RUB',
    history: engine.state,
  );
  IngestionOutcome import(
    SynoballCore engine,
    ParsedBankStatement statement, {
    bool legacy = false,
    String account = 'A',
  }) {
    final ids = resolve(engine, statement, account: account);
    return engine.ingest(
      StatementAdapter(),
      StatementInput(
        entityId: 'E',
        receivedAt: DateTime(2026, 9, 6),
        rawPayload: 'synthetic workbook',
        batchName: 'Excel',
        account: engine.state.accounts.firstWhere((a) => a.id == account),
        transactions: [
          for (final row in statement.transactions)
            if (legacy || ids[row.id]!.reviewReason == null)
              TransactionSeed(
                canonicalId: legacy
                    ? row.excelLegacyId
                    : ids[row.id]!.canonicalId,
                providerTransactionId: legacy ? row.excelLegacyId : row.id,
                accountId: account,
                amount: Money(
                  minorUnits: row.amountMinor.abs(),
                  currency: row.currency,
                ),
                direction: row.isIncoming
                    ? FinancialDirection.inflow
                    : FinancialDirection.outflow,
                occurredAt: row.operationDate,
                description: row.description,
                merchant: row.merchant,
                category: row.category.categoryId,
                confidence: 1,
                tags: [
                  'excel-import',
                  if (!legacy) 'excel-cell:${row.excelLegacyId}',
                ],
              ),
        ],
      ),
    );
  }

  test('filename and physical row are provenance, not financial identity', () {
    final old = parse();
    final moved = parse(name: 'renamed.xlsx', offset: 4);
    expect(old.transactions.single.id, moved.transactions.single.id);
    expect(
      old.transactions.single.excelLegacyId,
      isNot(moved.transactions.single.excelLegacyId),
    );
    expect(
      old.transactions.single.authorizationCode,
      isNot(moved.transactions.single.authorizationCode),
    );
  });
  test('new year or changed amount does not reuse a cell ID', () {
    final row = parse().transactions.single;
    expect(parse(year: 2025).transactions.single.id, isNot(row.id));
    expect(parse(rubles: 200).transactions.single.id, isNot(row.id));
  });
  test('equal rows preserve multiplicity across row insertion', () {
    final rows = parse(copies: 2).transactions;
    expect(rows.map((r) => r.id).toSet(), hasLength(2));
    expect(
      parse(copies: 2, offset: 3).transactions.map((r) => r.id),
      rows.map((r) => r.id),
    );
    final engine = core();
    expect(
      import(engine, parse(copies: 2)).createdTransactionIds,
      hasLength(2),
    );
    expect(
      import(engine, parse(copies: 2, name: 'copy.xlsx')).matchedTransactionIds,
      hasLength(2),
    );
  });
  test(
    'logical source scope separates independent books with identical contents',
    () {
      final engine = core();
      import(engine, parse());
      expect(
        import(engine, parse(), account: 'B').createdTransactionIds,
        hasLength(1),
      );
      expect(engine.transactions, hasLength(2));
    },
  );
  for (final deleted in [false, true]) {
    test(
      'legacy rename aliases exact evidence, including trash ($deleted)',
      () {
        final engine = core();
        final id = import(
          engine,
          parse(),
          legacy: true,
        ).createdTransactionIds.single;
        if (deleted) engine.deleteTransaction(id, actorId: 'user');
        final result = import(engine, parse(name: 'renamed.xlsx', offset: 3));
        expect(result.resolvedTransactionIds, [id]);
        expect(result.createdTransactionIds, isEmpty);
        if (deleted) expect(result.suppressedTransactionIds, [id]);
      },
    );
  }
  test('changed data in a legacy cell is held for review, not overwritten', () {
    final engine = core();
    import(engine, parse(), legacy: true);
    final rows = resolve(engine, parse(rubles: 200));
    expect(rows.values.single.reviewReason, isNotNull);
    expect(rows.values.single.existing, isFalse);
    expect(engine.transactions.single.amount.minorUnits, 10025);
  });

  test(
    'v2 cell edits also require review instead of adding a second expense',
    () {
      final engine = core();
      import(engine, parse());
      expect(
        resolve(engine, parse(rubles: 200)).values.single.reviewReason,
        isNotNull,
      );
      expect(
        resolve(engine, parse(year: 2025)).values.single.reviewReason,
        isNotNull,
      );
      expect(engine.transactions.single.amount.minorUnits, 10025);
    },
  );
  test(
    'legacy equal twins are not arbitrarily paired with edited/deleted rows',
    () {
      final engine = core();
      import(engine, parse(copies: 2), legacy: true);
      expect(
        resolve(
          engine,
          parse(copies: 2, name: 'renamed.xlsx'),
        ).values.every((r) => r.reviewReason != null),
        isTrue,
      );
    },
  );
  test('changing identical-row multiplicity requires review even for v2', () {
    final engine = core();
    import(engine, parse(copies: 2));
    expect(
      resolve(engine, parse(copies: 1)).values.single.reviewReason,
      isNotNull,
    );
    expect(
      resolve(
        engine,
        parse(copies: 3),
      ).values.every((r) => r.reviewReason != null),
      isTrue,
    );
  });
  test(
    'currency mismatch cannot be silently imported into selected source',
    () {
      final rows = resolveExcelRows(
        rows: parse().transactions,
        accountId: 'A',
        currency: 'USD',
        history: core().state,
      );
      expect(rows.values.single.reviewReason, contains('Валюта'));
    },
  );
}
