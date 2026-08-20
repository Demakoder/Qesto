import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter/foundation.dart';

import '../../notification_import/services/merchant_category_classifier.dart';
import '../domain/bank_statement_models.dart';

/// Converts user-authored XLSX/XLSM workbooks into the existing statement
/// import model. Synoball is deliberately kept outside this adapter: the
/// regular statement ingestion boundary remains the only writer to the core.
class UniversalExcelStatementAdapter {
  const UniversalExcelStatementAdapter({
    this.classifier = const MerchantCategoryClassifier(),
  });

  final MerchantCategoryClassifier classifier;

  Future<ParsedBankStatement> parseInBackground({
    required Uint8List bytes,
    required String fileName,
    DateTime? referenceDate,
    int? yearOverride,
  }) => compute(_parseExcelIsolate, {
    'bytes': bytes,
    'fileName': fileName,
    'referenceDate': referenceDate?.millisecondsSinceEpoch,
    'yearOverride': yearOverride,
  });

  ParsedBankStatement parse({
    required Uint8List bytes,
    required String fileName,
    DateTime? referenceDate,
    int? yearOverride,
  }) {
    if (bytes.isEmpty) {
      throw const UnsupportedBankStatementException('Excel-файл пуст');
    }
    if (bytes.length > 20 * 1024 * 1024) {
      throw const UnsupportedBankStatementException(
        'Размер Excel-файла не должен превышать 20 МБ',
      );
    }
    _validateExcelArchive(bytes);

    late final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } on Object {
      throw const UnsupportedBankStatementException(
        'Не удалось прочитать Excel. Поддерживаются файлы XLSX и XLSM без запуска макросов.',
      );
    }
    if (workbook.tables.length > 50 ||
        workbook.tables.values.any(
          (sheet) => sheet.maxRows > 10000 || sheet.maxColumns > 80,
        )) {
      throw const UnsupportedBankStatementException(
        'Excel слишком большой: максимум 50 листов, 10000 строк и 80 столбцов',
      );
    }

    final fallbackDate = referenceDate ?? DateTime.now();
    final workbookYear = _workbookExplicitYear(workbook);
    final grids = <_SheetGrid>[
      for (final entry in workbook.tables.entries)
        _SheetGrid.fromSheet(
          entry.key,
          entry.value,
          fallbackDate,
          forcedYear: yearOverride,
          defaultYear: workbookYear,
        ),
    ];
    final regular = grids.where((grid) => !grid.isSummaryLike).toList();
    final summary = grids.where((grid) => grid.isSummaryLike).toList();
    final drafts = _parseSheets(regular, fileName, fallbackDate);
    if (drafts.isEmpty) {
      drafts.addAll(_parseSheets(summary, fileName, fallbackDate));
    }

