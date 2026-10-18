import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/statement_import/domain/bank_statement_models.dart';
import 'package:qesto/features/statement_import/services/universal_excel_statement_adapter.dart';
import 'package:qesto/features/statement_import/services/xlsx_package_relationships.dart';
import 'package:xml/xml.dart';

const _rels = 'xl/_rels/workbook.xml.rels';

Uint8List _fixture() =>
    File('test/fixtures/QA-ST6-import.xlsx').readAsBytesSync();

Uint8List _alter(void Function(Archive, XmlDocument) change) {
  final archive = ZipDecoder().decodeBytes(_fixture());
  final document = XmlDocument.parse(
    utf8.decode(archive.findFile(_rels)!.content),
  );
  change(archive, document);
  archive.add(ArchiveFile.bytes(_rels, utf8.encode(document.toXmlString())));
  return ZipEncoder().encodeBytes(archive);
}

XmlElement _relationship(XmlDocument document, String kind) => document
    .rootElement
    .childElements
    .firstWhere((node) => node.getAttribute('Type')!.endsWith('/$kind'));

ParsedBankStatement _parse(Uint8List bytes) =>
    const UniversalExcelStatementAdapter().parse(
      bytes: bytes,
      fileName: 'QA-ST6-import.xlsx',
      referenceDate: DateTime(2026, 10, 6),
    );

void _expectAmounts(ParsedBankStatement statement) {
  expect(statement.transactions, hasLength(2));
  final income = statement.transactions.first;
  final expense = statement.transactions.last;
  expect(income.amountMinor, 200025);
  expect(income.operationDate, DateTime(2026, 10, 5));
  expect(income.kind, StatementTransactionKind.income);
  expect(income.isIncoming, isTrue);
  expect(income.currency, 'RUB');
  expect(expense.amountMinor, -8035);
  expect(expense.operationDate, DateTime(2026, 10, 6));
  expect(expense.kind, StatementTransactionKind.expense);
  expect(expense.isIncoming, isFalse);
  expect(expense.currency, 'RUB');
}