    final unique = <String, _ExcelDraft>{};
    for (final draft in drafts) {
      if (draft.amountMinor == 0) continue;
      unique.putIfAbsent(draft.sourceKey, () => draft);
    }
    final ordered = unique.values.toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.sourceKey.compareTo(b.sourceKey);
      });
    if (ordered.isEmpty) {
      throw const UnsupportedBankStatementException(
        'В Excel не найдены строки с датой и суммой или заполненная помесячная таблица',
      );
    }

    final transactions = ordered
        .map((draft) => _toStatementTransaction(draft, fileName))
        .toList(growable: false);
    return ParsedBankStatement(
      bankName: 'Excel',
      periodStart: transactions.first.operationDate,
      periodEnd: transactions.last.operationDate,
      transactions: transactions,
    );
  }

  List<_ExcelDraft> _parseSheets(
    List<_SheetGrid> grids,
    String fileName,
    DateTime fallbackDate,
  ) {
    final result = <_ExcelDraft>[];
    for (final grid in grids) {
      final claimedCells = <String>{};
      result.addAll(
        _parsePersistentCategoryLedgers(grid, fileName, claimedCells),
      );
      result.addAll(_parseBandedCategoryTables(grid, fileName, claimedCells));
      result.addAll(
        _parseColumnPeriodMatrices(grid, fileName, fallbackDate, claimedCells),
      );
      result.addAll(
        _parseRowPeriodMatrices(grid, fileName, fallbackDate, claimedCells),
      );
      result.addAll(
        _parseVerticalTables(grid, fileName, fallbackDate, claimedCells),
      );
      result.addAll(
        _parseMonthlyMatrices(grid, fileName, fallbackDate, claimedCells),
      );
      result.addAll(
        _parseCategoryMatrices(grid, fileName, fallbackDate, claimedCells),
      );
    }
    return result;
  }

  /// Parses budget sheets where expense categories are fixed in columns and
  /// dates appear only when a new group of amounts begins. Some templates
  /// repeat the category labels for every date, while older revisions keep a
  /// single header for the entire month. Both are handled by the same stateful
  /// scan without turning budget totals elsewhere on the sheet into expenses.
  List<_ExcelDraft> _parsePersistentCategoryLedgers(
    _SheetGrid grid,
    String fileName,
    Set<String> claimedCells,
  ) {
    if (grid.monthHint == null) return const <_ExcelDraft>[];
    final result = <_ExcelDraft>[];
    final maximum = grid.rows.length < 5000 ? grid.rows.length : 5000;
    for (
      var headerRow = 0;
      headerRow < maximum && headerRow < 80;
      headerRow++
    ) {
      final row = grid.rows[headerRow];
      final candidates = <int, String>{};
      for (var column = 0; column < row.length; column++) {
        final label = _cleanText(row[column]);
        if (label == null ||
            _columnRole(label) != null ||
            _monthNumber(label) != null ||
            _isSummaryLabel(label)) {
          continue;
        }
        candidates[column] = label;
      }
      if (candidates.length < 3) continue;

      final columns = candidates.keys.toList()..sort();
      var bestStart = 0;
      var bestEnd = 0;
      var runStart = 0;
      for (var index = 1; index <= columns.length; index++) {
        if (index < columns.length &&
            columns[index] == columns[index - 1] + 1) {
          continue;
        }
        if (index - runStart > bestEnd - bestStart) {
          bestStart = runStart;
          bestEnd = index;
        }
        runStart = index;
      }
      final contiguous = columns.sublist(bestStart, bestEnd);
      if (contiguous.length < 3) continue;
      final distinctCategories = contiguous
          .map((column) => _normalizeText(candidates[column]))
          .toSet();
      final financialCategories = distinctCategories
          .where(_looksLikeFinancialCategoryLabel)
          .length;
      if (distinctCategories.length < 3 || financialCategories < 2) continue;
      final firstCategory = contiguous.first;
      final nearbyContext = <String>[
        grid.name,
        for (
          var contextRow = headerRow - 3;
          contextRow <= headerRow;
          contextRow++
        )
          if (contextRow >= 0)
            ...grid.rows[contextRow]
                .take(firstCategory + 1)
                .map(_cleanText)
                .whereType<String>(),
      ].join(' ');
      final looksLikeExpenses = RegExp(
        r'трат|расход|покуп',
      ).hasMatch(_normalizeText(nearbyContext));
      if (!looksLikeExpenses && financialCategories < 3) continue;

      final categories = <int, String>{
        for (final column in contiguous) column: candidates[column]!,
      };
      var currentDate = DateTime(grid.yearHint, grid.monthHint!);
      var foundAmount = false;
      var emptyRun = 0;
      for (var rowIndex = headerRow + 1; rowIndex < maximum; rowIndex++) {
        final dataRow = grid.rows[rowIndex];
        final dateSearchStart = firstCategory > 2 ? firstCategory - 2 : 0;
        for (var column = dateSearchStart; column < firstCategory; column++) {
          final parsed = _parseDate(
            _at(dataRow, column),
            sheetMonth: grid.monthHint,
            sheetYear: grid.yearHint,
          );
          if (parsed != null) {
            currentDate = parsed;
            break;
          }
        }

        var populated = 0;
        for (final entry in categories.entries) {
          final rawAmount = _parseMoney(_at(dataRow, entry.key));
          if (rawAmount == null || rawAmount == 0) continue;
          populated++;
          final cellKey = '${grid.name}:$rowIndex:${entry.key}';
          if (!claimedCells.add(cellKey)) continue;
          foundAmount = true;
          final direction = _resolveDirection(
            headerRole: _ColumnRole.amount,
            rawAmount: rawAmount,
            sheetName: grid.name,
            description: entry.value,
          );
          result.add(
            _draft(
              fileName: fileName,
              grid: grid,
              row: rowIndex,
              column: entry.key,
              date: currentDate,
              rawAmount: rawAmount,
              direction: direction,
              description: entry.value,
              category: entry.value,
              aggregate: false,
            ),
          );
        }
        if (populated == 0 && dataRow.every(_isBlank)) {
          emptyRun++;
        } else {
          emptyRun = 0;
        }
        if (foundAmount && emptyRun >= 40) break;
      }
      if (foundAmount) break;
    }
    return result;
  }

  List<_ExcelDraft> _parseBandedCategoryTables(
    _SheetGrid grid,
    String fileName,
    Set<String> claimedCells,
  ) {
    final result = <_ExcelDraft>[];
    final maximum = grid.rows.length < 5000 ? grid.rows.length : 5000;
    for (var headerRow = 0; headerRow < maximum; headerRow++) {
      final row = grid.rows[headerRow];
      final dateEntry = _dateEntryInRow(grid, row);
      if (dateEntry == null) continue;
      final categories = <int, String>{};
      for (var column = dateEntry.column + 1; column < row.length; column++) {
        final label = _cleanText(row[column]);
        if (label == null ||
            _columnRole(label) != null ||
            _monthNumber(label) != null ||
            _isSummaryLabel(label)) {
          continue;
        }
        categories[column] = label;
      }
      if (categories.length < 3) continue;
      final distinctCategories = categories.values.map(_normalizeText).toSet();
      if (distinctCategories.length < 3 ||
          distinctCategories.where(_looksLikeFinancialCategoryLabel).length <
              2) {
        continue;
      }

      var blockEnd = headerRow + 1;
      while (blockEnd < maximum && blockEnd <= headerRow + 40) {
        final next = grid.rows[blockEnd];
        final nextDate = _dateEntryInRow(grid, next);
        if (nextDate != null &&
            nextDate.column == dateEntry.column &&
            next
                    .skip(dateEntry.column + 1)
                    .map(_cleanText)
                    .whereType<String>()
                    .length >=
                3) {
          break;
        }
        blockEnd++;
      }

      var foundAmount = false;
      for (var rowIndex = headerRow + 1; rowIndex < blockEnd; rowIndex++) {
        final dataRow = grid.rows[rowIndex];
        for (final entry in categories.entries) {
          final rawAmount = _parseMoney(_at(dataRow, entry.key));
          if (rawAmount == null || rawAmount == 0) continue;
          final cellKey = '${grid.name}:$rowIndex:${entry.key}';
          if (!claimedCells.add(cellKey)) continue;
          foundAmount = true;
          final direction = _resolveDirection(
            headerRole: _ColumnRole.amount,
            rawAmount: rawAmount,
            sheetName: grid.name,
            description: entry.value,
          );
          result.add(
            _draft(
              fileName: fileName,
              grid: grid,
              row: rowIndex,
              column: entry.key,
              date: dateEntry.date,
              rawAmount: rawAmount,
              direction: direction,
              description: entry.value,
              category: entry.value,
              aggregate: true,
            ),
          );
        }
      }
      if (foundAmount) headerRow = blockEnd - 1;
    }
    return result;
  }

  List<_ExcelDraft> _parseColumnPeriodMatrices(
    _SheetGrid grid,
    String fileName,
    DateTime fallbackDate,
    Set<String> claimedCells,
  ) {
    final result = <_ExcelDraft>[];
    final limit = grid.rows.length < 180 ? grid.rows.length : 180;
    for (var headerRow = 0; headerRow < limit; headerRow++) {
      final row = grid.rows[headerRow];
      final periodColumns = <int, DateTime>{};
      for (var column = 0; column < row.length; column++) {
        final date = _columnPeriodDate(
          row[column],
          sheetMonth: grid.monthHint,
          sheetYear: grid.yearHint,
        );
        if (date != null) periodColumns[column] = date;
      }
      if (periodColumns.length < 2) continue;
      final firstPeriodColumn = periodColumns.keys.reduce(
        (left, right) => left < right ? left : right,
      );
      final roles = <int, _ColumnRole>{};
      for (var column = 0; column < row.length; column++) {
        final role = _columnRole(row[column]);
        if (role != null) roles[column] = role;
      }
      final descriptorCandidates = roles.entries
          .where(
            (entry) =>
                entry.value == _ColumnRole.category ||
                entry.value == _ColumnRole.description ||
                entry.value == _ColumnRole.merchant,
          )
          .map((entry) => entry.key)
          .where((column) => column < firstPeriodColumn)
          .toList();
      int? descriptorColumn = descriptorCandidates.isEmpty
          ? null
          : descriptorCandidates.last;
      descriptorColumn ??= _nearestTextColumnBefore(row, firstPeriodColumn);
      if (descriptorColumn == null) continue;

      final section =
          _cleanText(_at(row, descriptorColumn)) ??
          _textBefore(row, firstPeriodColumn) ??
          grid.name;
      var currentDirection = _resolveDirection(
        headerRole: _ColumnRole.amount,
        rawAmount: 1,
        sheetName: '${grid.name} $section',
        description: '',
      );
      final maximum = grid.rows.length < headerRow + 500
          ? grid.rows.length
          : headerRow + 500;
      var matchedRows = 0;
      var emptyRun = 0;
      for (var rowIndex = headerRow + 1; rowIndex < maximum; rowIndex++) {
        final dataRow = grid.rows[rowIndex];
        final label = _cleanText(_at(dataRow, descriptorColumn));
        final rowContext = _normalizeText(
          dataRow.map(_cleanText).whereType<String>().join(' '),
        );
        if (RegExp(
          r'категори[ия] доход|источник[и]? доход',
        ).hasMatch(rowContext)) {
          currentDirection = _Direction.income;
          continue;
        }
        if (RegExp(
          r'категори[ия] расход|стать[ия] расход',
        ).hasMatch(rowContext)) {
          currentDirection = _Direction.expense;
          continue;
        }
        if (_isSummaryLabel(rowContext)) {
          emptyRun = 0;
          continue;
        }
        final populated = periodColumns.keys
            .where((column) => _parseMoney(_at(dataRow, column)) != null)
            .length;
        if (label == null && populated == 0) {
          emptyRun++;
          if (matchedRows > 0 || emptyRun >= 5) break;
          continue;
        }
        emptyRun = 0;
        if (label == null || _isSummaryLabel(label)) continue;
        if (populated == 0) continue;
        matchedRows++;
        for (final entry in periodColumns.entries) {
          final rawAmount = _parseMoney(_at(dataRow, entry.key));
          if (rawAmount == null || rawAmount == 0) continue;
          final cellKey = '${grid.name}:$rowIndex:${entry.key}';
          if (!claimedCells.add(cellKey)) continue;
          result.add(
            _draft(
              fileName: fileName,
              grid: grid,
              row: rowIndex,
              column: entry.key,
              date: entry.value,
              rawAmount: rawAmount,
              direction: currentDirection,
              description: label,
              category: label,
              aggregate: true,
            ),
          );
        }
        for (final role in roles.entries.where(
          (entry) => _isAmountRole(entry.value),
        )) {
          if (_parseMoney(_at(dataRow, role.key)) != null) {
            claimedCells.add('${grid.name}:$rowIndex:${role.key}');
          }
        }
      }
      if (matchedRows > 0) break;
    }
    return result;
  }

  List<_ExcelDraft> _parseRowPeriodMatrices(
    _SheetGrid grid,
    String fileName,
    DateTime fallbackDate,
    Set<String> claimedCells,
  ) {
    final result = <_ExcelDraft>[];
    final limit = grid.rows.length < 160 ? grid.rows.length : 160;
    for (var headerRow = 0; headerRow < limit; headerRow++) {
      final row = grid.rows[headerRow];
      int? periodColumn;
      for (var column = 0; column < row.length; column++) {
        final text = _normalizeText(row[column]);
        if (RegExp(r'(^|\s)(месяц|период)(\s|$)').hasMatch(text)) {
          periodColumn = column;
          break;
        }
      }
      if (periodColumn == null) continue;

      final candidates = <_RowPeriodColumn>[];
      for (var column = 0; column < row.length; column++) {
        if (column == periodColumn) continue;
        final context = _matrixHeaderContext(grid, headerRow, column);
        final normalized = _normalizeText(context);
        if (normalized.isEmpty ||
            RegExp(
              r'(^|\s)(план|дельта|отклонен|процент|%|остаток|баланс|целевая|курс|колич|avg|floor)(\s|$)',
            ).hasMatch(normalized)) {
          continue;
        }
        final hasIncome = RegExp(
          r'доход|заработ|зарплат|зачислен|оклад|преми|начислен|источник',
        ).hasMatch(normalized);
        final hasExpense = RegExp(
          r'расход|трат|покуп|списан|еда|коммун|интернет|маркетплейс|супермаркет|переводы другим|услуг',
        ).hasMatch(normalized);
        final capital = _capitalKind(normalized);
        if (!hasIncome && !hasExpense && capital == null) continue;
        final direction = hasIncome && !hasExpense
            ? _Direction.income
            : _Direction.expense;
        candidates.add(
          _RowPeriodColumn(
            column: column,
            description: _matrixHeaderLabel(grid, headerRow, column),
            direction: direction,
            capitalKind: capital,
            isTotal: RegExp(r'итог|суммар|общ').hasMatch(normalized),
          ),
        );
      }
      if (candidates.length < 2) continue;

      final selected = <_RowPeriodColumn>[];
      final income = candidates
          .where((item) => item.direction == _Direction.income)
          .toList();
      final expense = candidates
          .where(
            (item) =>
                item.direction == _Direction.expense &&
                item.capitalKind == null,
          )
          .toList();
      final capital = candidates
          .where((item) => item.capitalKind != null)
          .toList();
      final incomeTotals = income.where((item) => item.isTotal).toList();
      selected.addAll(incomeTotals.isNotEmpty ? incomeTotals : income);
      final expenseDetails = expense.where((item) => !item.isTotal).toList();
      selected.addAll(expenseDetails.length >= 2 ? expenseDetails : expense);
      selected.addAll(capital.where((item) => !item.isTotal));
      if (selected.isEmpty) continue;

      final maximum = grid.rows.length < headerRow + 180
          ? grid.rows.length
          : headerRow + 180;
      var matchedRows = 0;
      for (var rowIndex = headerRow + 1; rowIndex < maximum; rowIndex++) {
        final dataRow = grid.rows[rowIndex];
        final date = _parseMonthHeader(
          _at(dataRow, periodColumn),
          sheetYear: grid.yearHint,
          fallbackYear: fallbackDate.year,
          preferSheetYear: grid.yearIsExplicit,
        );
        if (date == null) continue;
        var rowHasAmount = false;
        for (final item in selected) {
          final rawAmount = _parseMoney(_at(dataRow, item.column));
          if (rawAmount == null || rawAmount == 0) continue;
          final cellKey = '${grid.name}:$rowIndex:${item.column}';
          if (!claimedCells.add(cellKey)) continue;
          rowHasAmount = true;
          result.add(
            _draft(
              fileName: fileName,
              grid: grid,
              row: rowIndex,
              column: item.column,
              date: date,
              rawAmount: rawAmount,
              direction: item.direction,
              description: item.description,
              category: item.description,
              aggregate: true,
            ),
          );
        }
        if (rowHasAmount) {
          matchedRows++;
          for (final item in candidates) {
            if (_parseMoney(_at(dataRow, item.column)) != null) {
              claimedCells.add('${grid.name}:$rowIndex:${item.column}');
            }
          }
        }
      }
      if (matchedRows > 0) break;
    }
    return result;
  }

  List<_ExcelDraft> _parseVerticalTables(
    _SheetGrid grid,
    String fileName,
    DateTime fallbackDate,
    Set<String> claimedCells,
  ) {
    final drafts = <_ExcelDraft>[];
    final headerLimit = grid.rows.length < 220 ? grid.rows.length : 220;
    for (var headerRow = 0; headerRow < headerLimit; headerRow++) {
      final row = grid.rows[headerRow];
      final roles = <int, _ColumnRole>{};
      for (var column = 0; column < row.length; column++) {
        final role = _columnRole(row[column]);
        if (role != null) roles[column] = role;
      }
      final dateColumns = roles.entries
          .where((entry) => entry.value == _ColumnRole.date)
          .map((entry) => entry.key)
          .toList();
      final hasAmount = roles.values.any(_isAmountRole);
      final hasDescriptor = roles.values.any(
        (role) =>
            role == _ColumnRole.category ||
            role == _ColumnRole.description ||
            role == _ColumnRole.merchant,
      );
      if (!hasAmount || (dateColumns.isEmpty && !hasDescriptor)) continue;

      if (dateColumns.isNotEmpty) {
        for (var block = 0; block < dateColumns.length; block++) {
          final start = dateColumns[block];
          final end = block + 1 < dateColumns.length
              ? dateColumns[block + 1] - 1
              : _verticalBlockEnd(roles, start, row.length);
          drafts.addAll(
            _readVerticalBlock(
              grid: grid,
              fileName: fileName,
              headerRow: headerRow,
              startColumn: start,
              endColumn: end,
              roles: roles,
              dateColumn: start,
              fallbackDate: fallbackDate,
              claimedCells: claimedCells,
            ),
          );
        }
      } else {
        final month = grid.monthHint;
        if (month == null) continue;
        for (final amountEntry in roles.entries.where(
          (entry) => _isAmountRole(entry.value),
        )) {
          final descriptorColumn = _nearestDescriptorColumn(
            roles,
            amountEntry.key,
          );
          if (descriptorColumn == null) continue;
          drafts.addAll(
            _readVerticalBlock(
              grid: grid,
              fileName: fileName,
              headerRow: headerRow,
              startColumn: descriptorColumn < amountEntry.key
                  ? descriptorColumn
                  : amountEntry.key,
              endColumn: descriptorColumn > amountEntry.key
                  ? descriptorColumn
                  : amountEntry.key,
              roles: roles,
              dateColumn: null,
              fallbackDate: DateTime(grid.yearHint, month),
              claimedCells: claimedCells,
              forcedAmountColumn: amountEntry.key,
            ),
          );
        }
      }
    }
    return drafts;
  }

  int _verticalBlockEnd(Map<int, _ColumnRole> roles, int start, int rowLength) {
    var last = start;
    for (var column = start + 1; column < rowLength; column++) {
      final role = roles[column];
      if (role == _ColumnRole.date) break;
      if (role != null) last = column;
    }
    return last < start ? start : last;
  }

  int? _nearestDescriptorColumn(Map<int, _ColumnRole> roles, int amountColumn) {
    final candidates = roles.entries.where(
      (entry) =>
          entry.value == _ColumnRole.category ||
          entry.value == _ColumnRole.description ||
          entry.value == _ColumnRole.merchant,
    );
    int? best;
    var bestDistance = 1000;
    for (final entry in candidates) {
      final distance = (entry.key - amountColumn).abs();
      if (distance < bestDistance && distance <= 6) {
        best = entry.key;
        bestDistance = distance;
      }
    }
    return best;
  }

  List<_ExcelDraft> _readVerticalBlock({
    required _SheetGrid grid,
    required String fileName,
    required int headerRow,
    required int startColumn,
    required int endColumn,
    required Map<int, _ColumnRole> roles,
    required int? dateColumn,
    required DateTime fallbackDate,
    required Set<String> claimedCells,
    int? forcedAmountColumn,
  }) {
    final result = <_ExcelDraft>[];
    final amountColumns = forcedAmountColumn == null
        ? roles.entries
              .where(
                (entry) =>
                    entry.key >= startColumn &&
                    entry.key <= endColumn &&
                    _isAmountRole(entry.value),
              )
              .map((entry) => entry.key)
              .toList()
        : [forcedAmountColumn];
    if (amountColumns.isEmpty) return result;

    var emptyRun = 0;
    final maximum = grid.rows.length < headerRow + 5000
        ? grid.rows.length
        : headerRow + 5000;
    DateTime? carriedDate;
    for (var rowIndex = headerRow + 1; rowIndex < maximum; rowIndex++) {
      final row = grid.rows[rowIndex];
      final relevant = <Object?>[
        for (var column = startColumn; column <= endColumn; column++)
          _at(row, column),
      ];
      if (relevant.every(_isBlank)) {
        emptyRun++;
        if (emptyRun >= 5) break;
        continue;
      }
      emptyRun = 0;
      if (_looksLikeHeader(relevant)) break;

      if (dateColumn != null) {
        final rawDate = _at(row, dateColumn);
        final explicitDate = _parseDate(
          rawDate,
          sheetMonth: grid.monthHint,
          sheetYear: grid.yearHint,
        );
        if (explicitDate != null) {
          carriedDate = explicitDate;
        } else if (!_isBlank(rawDate)) {
          // A balance/formula in the date column marks the end of a ledger
          // run. Blank cells inherit the preceding date; non-date values do
          // not, otherwise analytical blocks become fake transactions.
          carriedDate = null;
        }
      }
      final date = dateColumn == null ? fallbackDate : carriedDate;
      if (date == null) continue;
      final descriptors = <String>[];
      String? category;
      String? merchant;
      String? typeText;
      String? currency;
      for (var column = startColumn; column <= endColumn; column++) {
        final value = _cleanText(_at(row, column));
        if (value == null) continue;
        final role = roles[column];
        if (role == _ColumnRole.category) {
          category ??= value;
          descriptors.add(value);
        } else if (role == _ColumnRole.description) {
          descriptors.add(value);
        } else if (role == _ColumnRole.merchant) {
          merchant ??= value;
          descriptors.add(value);
        } else if (role == _ColumnRole.type) {
          typeText = value;
        } else if (role == _ColumnRole.currency) {
          currency = value;
        } else if (column != dateColumn &&
            !amountColumns.contains(column) &&
            value.length > 1) {
          descriptors.add(value);
        }
      }
      final description = _bestDescription(
        descriptors,
        fallback: category ?? 'Операция из Excel',
      );
      if (_isSummaryLabel(description) ||
          (category != null && _isSummaryLabel(category))) {
        continue;
      }

      for (final amountColumn in amountColumns) {
        final rawAmount = _parseMoney(_at(row, amountColumn));
        if (rawAmount == null || rawAmount == 0) continue;
        final cellKey = '${grid.name}:$rowIndex:$amountColumn';
        if (!claimedCells.add(cellKey)) continue;
        final direction = _resolveDirection(
          headerRole: roles[amountColumn]!,
          rawAmount: rawAmount,
          sheetName:
              '${grid.name} ${_matrixHeaderContext(grid, headerRow, amountColumn)}',
          typeText: typeText,
          description: description,
        );
        result.add(
          _draft(
            fileName: fileName,
            grid: grid,
            row: rowIndex,
            column: amountColumn,
            date: date,
            rawAmount: rawAmount,
            direction: direction,
            description: description,
            merchant: merchant,
            category: category,
            currency: currency,
            aggregate: dateColumn == null,
          ),
        );
      }
    }
    return result;
  }

  List<_ExcelDraft> _parseMonthlyMatrices(
    _SheetGrid grid,
    String fileName,
    DateTime fallbackDate,
    Set<String> claimedCells,
  ) {
    final result = <_ExcelDraft>[];
    final limit = grid.rows.length < 220 ? grid.rows.length : 220;
    for (var headerRow = 0; headerRow < limit; headerRow++) {
      final row = grid.rows[headerRow];
      final monthColumns = <int, DateTime>{};
      for (var column = 0; column < row.length; column++) {
        final date = _parseMonthHeader(
          row[column],
          sheetYear: grid.yearHint,
          fallbackYear: fallbackDate.year,
          preferSheetYear: grid.yearIsExplicit,
        );
        if (date != null) monthColumns[column] = date;
      }
      if (monthColumns.length < 2) continue;
      final firstMonthColumn = monthColumns.keys.reduce(
        (left, right) => left < right ? left : right,
      );
      if (firstMonthColumn == 0) continue;
      final maximum = grid.rows.length < headerRow + 300
          ? grid.rows.length
          : headerRow + 300;
      if (!grid.yearIsExplicit) {
        final lastPopulatedMonth = _lastPopulatedMonth(
          grid.rows,
          headerRow + 1,
          maximum,
          monthColumns,
        );
        final inferredYear = lastPopulatedMonth > fallbackDate.month
            ? fallbackDate.year - 1
            : fallbackDate.year;
        for (final entry in monthColumns.entries.toList()) {
          monthColumns[entry.key] = DateTime(inferredYear, entry.value.month);
        }
      }
      var section = _textBefore(row, firstMonthColumn) ?? grid.name;
      var emptyRun = 0;
      for (var rowIndex = headerRow + 1; rowIndex < maximum; rowIndex++) {
        final dataRow = grid.rows[rowIndex];
        final labels = _textsBefore(dataRow, firstMonthColumn);
        final label = labels.isEmpty ? null : labels.last;
        final numericValues = monthColumns.entries
            .map((entry) => _parseMoney(_at(dataRow, entry.key)))
            .whereType<double>()
            .where((value) => value != 0)
            .length;
        if (label == null && numericValues == 0) {
          emptyRun++;
          if (emptyRun >= 4) break;
          continue;
        }
        emptyRun = 0;
        if (label != null && numericValues == 0) {
          if (!_isSummaryLabel(label)) section = label;
          continue;
        }
        if (label == null) continue;
        if (_isSummaryLabel(label)) {
          final parentLabels = labels
              .where((value) => !_isSummaryLabel(value))
              .toList();
          if (parentLabels.isNotEmpty) section = parentLabels.last;
          continue;
        }
        final direction = _resolveDirection(
          headerRole: _ColumnRole.amount,
          rawAmount: 1,
          sheetName: '${grid.name} $section',
          description: label,
        );
        for (final entry in monthColumns.entries) {
          final rawAmount = _parseMoney(_at(dataRow, entry.key));
          if (rawAmount == null || rawAmount == 0) continue;
          final cellKey = '${grid.name}:$rowIndex:${entry.key}';
          if (!claimedCells.add(cellKey)) continue;
          result.add(
            _draft(
              fileName: fileName,
              grid: grid,
              row: rowIndex,
              column: entry.key,
              date: entry.value,
              rawAmount: rawAmount,
              direction: direction,
              description: label,
              category: section == grid.name ? label : section,
              aggregate: true,
            ),
          );
        }
      }
    }
    return result;
  }

  List<_ExcelDraft> _parseCategoryMatrices(
    _SheetGrid grid,
    String fileName,
    DateTime fallbackDate,
    Set<String> claimedCells,
  ) {
    final result = <_ExcelDraft>[];
    final limit = grid.rows.length < 120 ? grid.rows.length : 120;
    for (var headerRow = 0; headerRow < limit; headerRow++) {
      final row = grid.rows[headerRow];
      final categoryColumns = <int, String>{};
      for (var column = 0; column < row.length; column++) {
        final label = _cleanText(row[column]);
        if (label == null ||
            _columnRole(label) != null ||
            _monthNumber(label) != null ||
            _isSummaryLabel(label)) {
          continue;
        }
        categoryColumns[column] = label;
      }
      if (categoryColumns.length < 3) continue;
      final distinctCategories = categoryColumns.values
          .map(_normalizeText)
          .toSet();
      if (distinctCategories.length < 3 ||
          distinctCategories.where(_looksLikeFinancialCategoryLabel).length <
              2) {
        continue;
      }
      final nextRow = headerRow + 1 < grid.rows.length
          ? grid.rows[headerRow + 1]
          : const <Object?>[];
      for (final column in categoryColumns.keys.toList()) {
        final subcategory = _cleanText(_at(nextRow, column));
        if (subcategory != null &&
            _columnRole(subcategory) == null &&
            _monthNumber(subcategory) == null &&
            !_isSummaryLabel(subcategory)) {
          categoryColumns[column] = subcategory;
        }
      }

      var matchedRows = 0;
      final maximum = grid.rows.length < headerRow + 400
          ? grid.rows.length
          : headerRow + 400;
      for (var rowIndex = headerRow + 1; rowIndex < maximum; rowIndex++) {
        final dataRow = grid.rows[rowIndex];
        DateTime? date;
        for (var column = 0; column < dataRow.length; column++) {
          if (categoryColumns.containsKey(column)) continue;
          date = _parseDate(
            dataRow[column],
            sheetMonth: grid.monthHint,
            sheetYear: grid.yearHint,
          );
          if (date != null) break;
        }
        if (date == null) continue;
        final populated = categoryColumns.keys
            .where((column) => _parseMoney(_at(dataRow, column)) != null)
            .length;
        if (populated < 2) continue;
        matchedRows++;
        final direction = _resolveDirection(
          headerRole: _ColumnRole.amount,
          rawAmount: 1,
          sheetName: grid.name,
          description: '',
        );
        for (final entry in categoryColumns.entries) {
          final rawAmount = _parseMoney(_at(dataRow, entry.key));
          if (rawAmount == null || rawAmount == 0) continue;
          final cellKey = '${grid.name}:$rowIndex:${entry.key}';
          if (!claimedCells.add(cellKey)) continue;
          result.add(
            _draft(
              fileName: fileName,
              grid: grid,
              row: rowIndex,
              column: entry.key,
              date: date,
              rawAmount: rawAmount,
              direction: direction,
              description: entry.value,
              category: entry.value,
              aggregate: true,
            ),
          );
        }
      }
      if (matchedRows > 0) break;
    }
    return result;
  }

  _ExcelDraft _draft({
    required String fileName,
    required _SheetGrid grid,
    required int row,
    required int column,
    required DateTime date,
    required double rawAmount,
    required _Direction direction,
    required String description,
    String? merchant,
    String? category,
    String? currency,
    bool aggregate = false,
  }) {
    final capitalKind = direction == _Direction.income
        ? null
        : _capitalKind('$category $description ${grid.name}');
    final resolved = capitalKind == null
        ? _kindFor(direction, description, rawAmount)
        : _ResolvedKind(
            capitalKind == StatementCapitalKind.investment
                ? StatementTransactionKind.investment
                : StatementTransactionKind.savings,
            false,
          );
    final amountMinor = (rawAmount.abs() * 100).round();
    return _ExcelDraft(
      sourceKey: '$fileName|${grid.name}|${row + 1}|${column + 1}',
      sheetName: grid.name,
      row: row + 1,
      column: column + 1,
      date: DateTime(date.year, date.month, date.day),
      amountMinor: resolved.isIncoming ? amountMinor : -amountMinor,
      kind: resolved.kind,
      isIncoming: resolved.isIncoming,
      description: description,
      merchant: merchant ?? description,
      category: category ?? description,
      currency: _normalizeCurrency(currency),
      aggregate: aggregate,
      capitalKind: capitalKind,
      capitalAccountName: capitalKind == null ? null : description,
    );
  }

  ParsedStatementTransaction _toStatementTransaction(
    _ExcelDraft draft,
    String fileName,
  ) {
    final category = classifier.classify('${draft.merchant} ${draft.category}');
    final id = 'excel-${_stableHash(draft.sourceKey)}';
    return ParsedStatementTransaction(
      id: id,
      operationDate: draft.date,
      processingDate: draft.date,
      authorizationCode: '${draft.sheetName}:${draft.row}:${draft.column}',
      bankCategory: draft.category,
      description:
          '${draft.description}${draft.aggregate ? ' · агрегировано за период' : ''}',
      merchant: draft.merchant,
      amountMinor: draft.amountMinor,
      balanceMinor: 0,
      kind: draft.kind,
      isIncoming: draft.isIncoming,
      category: category,
      confidence: draft.aggregate ? 0.68 : 0.84,
      currency: draft.currency,
      capitalKind: draft.capitalKind,
      capitalAccountName: draft.capitalAccountName,
    );
  }
}

void _validateExcelArchive(Uint8List bytes) {
  const endSignature = 0x06054b50;
  const centralSignature = 0x02014b50;
  const maximumEntries = 5000;
  const maximumUncompressedBytes = 100 * 1024 * 1024;
  final data = ByteData.sublistView(bytes);
  final firstPossibleEnd = bytes.length > 65557 ? bytes.length - 65557 : 0;
  int? endOffset;
  for (var offset = bytes.length - 22; offset >= firstPossibleEnd; offset--) {
    if (data.getUint32(offset, Endian.little) == endSignature) {
      endOffset = offset;
      break;
    }
  }
  if (endOffset == null) {
    throw const UnsupportedBankStatementException(
      'Excel-файл повреждён: не найдена структура XLSX',
    );
  }
  final entries = data.getUint16(endOffset + 10, Endian.little);
  final centralSize = data.getUint32(endOffset + 12, Endian.little);
  var offset = data.getUint32(endOffset + 16, Endian.little);
  if (entries > maximumEntries || offset + centralSize > bytes.length) {
    throw const UnsupportedBankStatementException(
      'Excel-файл содержит слишком много данных',
    );
  }

  var uncompressedTotal = 0;
  for (var entry = 0; entry < entries; entry++) {
    if (offset + 46 > bytes.length ||
        data.getUint32(offset, Endian.little) != centralSignature) {
      throw const UnsupportedBankStatementException(
        'Excel-файл повреждён: неверная структура XLSX',
      );
    }
    final versionMadeBy = data.getUint16(offset + 4, Endian.little);
    final generalPurposeFlags = data.getUint16(offset + 8, Endian.little);
    final compressionMethod = data.getUint16(offset + 10, Endian.little);
    final externalAttributes = data.getUint32(offset + 38, Endian.little);
    final creatorSystem = versionMadeBy >> 8;
    final unixFileType = (externalAttributes >> 16) & 0xf000;
    if ((generalPurposeFlags & 0x1) != 0) {
      throw const UnsupportedBankStatementException(
        'Зашифрованные Excel-архивы не поддерживаются',
      );
    }
    if (compressionMethod != 0 && compressionMethod != 8) {
      throw const UnsupportedBankStatementException(
        'Excel-файл использует неподдерживаемый метод ZIP-сжатия',
      );
    }
    if (creatorSystem == 3 && unixFileType == 0xa000) {
      throw const UnsupportedBankStatementException(
        'Символические ссылки внутри Excel-архива запрещены',
      );
    }
    final uncompressed = data.getUint32(offset + 24, Endian.little);
    if (uncompressed == 0xffffffff) {
      throw const UnsupportedBankStatementException(
        'ZIP64 Excel-файлы не поддерживаются',
      );
    }
    uncompressedTotal += uncompressed;
    if (uncompressedTotal > maximumUncompressedBytes) {
      throw const UnsupportedBankStatementException(
        'Распакованный Excel-файл не должен превышать 100 МБ',
      );
    }
    final nameLength = data.getUint16(offset + 28, Endian.little);
    final extraLength = data.getUint16(offset + 30, Endian.little);
    final commentLength = data.getUint16(offset + 32, Endian.little);
    offset += 46 + nameLength + extraLength + commentLength;
  }

  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.length > maximumEntries) {
      throw const UnsupportedBankStatementException(
        'Excel-файл содержит слишком много архивных элементов',
      );
    }
    var actualUncompressedTotal = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final counter = _LimitedArchiveOutput(
        maximumBytes: maximumUncompressedBytes - actualUncompressedTotal,
      );
      entry.writeContent(counter);
      actualUncompressedTotal += counter.length;
    }
  } on UnsupportedBankStatementException {
    rethrow;
  } on Object {
    throw const UnsupportedBankStatementException(
      'Excel-файл повреждён или использует неподдерживаемое ZIP-сжатие',
    );
  }
}