void main() {
  test('sharedStrings content survives absolute target and XML prefixes', () {
    final bytes = _alter((archive, _) {
      archive.add(
        ArchiveFile.string(
          'xl/sharedStrings.xml',
          '<x:sst xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1"><x:si><x:t>QA-ST6-XLSX-Expense</x:t></x:si></x:sst>',
        ),
      );
      final sheet = utf8
          .decode(archive.findFile('xl/worksheets/sheet1.xml')!.content)
          .replaceFirst(
            't="str"><x:v>QA-ST6-XLSX-Expense</x:v>',
            't="s"><x:v>0</x:v>',
          );
      archive.add(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet));
    });
    final parsed = _parse(bytes);
    _expectAmounts(parsed);
    expect(
      parsed.transactions.last.description,
      contains('QA-ST6-XLSX-Expense'),
    );
  });

  test('normalization preserves formula cells and treats literals as text', () {
    final bytes = _alter((archive, _) {
      final sheet = utf8
          .decode(archive.findFile('xl/worksheets/sheet1.xml')!.content)
          .replaceFirst(
            '<x:c r="E1" s="1" />',
            '<x:c r="E1" s="1" t="str"><x:f>"TEXT"</x:f><x:v>TEXT</x:v></x:c>',
          );
      archive.add(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet));
    });
    final normalized = prepareXlsxRelationships(
      ZipDecoder().decodeBytes(bytes),
    )!;
    final book = Excel.decodeBytes(normalized);
    final row = book.tables.values.single.rows.first;
    expect(row.first!.value, isA<TextCellValue>());
    expect(row[4]!.value, isA<FormulaCellValue>());
    _expectAmounts(_parse(bytes));
  });
  test(
    'unchanged Stage 6A absolute styles/sharedStrings/worksheet package',
    () {
      _expectAmounts(_parse(_fixture()));
    },
  );

  test(
    'ordinary relative targets retain exact values and source identities',
    () {
      final original = _parse(_fixture());
      final relative = _parse(
        _alter((_, document) {
          for (final relation in document.rootElement.childElements) {
            relation.setAttribute(
              'Target',
              relation.getAttribute('Target')!.replaceFirst('/xl/', ''),
            );
          }
        }),
      );
      _expectAmounts(relative);
      expect(
        relative.transactions.map((row) => row.id),
        original.transactions.map((row) => row.id),
      );
      expect(
        relative.transactions.map((row) => row.excelObservationKey),
        original.transactions.map((row) => row.excelObservationKey),
      );
    },
  );

  for (final kind in ['styles', 'sharedStrings', 'worksheet']) {
    test('$kind absolute package target resolves independently', () {
      _expectAmounts(
        _parse(
          _alter((_, document) {
            for (final relation in document.rootElement.childElements) {
              if (!relation.getAttribute('Type')!.endsWith('/$kind')) {
                relation.setAttribute(
                  'Target',
                  relation.getAttribute('Target')!.replaceFirst('/xl/', ''),
                );
              }
            }
          }),
        ),
      );
    });
    test('$kind missing package part fails before lossy decoder fallback', () {
      final bytes = _alter((archive, document) {
        final target = _relationship(
          document,
          kind,
        ).getAttribute('Target')!.substring(1);
        archive.removeFile(archive.findFile(target)!);
      });
      expect(
        () => _parse(bytes),
        throwsA(isA<UnsupportedBankStatementException>()),
      );
    });
  }

  for (final target in [
    '../../styles.xml',
    '/../../xl/styles.xml',
    '%2e%2e/%2e%2e/xl/styles.xml',
    'https://example.invalid/styles.xml',
    '//server/share/styles.xml',
    r'\\server\share\styles.xml',
    'C:/xl/styles.xml',
    'file:///xl/styles.xml',
    '/xl/%2e%2e/%2e%2e/styles.xml',
    '/xl/styles.xml?network=1',
  ]) {
    test('unsafe target $target is rejected', () {
      final bytes = _alter((_, document) {
        _relationship(document, 'styles').setAttribute('Target', target);
      });
      expect(
        () => _parse(bytes),
        throwsA(isA<UnsupportedBankStatementException>()),
      );
    });
  }
  test('external relationship rejected even when target is inside ZIP', () {
    final bytes = _alter((_, document) {
      _relationship(document, 'styles').setAttribute('TargetMode', 'External');
    });
    expect(
      () => _parse(bytes),
      throwsA(isA<UnsupportedBankStatementException>()),
    );
  });
  test('external worksheet hyperlink is removed, never resolved or fetched', () {
    final bytes = _alter((archive, _) {
      final sheet = utf8
          .decode(archive.findFile('xl/worksheets/sheet1.xml')!.content)
          .replaceFirst(
            '</x:worksheet>',
            '<x:hyperlinks><x:hyperlink ref="A1" r:id="external" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/></x:hyperlinks></x:worksheet>',
          );
      archive.add(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet));
      archive.add(
        ArchiveFile.string(
          'xl/worksheets/_rels/sheet1.xml.rels',
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="external" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.invalid" TargetMode="External"/>'
              '</Relationships>',
        ),
      );
    });
    _expectAmounts(_parse(bytes));
    final safeBytes = prepareXlsxRelationships(
      ZipDecoder().decodeBytes(bytes),
    )!;
    final safe = ZipDecoder().decodeBytes(safeBytes);
    expect(
      utf8.decode(
        safe.findFile('xl/worksheets/_rels/sheet1.xml.rels')!.content,
      ),
      isNot(contains('External')),
    );
    expect(
      utf8.decode(safe.findFile('xl/worksheets/sheet1.xml')!.content),
      isNot(contains('id="external"')),
    );
  });
  for (final kind in ['styles', 'worksheet']) {
    // Required external data parts are tested above; inert links are stripped.
    test('missing $kind relationship rejected', () {
      final bytes = _alter((_, document) {
        _relationship(document, kind).remove();
      });
      expect(
        () => _parse(bytes),
        throwsA(isA<UnsupportedBankStatementException>()),
      );
    });
  }
  test('relationship without Target rejected', () {
    final bytes = _alter((_, document) {
      _relationship(document, 'styles').removeAttribute('Target');
    });
    expect(
      () => _parse(bytes),
      throwsA(isA<UnsupportedBankStatementException>()),
    );
  });
  test('duplicate relationship ID rejected', () {
    final bytes = _alter((_, document) {
      _relationship(document, 'styles').setAttribute(
        'Id',
        _relationship(document, 'worksheet').getAttribute('Id')!,
      );
    });
    expect(
      () => _parse(bytes),
      throwsA(isA<UnsupportedBankStatementException>()),
    );
  });
  for (final content in [
    '<Relationships',
    '<!DOCTYPE Relationships [<!ENTITY injected SYSTEM "file:///secret">]><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>',
  ]) {
    test('malformed or DTD XML rejected', () {
      final archive = ZipDecoder().decodeBytes(_fixture());
      archive.add(ArchiveFile.string(_rels, content));
      expect(
        () => _parse(ZipEncoder().encodeBytes(archive)),
        throwsA(isA<UnsupportedBankStatementException>()),
      );
    });
  }
  test('missing relationship file rejected', () {
    final archive = ZipDecoder().decodeBytes(_fixture());
    archive.removeFile(archive.findFile(_rels)!);
    expect(
      () => _parse(ZipEncoder().encodeBytes(archive)),
      throwsA(isA<UnsupportedBankStatementException>()),
    );
  });
  test('ZIP traversal part is rejected even if unrelated to workbook', () {
    final bytes = _alter((archive, _) {
      archive.add(ArchiveFile.string('../escape', 'no'));
    });
    expect(
      () => _parse(bytes),
      throwsA(isA<UnsupportedBankStatementException>()),
    );
  });
}