class _LimitedArchiveOutput extends OutputStream {
  _LimitedArchiveOutput({required this.maximumBytes})
    : super(byteOrder: ByteOrder.littleEndian);

  final int maximumBytes;

  @override
  int length = 0;

  void _add(int count) {
    if (count < 0 || length + count > maximumBytes) {
      throw const UnsupportedBankStatementException(
        'Фактически распакованный Excel-файл не должен превышать 100 МБ',
      );
    }
    length += count;
  }

  @override
  void clear() => length = 0;

  @override
  void flush() {}

  @override
  Uint8List subset(int start, [int? end]) => Uint8List(0);

  @override
  void writeByte(int value) => _add(1);

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (count > bytes.length) {
      throw const UnsupportedBankStatementException(
        'Excel-файл содержит повреждённый поток данных',
      );
    }
    _add(count);
  }

  @override
  void writeStream(InputStream stream) => _add(stream.length);
}

ParsedBankStatement _parseExcelIsolate(Map<String, Object?> input) {
  final referenceMilliseconds = input['referenceDate'] as int?;
  return const UniversalExcelStatementAdapter().parse(
    bytes: input['bytes']! as Uint8List,
    fileName: input['fileName']! as String,
    referenceDate: referenceMilliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(referenceMilliseconds),
    yearOverride: input['yearOverride'] as int?,
  );
}

int? _workbookExplicitYear(Excel workbook) {
  final counts = <int, int>{};
  void add(int? year) {
    if (year == null) return;
    counts.update(year, (value) => value + 1, ifAbsent: () => 1);
  }

  for (final entry in workbook.tables.entries) {
    add(_yearNumber(entry.key));
    for (final row in entry.value.rows.take(160)) {
      for (final cell in row.take(40)) {
        final value = _excelValue(cell?.value);
        if (value is String) add(_yearNumber(value));
      }
    }
  }
  if (counts.isEmpty) return null;
  if (counts.length > 1) return null;
  return counts.keys.single;
}

int? _yearNumber(Object? value) {
  final text = _normalizeText(value);
  final full = RegExp(r'\b(20\d{2})\b').firstMatch(text);
  final fullYear = _plausibleYear(full?.group(1));
  if (fullYear != null) return fullYear;
  final numericSuffix = RegExp(
    r'(?:^|\D)(?:0?[1-9]|1[0-2])[.\-_/](\d{2})(?:\D|$)',
  ).firstMatch(text);
  final suffix = int.tryParse(numericSuffix?.group(1) ?? '');
  if (suffix != null) return 2000 + suffix;
  if (_monthNumber(text) != null) {
    final shortMatches = RegExp(
      r'(?:^|\D)(\d{2})(?:\D|$)',
    ).allMatches(text).toList();
    final short = shortMatches.isEmpty ? null : shortMatches.last;
    final year = int.tryParse(short?.group(1) ?? '');
    if (year != null) return 2000 + year;
  }
  return null;
}

int? _plausibleYear(Object? value) {
  final year = value is int ? value : int.tryParse('$value');
  return year != null && year >= 2010 && year <= 2100 ? year : null;
}

enum _ColumnRole {
  date,
  amount,
  expenseAmount,
  incomeAmount,
  category,
  description,
  merchant,
  type,
  currency,
}

enum _Direction { expense, income, signed }

class _ResolvedKind {
  const _ResolvedKind(this.kind, this.isIncoming);

  final StatementTransactionKind kind;
  final bool isIncoming;
}

class _ExcelDraft {
  const _ExcelDraft({
    required this.sourceKey,
    required this.sheetName,
    required this.row,
    required this.column,
    required this.date,
    required this.amountMinor,
    required this.kind,
    required this.isIncoming,
    required this.description,
    required this.merchant,
    required this.category,
    required this.currency,
    required this.aggregate,
    required this.capitalKind,
    required this.capitalAccountName,
  });

  final String sourceKey;
  final String sheetName;
  final int row;
  final int column;
  final DateTime date;
  final int amountMinor;
  final StatementTransactionKind kind;
  final bool isIncoming;
  final String description;
  final String merchant;
  final String category;
  final String currency;
  final bool aggregate;
  final StatementCapitalKind? capitalKind;
  final String? capitalAccountName;
}

class _DateEntry {
  const _DateEntry(this.column, this.date);

  final int column;
  final DateTime date;
}

class _RowPeriodColumn {
  const _RowPeriodColumn({
    required this.column,
    required this.description,
    required this.direction,
    required this.capitalKind,
    required this.isTotal,
  });

  final int column;
  final String description;
  final _Direction direction;
  final StatementCapitalKind? capitalKind;
  final bool isTotal;
}

class _SheetGrid {
  const _SheetGrid({
    required this.name,
    required this.rows,
    required this.yearHint,
    required this.monthHint,
    required this.yearIsExplicit,
  });

  factory _SheetGrid.fromSheet(
    String name,
    Sheet sheet,
    DateTime fallbackDate, {
    int? forcedYear,
    int? defaultYear,
  }) {
    final rows = <List<Object?>>[];
    final maximumRows = sheet.maxRows < 10000 ? sheet.maxRows : 10000;
    final maximumColumns = sheet.maxColumns < 80 ? sheet.maxColumns : 80;
    for (var row = 0; row < maximumRows; row++) {
      final values = <Object?>[];
      final source = row < sheet.rows.length
          ? sheet.rows[row]
          : const <Data?>[];
      for (var column = 0; column < maximumColumns; column++) {
        values.add(
          column < source.length ? _excelValue(source[column]?.value) : null,
        );
      }
      while (values.isNotEmpty && _isBlank(values.last)) {
        values.removeLast();
      }
      rows.add(values);
    }
    while (rows.isNotEmpty && rows.last.every(_isBlank)) {
      rows.removeLast();
    }
    final normalizedName = _normalizeText(name);
    final nameYear = _yearNumber(normalizedName);
    int? contentYear;
    for (final row in rows.take(80)) {
      for (final value in row.take(30)) {
        if (value is DateTime && _plausibleYear(value.year) != null) {
          contentYear = value.year;
          break;
        }
        if (value is String) {
          final match = RegExp(r'\b(20\d{2})\b').firstMatch(value);
          final candidate = _plausibleYear(match?.group(1));
          if (candidate != null) {
            contentYear = candidate;
            break;
          }
        }
      }
      if (contentYear != null) break;
    }
    final explicitYear = forcedYear ?? nameYear ?? contentYear;
    final year = explicitYear ?? defaultYear ?? fallbackDate.year;
    return _SheetGrid(
      name: name,
      rows: rows,
      yearHint: year,
      monthHint: _monthNumber(name),
      yearIsExplicit: explicitYear != null,
    );
  }

  final String name;
  final List<List<Object?>> rows;
  final int yearHint;
  final int? monthHint;
  final bool yearIsExplicit;

  bool get isSummaryLike => RegExp(
    r'дашборд|dashboard|граф|свод|отч[её]т|статист|инструк|настрой|шаблон|справоч|диаграм',
  ).hasMatch(_normalizeText(name));
}

Object? _excelValue(CellValue? value) => switch (value) {
  null => null,
  TextCellValue() => value.value.toString(),
  IntCellValue() => value.value,
  DoubleCellValue() => value.value,
  DateCellValue() => value.asDateTimeLocal(),
  DateTimeCellValue() => value.asDateTimeLocal(),
  BoolCellValue() => value.value,
  TimeCellValue() => value.asDuration(),
  FormulaCellValue() => _numericFormulaValue(value.formula),
};

/// Excel readers do not always expose a cached value for formula cells. User
/// budget sheets commonly use small arithmetic formulas inside leaf rows (for
/// example `=1335+1889`). Evaluating only number/operator expressions keeps
/// those amounts without attempting to implement Excel or follow cell links.
double? _numericFormulaValue(String formula) {
  final expression = formula.trim().replaceFirst(RegExp(r'^='), '');
  if (expression.isEmpty ||
      !RegExp(r'^[0-9\s.,+\-*/()]+$').hasMatch(expression)) {
    return null;
  }
  try {
    final parser = _NumericFormulaParser(expression.replaceAll(',', '.'));
    final result = parser.parse();
    return result.isFinite ? result : null;
  } on FormatException {
    return null;
  }
}

class _NumericFormulaParser {
  _NumericFormulaParser(this.source);

  final String source;
  var index = 0;

  double parse() {
    final value = _expression();
    _skipSpaces();
    if (index != source.length) throw const FormatException();
    return value;
  }

  double _expression() {
    var value = _term();
    while (true) {
      _skipSpaces();
      if (_take('+')) {
        value += _term();
      } else if (_take('-')) {
        value -= _term();
      } else {
        return value;
      }
    }
  }

  double _term() {
    var value = _factor();
    while (true) {
      _skipSpaces();
      if (_take('*')) {
        value *= _factor();
      } else if (_take('/')) {
        final divisor = _factor();
        if (divisor == 0) throw const FormatException();
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  double _factor() {
    _skipSpaces();
    if (_take('+')) return _factor();
    if (_take('-')) return -_factor();
    if (_take('(')) {
      final value = _expression();
      _skipSpaces();
      if (!_take(')')) throw const FormatException();
      return value;
    }
    final start = index;
    while (index < source.length && RegExp(r'[0-9.]').hasMatch(source[index])) {
      index++;
    }
    if (start == index) throw const FormatException();
    final value = double.tryParse(source.substring(start, index));
    if (value == null) throw const FormatException();
    return value;
  }

  bool _take(String token) {
    if (index >= source.length || source[index] != token) return false;
    index++;
    return true;
  }

  void _skipSpaces() {
    while (index < source.length && source[index].trim().isEmpty) {
      index++;
    }
  }
}

_ColumnRole? _columnRole(Object? value) {
  final text = _normalizeText(value);
  if (text.isEmpty || _isSummaryLabel(text)) return null;
  if (RegExp(r'(^|\s)(дата|date|день|число)(\s|$)').hasMatch(text)) {
    return _ColumnRole.date;
  }
  if (text.contains('валют')) return _ColumnRole.currency;
  if (RegExp(r'магазин|merchant|получатель|контрагент|место').hasMatch(text)) {
    return _ColumnRole.merchant;
  }
  if (RegExp(
    r'описан|комментар|назначен|наименован|подробн|операция|детал|примечан',
  ).hasMatch(text)) {
    return _ColumnRole.description;
  }
  if (text.contains('подкатегор') ||
      text.contains('категор') ||
      text.contains('вид актива') ||
      text == 'статья') {
    return _ColumnRole.category;
  }
  if (RegExp(
    r'(^|\s)(тип|вид)(\s|$)|доход.?расход|приход.?расход',
  ).hasMatch(text)) {
    return _ColumnRole.type;
  }
  if (RegExp(r'доход|приход|зачислен').hasMatch(text) &&
      !text.contains('убыт')) {
    return _ColumnRole.incomeAmount;
  }
  if (RegExp(r'расход|трат|списан|стоимост').hasMatch(text)) {
    return _ColumnRole.expenseAmount;
  }
  if (RegExp(r'(^|\s)(сумма|amount)(\s|$)|доход.?убыт').hasMatch(text)) {
    return _ColumnRole.amount;
  }
  return null;
}

bool _isAmountRole(_ColumnRole role) =>
    role == _ColumnRole.amount ||
    role == _ColumnRole.expenseAmount ||
    role == _ColumnRole.incomeAmount;

_Direction _resolveDirection({
  required _ColumnRole headerRole,
  required double rawAmount,
  required String sheetName,
  required String description,
  String? typeText,
}) {
  if (headerRole == _ColumnRole.expenseAmount) return _Direction.expense;
  if (headerRole == _ColumnRole.incomeAmount) return _Direction.income;
  final context = _normalizeText('$sheetName ${typeText ?? ''} $description');
  if (RegExp(r'расход|трат|покуп|списан|плат[её]ж').hasMatch(context)) {
    return _Direction.expense;
  }
  if (RegExp(r'доход|приход|зачислен|зарплат|пополнен').hasMatch(context)) {
    return _Direction.income;
  }
  return rawAmount < 0 ? _Direction.signed : _Direction.expense;
}

_ResolvedKind _kindFor(
  _Direction direction,
  String description,
  double rawAmount,
) {
  final normalized = _normalizeText(description);
  if (normalized.contains('возврат')) {
    return const _ResolvedKind(StatementTransactionKind.refund, true);
  }
  final incoming = switch (direction) {
    _Direction.income => rawAmount >= 0,
    _Direction.expense => rawAmount < 0,
    _Direction.signed => rawAmount >= 0,
  };
  if (normalized.contains('перевод') && direction == _Direction.signed) {
    return _ResolvedKind(StatementTransactionKind.transfer, incoming);
  }
  return incoming
      ? const _ResolvedKind(StatementTransactionKind.income, true)
      : const _ResolvedKind(StatementTransactionKind.expense, false);
}

StatementCapitalKind? _capitalKind(String context) {
  final value = _normalizeText(context);
  if (RegExp(r'депозит|вклад').hasMatch(value)) {
    return StatementCapitalKind.deposit;
  }
  if (RegExp(r'накоплен|сбережен|копилк|резерв').hasMatch(value)) {
    return StatementCapitalKind.savings;
  }
  if (RegExp(
    r'инвест|крипт|биткоин|bitcoin|ethereum|эфир|брокер|финам|акци[ия]|облигац|etf|ценн(ая|ые) бумаг',
  ).hasMatch(value)) {
    return StatementCapitalKind.investment;
  }
  return null;
}

bool _looksLikeFinancialCategoryLabel(String value) {
  final normalized = _normalizeText(value).replaceAll('ё', 'е');
  if (_capitalKind(normalized) != null) return true;
  return RegExp(
    r'продукт|еда|кафе|ресторан|достав|транспорт|такси|проезд|авто|бенз|здоров|лекар|аптек|гигиен|кредит|ипотек|аренд|жиль|коммун|связ|интернет|телефон|подпис|развлеч|путеше|отдых|шоп|одеж|подар|маркетплейс|дом|быт|образован|дети|родител|налог|страхов|спорт|зарплат|фриланс|кэшб|перевод',
  ).hasMatch(normalized);
}

_DateEntry? _dateEntryInRow(_SheetGrid grid, List<Object?> row) {
  for (var column = 0; column < row.length; column++) {
    final value = row[column];
    if (value is DateTime) return _DateEntry(column, value);
    if (value is! String || !RegExp(r'\d{1,2}[.\-/]\d{1,2}').hasMatch(value)) {
      continue;
    }
    final parsed = _parseDate(
      value,
      sheetMonth: grid.monthHint,
      sheetYear: grid.yearHint,
    );
    if (parsed != null) return _DateEntry(column, parsed);
  }
  return null;
}

DateTime? _columnPeriodDate(
  Object? value, {
  required int? sheetMonth,
  required int sheetYear,
}) {
  if (sheetMonth == null) return null;
  if (value is DateTime) {
    final year = _plausibleYear(value.year) ?? sheetYear;
    return DateTime(year, value.month, value.day);
  }
  if (value is num && value == value.roundToDouble()) {
    final day = value.toInt();
    final maximum = DateTime(sheetYear, sheetMonth + 1, 0).day;
    if (day >= 1 && day <= maximum) {
      return DateTime(sheetYear, sheetMonth, day);
    }
  }
  final text = _cleanText(value);
  if (text == null || _monthNumber(text) != null) return null;
  final week = RegExp(
    r'(?:^|\s)(?:с\s*)?(\d{1,2})\s*(?:по|[-–—])\s*(\d{1,2})(?:\s|$)',
  ).firstMatch(_normalizeText(text));
  if (week != null) {
    final day = int.parse(week.group(1)!);
    final maximum = DateTime(sheetYear, sheetMonth + 1, 0).day;
    if (day >= 1 && day <= maximum) {
      return DateTime(sheetYear, sheetMonth, day);
    }
  }
  final exactDay = int.tryParse(text);
  if (exactDay != null) {
    final maximum = DateTime(sheetYear, sheetMonth + 1, 0).day;
    if (exactDay >= 1 && exactDay <= maximum) {
      return DateTime(sheetYear, sheetMonth, exactDay);
    }
  }
  if (RegExp(r'\d{1,2}[.\-/]\d{1,2}').hasMatch(text)) {
    return _parseDate(text, sheetMonth: sheetMonth, sheetYear: sheetYear);
  }
  return null;
}

int? _nearestTextColumnBefore(List<Object?> row, int beforeColumn) {
  for (var column = beforeColumn - 1; column >= 0; column--) {
    final label = _cleanText(_at(row, column));
    if (label == null || _isSummaryLabel(label)) continue;
    return column;
  }
  return null;
}

String _matrixHeaderContext(_SheetGrid grid, int headerRow, int column) {
  final parts = <String>[];
  final seen = <String>{};
  final start = headerRow < 4 ? 0 : headerRow - 4;
  for (var rowIndex = start; rowIndex <= headerRow; rowIndex++) {
    final row = grid.rows[rowIndex];
    String? value;
    for (
      var candidate = column;
      candidate >= 0 && candidate >= column - 10;
      candidate--
    ) {
      value = _cleanText(_at(row, candidate));
      if (value != null) break;
    }
    if (value == null) continue;
    final normalized = _normalizeText(value);
    if (seen.add(normalized)) parts.add(value);
  }
  return parts.join(' · ');
}

String _matrixHeaderLabel(_SheetGrid grid, int headerRow, int column) {
  final direct = _cleanText(_at(grid.rows[headerRow], column));
  if (direct != null &&
      !RegExp(
        r'^(факт|сумма|итог|итого|за месяц|за период)$',
      ).hasMatch(_normalizeText(direct))) {
    return direct;
  }
  final context = _matrixHeaderContext(grid, headerRow, column);
  final parts = context.split(' · ').reversed;
  for (final part in parts) {
    if (!RegExp(
      r'^(факт|сумма|итог|итого|за месяц|за период|доход|расходы?)$',
    ).hasMatch(_normalizeText(part))) {
      return part;
    }
  }
  return direct ?? 'Операция из Excel';
}

DateTime? _parseDate(
  Object? value, {
  required int? sheetMonth,
  required int sheetYear,
}) {
  if (value is DateTime) return value;
  if (value is num && sheetMonth != null && value >= 1 && value <= 31) {
    final day = value.round();
    final maximum = DateTime(sheetYear, sheetMonth + 1, 0).day;
    if (day <= maximum) return DateTime(sheetYear, sheetMonth, day);
  }
  final text = _cleanText(value);
  if (text == null) return null;
  final numeric = RegExp(
    r'\b(\d{1,2})[.\-/](\d{1,2})(?:[.\-/](\d{2,4}))?\b',
  ).firstMatch(text);
  if (numeric != null) {
    var year = int.tryParse(numeric.group(3) ?? '') ?? sheetYear;
    if (year < 100) year += 2000;
    final first = int.parse(numeric.group(1)!);
    final second = int.parse(numeric.group(2)!);
    // Budget templates exported from different locales may contain both
    // dd/mm/yyyy and mm/dd/yyyy. The month encoded in the sheet title is the
    // reliable discriminator when only one side matches it.
    final firstIsSheetMonth = sheetMonth != null && first == sheetMonth;
    final secondIsSheetMonth = sheetMonth != null && second == sheetMonth;
    final month = firstIsSheetMonth && !secondIsSheetMonth ? first : second;
    final day = firstIsSheetMonth && !secondIsSheetMonth ? second : first;
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      final maximum = DateTime(year, month + 1, 0).day;
      if (day <= maximum) return DateTime(year, month, day);
    }
  }
  if (sheetMonth != null) {
    final day = int.tryParse(text);
    if (day != null && day >= 1 && day <= 31) {
      return DateTime(sheetYear, sheetMonth, day);
    }
  }
  return null;
}

DateTime? _parseMonthHeader(
  Object? value, {
  required int sheetYear,
  required int fallbackYear,
  bool preferSheetYear = false,
}) {
  if (value is DateTime) {
    final year = preferSheetYear
        ? sheetYear
        : (_plausibleYear(value.year) ?? sheetYear);
    return DateTime(year, value.month);
  }
  final text = _cleanText(value);
  if (text == null) return null;
  final month = _monthNumber(text);
  if (month == null) return null;
  final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(text);
  final year =
      int.tryParse(yearMatch?.group(1) ?? '') ??
      (_plausibleYear(sheetYear) ?? fallbackYear);
  return DateTime(year, month);
}

int? _monthNumber(Object? value) {
  final text = _normalizeText(value).replaceAll('ё', 'е');
  final numericMonth = RegExp(
    r'(?:^|\D)(0?[1-9]|1[0-2])[.\-/](?:20)?\d{2}(?:\D|$)',
  ).firstMatch(text);
  if (numericMonth != null) return int.parse(numericMonth.group(1)!);
  const names = <String, int>{
    'январ': 1,
    'феврал': 2,
    'март': 3,
    'апрел': 4,
    'май': 5,
    'мая': 5,
    'июн': 6,
    'июл': 7,
    'август': 8,
    'сентябр': 9,
    'октябр': 10,
    'ноябр': 11,
    'декабр': 12,
    'january': 1,
    'february': 2,
    'march': 3,
    'april': 4,
    'june': 6,
    'july': 7,
    'august': 8,
    'september': 9,
    'october': 10,
    'november': 11,
    'december': 12,
  };
  for (final entry in names.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return null;
}

double? _parseMoney(Object? value) {
  if (value is num) return value.toDouble();
  final text = _cleanText(value);
  if (text == null || text.startsWith('=')) return null;
  var normalized = text
      .replaceAll('\u00a0', '')
      .replaceAll(' ', '')
      .replaceAll('₽', '')
      .replaceAll('руб.', '')
      .replaceAll('руб', '')
      .replaceAll(RegExp(r'[^0-9,\.\-+()]'), '');
  if (normalized.isEmpty) return null;
  final negativeByParentheses =
      normalized.startsWith('(') && normalized.endsWith(')');
  normalized = normalized.replaceAll('(', '').replaceAll(')', '');
  if (normalized.contains(',') && normalized.contains('.')) {
    if (normalized.lastIndexOf(',') > normalized.lastIndexOf('.')) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else {
      normalized = normalized.replaceAll(',', '');
    }
  } else if (normalized.contains(',')) {
    normalized = normalized.replaceAll(',', '.');
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || !parsed.isFinite) return null;
  return negativeByParentheses ? -parsed.abs() : parsed;
}

String _bestDescription(List<String> values, {required String fallback}) {
  final unique = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final normalized = _normalizeText(value);
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    unique.add(value.trim());
  }
  if (unique.isEmpty) return fallback;
  unique.sort((a, b) => b.length.compareTo(a.length));
  return unique.first;
}

String? _textBefore(List<Object?> row, int beforeColumn) {
  for (var column = beforeColumn - 1; column >= 0; column--) {
    final value = _cleanText(_at(row, column));
    if (value != null) return value;
  }
  return null;
}

List<String> _textsBefore(List<Object?> row, int beforeColumn) {
  final result = <String>[];
  for (var column = 0; column < beforeColumn; column++) {
    final value = _cleanText(_at(row, column));
    if (value != null) result.add(value);
  }
  return result;
}

int _lastPopulatedMonth(
  List<List<Object?>> rows,
  int startRow,
  int endRow,
  Map<int, DateTime> monthColumns,
) {
  var lastMonth = 1;
  for (final entry in monthColumns.entries) {
    for (var row = startRow; row < endRow; row++) {
      final amount = _parseMoney(_at(rows[row], entry.key));
      if (amount != null && amount != 0) {
        if (entry.value.month > lastMonth) lastMonth = entry.value.month;
        break;
      }
    }
  }
  return lastMonth;
}

bool _looksLikeHeader(List<Object?> values) {
  var roles = 0;
  for (final value in values) {
    if (_columnRole(value) != null) roles++;
  }
  return roles >= 2;
}

bool _isSummaryLabel(Object? value) {
  final text = _normalizeText(value);
  if (text.isEmpty) return false;
  return RegExp(
    r'(^|\s)(итого|всего|total|grand total|сальдо|остаток|средн|план|бюджет|прогноз|проверка|дельта|начальная сумма|конечный капитал|предполагаемые|фактические|разница|доля,?\s*%|№|п/п|срок)(\s|:|$)',
  ).hasMatch(text);
}

String _normalizeCurrency(String? value) {
  final text = _normalizeText(value).toUpperCase();
  if (text.contains('USD') || text.contains(r'$')) return 'USD';
  if (text.contains('EUR') || text.contains('€')) return 'EUR';
  return 'RUB';
}

String? _cleanText(Object? value) {
  if (value == null || value is bool || value is Duration) return null;
  if (value is num || value is DateTime) return null;
  final text = '$value'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty || RegExp(r'^[-–—?]+$').hasMatch(text)) return null;
  return text;
}

String _normalizeText(Object? value) => '$value'
    .replaceAll('\u00a0', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

bool _isBlank(Object? value) =>
    value == null || (value is String && value.trim().isEmpty);

Object? _at(List<Object?> row, int column) =>
    column >= 0 && column < row.length ? row[column] : null;

String _stableHash(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
