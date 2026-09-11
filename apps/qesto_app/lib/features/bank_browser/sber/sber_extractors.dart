import 'dart:convert';

import '../../../data/models/qesto_models.dart';
import '../runtime/browser_controller.dart';
import 'sber_connector_models.dart';
import 'sber_readiness.dart';

class SberExtractors {
  const SberExtractors({this.readiness = const SberReadiness()});

  final SberReadiness readiness;

  Future<List<SberAccountFact>> accounts(BrowserController browser) async {
    final raw = await browser.evaluateConnectorJavascript(_accountsScript);
    if (raw is! String) return const [];
    return normalizeAccountRows(_decodeRows(raw));
  }

  List<SberAccountFact> normalizeAccountRows(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final normalized = rows
        .map(_accountFromRow)
        .whereType<SberAccountFact>()
        .toList(growable: false);
    return mergeAccounts(normalized);
  }

  List<SberAccountFact> mergeAccounts(Iterable<SberAccountFact> facts) {
    final normalized = facts.toList();
    final result = <SberAccountFact>[];
    for (final incoming in normalized) {
      final index = result.indexWhere(
        (existing) =>
            existing.id == incoming.id ||
            (_accountsAreDirectlyLinked(existing, incoming) &&
                normalized
                        .where(
                          (other) =>
                              other.id != existing.id &&
                              _accountsAreDirectlyLinked(other, existing),
                        )
                        .map((a) => a.id)
                        .toSet()
                        .length <=
                    1 &&
                normalized
                        .where(
                          (other) =>
                              other.id != incoming.id &&
                              _accountsAreDirectlyLinked(other, incoming),
                        )
                        .map((a) => a.id)
                        .toSet()
                        .length <=
                    1),
      );
      if (index < 0) {
        result.add(incoming);
      } else {
        result[index] = _mergeAccountFacts(result[index], incoming);
      }
    }
    return result;
  }

  Future<void> hydratePage(
    BrowserController browser, {
    int maxSteps = 24,
  }) async {
    if (!await readiness.wait(browser)) return;
    var stationary = 0;
    for (var step = 0; step < maxSteps; step++) {
      if (!await readiness.wait(browser)) break;
      final moved = await browser.evaluateConnectorJavascript(
        _hydrationScrollScript,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (moved == '1') {
        stationary = 0;
      } else {
        stationary += 1;
        if (stationary >= 2) break;
      }
    }
    await browser.evaluateConnectorJavascript(_scrollToTopScript);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<SberTransactionExtraction> transactions(
    BrowserController browser, {
    required SberSyncRange range,
    int maxScrolls = 160,
    Duration? maxDuration,
  }) async {
    final elapsed = Stopwatch()..start();
    final byFingerprint = <String, SberTransactionFact>{};
    final transactionKeyByObservation = <String, String>{};
    final rawFingerprints = <String>{};
    final diagnostics = <String, SberHistoryRowDiagnostic>{};
    final loyaltyFingerprints = <String>{};
    var previousRawCount = -1;
    var scrollSteps = 0;
    var loadMoreClicks = 0;
    var reachedRangeStart = false;
    var stationaryEndAttempts = 0;
    var observedStableEnd = false;
    bool observeRows(List<Map<String, dynamic>> rows) {
      var advanced = false;
      for (final row in rows) {
        final rawFingerprint = _rawRowFingerprint(row);
        advanced = rawFingerprints.add(rawFingerprint) || advanced;
        final observedDate = _rowDate(row);
        if (observedDate != null && observedDate.isBefore(range.from)) {
          reachedRangeStart = true;
        }
        if (row['loyaltyAmount'] is num || row['nonCashKind'] == 'reward') {
          loyaltyFingerprints.add(rawFingerprint);
        }
        final transaction = _transactionFromRow(row, range);
        final decision = _diagnoseRow(row, range, transaction);
        final previous = diagnostics[rawFingerprint];
        advanced =
            (previous?.outcome.isError == true && !decision.outcome.isError) ||
            advanced;
        // Every read is an observation, including pagination-wait probes.
        // Virtualized rows can disappear before the next main-loop read.
        if (previous?.outcome != SberHistoryRowOutcome.accepted ||
            decision.outcome == SberHistoryRowOutcome.accepted) {
          diagnostics[rawFingerprint] = decision;
        }
        if (transaction != null) {
          final previousKey = transactionKeyByObservation[rawFingerprint];
          if (previousKey != null && previousKey != transaction.fingerprint) {
            byFingerprint.remove(previousKey);
          }
          transactionKeyByObservation[rawFingerprint] = transaction.fingerprint;
          byFingerprint[transaction.fingerprint] = transaction;
        }
      }
      return advanced;
    }

    // The SPA may restore its last scroll offset. Starting there can skip the
    // newest part of the selected period and immediately hit its old boundary.
    if (!await readiness.wait(browser)) {
      return const SberTransactionExtraction(hasMoreRows: true);
    }
    await browser.evaluateConnectorJavascript(_scrollToTopScript);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    for (var index = 0; index < maxScrolls; index++) {
      if (maxDuration != null && elapsed.elapsed >= maxDuration) break;
      if (reachedRangeStart) break;
      if (!await readiness.wait(browser)) break;
      final raw = await browser.evaluateConnectorJavascript(
        _transactionsScript,
      );
      if (raw is String) {
        observeRows(_decodeRows(raw));
      }
      final grew = rawFingerprints.length > previousRawCount;
      if (grew) {
        stationaryEndAttempts = 0;
      }
      previousRawCount = rawFingerprints.length;
      if (reachedRangeStart) break;

      // Walk the rendered history in small, overlapping steps. Sber
      // virtualizes this list: jumping straight to the last row or to an
      // off-screen "Показать ещё" button unmounts intermediate operations
      // before the extractor can observe them.
      final moved = await browser.evaluateConnectorJavascript(_scrollScript);
      if (moved is String && moved == '1') {
        scrollSteps += 1;
        stationaryEndAttempts = 0;
        // Sber lazy-renders the next portion of the operation history. A short
        // delay races that render and used to make the connector stop after
        // the first few rows.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        continue;
      }

      // Pagination is safe only after the incremental walk reaches the end
      // of the currently rendered page. The JS side clicks only a rendered,
      // enabled read-only history control and never a financial action.
      {
        final loadedMore = await browser
            .evaluateConnectorJavascript(_loadMoreTransactionsScript)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (loadedMore == '1') {
          loadMoreClicks += 1;
          stationaryEndAttempts = 0;
          final advanced = await _waitForHistoryAdvance(
            browser,
            observeRows: observeRows,
          );
          if (advanced) {
            continue;
          }
          // A slow request is not permission to click the same control again.
          // Keep observed rows and report partial coverage after the deadline.
          break;
        }
      }

      // A virtualized list can report the same scroll position while a new
      // page is still being mounted. Require several stable observations
      // before declaring the selected period exhausted.
      if (!await readiness.wait(browser)) break;
      stationaryEndAttempts += 1;
      if (stationaryEndAttempts >= 3) {
        observedStableEnd = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    final result = byFingerprint.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final hasMore = await browser
        .evaluateConnectorJavascript(_hasMoreTransactionsScript)
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    return SberTransactionExtraction(
      transactions: result,
      rawRowsSeen: rawFingerprints.length,
      rejectedRows: diagnostics.values.where((d) => d.outcome.isError).length,
      scrollSteps: scrollSteps,
      loadMoreClicks: loadMoreClicks,
      rewardRows: diagnostics.values
          .where((d) => d.outcome == SberHistoryRowOutcome.reward)
          .length,
      serviceRows: diagnostics.values
          .where((d) => d.outcome == SberHistoryRowOutcome.service)
          .length,
      outsidePeriodRows: diagnostics.values
          .where((d) => d.outcome == SberHistoryRowOutcome.outsidePeriod)
          .length,
      diagnostics: diagnostics.values.toList(growable: false),
      loyaltyRewards: loyaltyFingerprints.length,
      rangeBoundaryReached: reachedRangeStart,
      // Timeout/unknown is not proof of a fully traversed history.
      hasMoreRows: !reachedRangeStart && (!observedStableEnd || hasMore != '0'),
    );
  }

  Future<bool> _waitForHistoryAdvance(
    BrowserController browser, {
    required bool Function(List<Map<String, dynamic>>) observeRows,
  }) async {
    final elapsed = Stopwatch()..start();
    var advanced = false;
    while (elapsed.elapsed < readiness.timeout) {
      await Future<void>.delayed(readiness.pollInterval);
      final state = await readiness.probe(browser);
      if (state == 'auth' || state == 'blocked') return false;
      final raw = await browser
          .evaluateConnectorJavascript(_transactionsScript)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (raw is! String) continue;
      advanced = observeRows(_decodeRows(raw)) || advanced;
      if (advanced && state == 'ready') return true;
    }
    return false;
  }

  Future<List<SberTransactionFact>> visibleTransactions(
    BrowserController browser, {
    required SberSyncRange range,
  }) async {
    final raw = await browser.evaluateConnectorJavascript(_transactionsScript);
    if (raw is! String) return const [];
    return normalizeTransactionRows(_decodeRows(raw), range: range);
  }

  List<SberTransactionFact> normalizeTransactionRows(
    Iterable<Map<String, dynamic>> rows, {
    required SberSyncRange range,
  }) {
    final byFingerprint = <String, SberTransactionFact>{};
    for (final row in rows) {
      final transaction = _transactionFromRow(row, range);
      if (transaction != null) {
        byFingerprint[transaction.fingerprint] = transaction;
      }
    }
    final result = byFingerprint.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  static List<Map<String, dynamic>> _decodeRows(String raw) {
    try {
      final value = jsonDecode(raw);
      return (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  List<SberHistoryRowDiagnostic> diagnoseTransactionRows(
    Iterable<Map<String, dynamic>> rows, {
    required SberSyncRange range,
  }) => [
    for (final row in rows)
      _diagnoseRow(row, range, _transactionFromRow(row, range)),
  ];

  SberHistoryRowDiagnostic _diagnoseRow(
    Map<String, dynamic> row,
    SberSyncRange range,
    SberTransactionFact? transaction,
  ) {
    final date = _rowDate(row);
    final outcome = transaction != null
        ? SberHistoryRowOutcome.accepted
        : row['nonCashKind'] == 'reward'
        ? SberHistoryRowOutcome.reward
        : row['nonCashKind'] == 'service'
        ? SberHistoryRowOutcome.service
        : _clean(row['text'] as String?).isEmpty
        ? SberHistoryRowOutcome.emptyText
        : date == null
        ? SberHistoryRowOutcome.missingDate
        : !range.contains(date)
        ? SberHistoryRowOutcome.outsidePeriod
        : SberHistoryRowOutcome.missingAmount;
    final merchant = _merchantCandidate(row['merchant'] as String?);
    return SberHistoryRowDiagnostic(
      observationId: _stableId('observation', _rawRowFingerprint(row)),
      outcome: outcome,
      date: date,
      description:
          merchant ??
          (_clean(row['operationType'] as String?).isNotEmpty
              ? _clean(row['operationType'] as String?)
              : 'Операция без названия'),
    );
  }

  static String _rawRowFingerprint(Map<String, dynamic> row) {
    final sourceId = _clean(row['id'] as String?);
    if (sourceId.isNotEmpty) return 'id:$sourceId';
    final observationKey = _clean(row['observationKey'] as String?);
    if (observationKey.isNotEmpty) return 'observation:$observationKey';
    // Ordinals are deliberately excluded. They change whenever Sber recycles
    // virtual-list nodes and previously made the same operation look new.
    return 'fact:${row['dateIso'] ?? row['date']}|${row['amountValue'] ?? row['amount']}|${row['text']}|${row['account']}';
  }

  SberAccountFact? _accountFromRow(Map<String, dynamic> row) {
    final text = _clean(row['text'] as String?);
    final balance = _money(row['balance'] as String? ?? text);
    if (balance == null || text.isEmpty) return null;
    final lower = '${row['kind'] ?? ''} ${row['name'] ?? ''} $text'
        .toLowerCase();
    final type = lower.contains('вклад') || lower.contains('депозит')
        ? AccountType.deposit
        : lower.contains('накоп')
        ? AccountType.savings
        : lower.contains('кредит')
        ? AccountType.liability
        : lower.contains('инвест') || lower.contains('брокер')
        ? AccountType.investment
        : row['kind'] != 'account' && lower.contains('карт')
        ? AccountType.bankCard
        : AccountType.cash;
    final identityText = _clean(row['identityText'] as String? ?? text);
    final maskedLastFour =
        RegExp(
          r'(?:\*{2,}|X{2,}|•{2,})\s*(\d{4})',
        ).firstMatch(identityText)?.group(1) ??
        RegExp(
          r'(?:^|[^а-яёa-z])(?:сч[её]т|карта)\s*(?:[•*Xx]+\s*)?(\d{4})(?!\d)',
          caseSensitive: false,
        ).firstMatch(identityText)?.group(1);
    final linkedCards =
        (row['cards'] as List? ?? const [])
            .map((value) => _clean(value?.toString()))
            .where((value) => RegExp(r'^\d{4}$').hasMatch(value))
            .toSet()
            .toList(growable: false)
          ..sort();
    final rawName = _clean(row['name'] as String?);
    final name = rawName.isEmpty ? _title(text) : rawName;
    final currency = _currency(text);
    final rawId = _clean(row['id'] as String?);
    final stableIdentity = rawId.isNotEmpty
        ? 'external:$rawId'
        : maskedLastFour != null
        ? 'suffix:$maskedLastFour'
        : linkedCards.isNotEmpty
        ? 'linked:${linkedCards.join(',')}'
        : 'name:${_accountIdentityName(name)}|${type.name}|$currency';
    final id = _stableId('account', stableIdentity);
    return SberAccountFact(
      id: id,
      name: name,
      type: type,
      currency: currency,
      balance: balance,
      exactBalanceMinor: _moneyMinor(row['balance'] as String? ?? text),
      availableBalance: _money(row['available'] as String? ?? ''),
      lastFour: maskedLastFour,
      linkedCardLastFours: linkedCards,
      historyResources: (row['historyResources'] as List? ?? const [])
          .whereType<String>()
          .where((v) => RegExp(r'^card:\d+$').hasMatch(v))
          .toList(),
      isLiability: type == AccountType.liability,
    );
  }

  static bool _accountsAreDirectlyLinked(
    SberAccountFact left,
    SberAccountFact right,
  ) {
    if (left.currency != right.currency) return false;
    return (right.type == AccountType.bankCard &&
            right.lastFour != null &&
            left.linkedCardLastFours.contains(right.lastFour)) ||
        (left.type == AccountType.bankCard &&
            left.lastFour != null &&
            right.linkedCardLastFours.contains(left.lastFour));
  }

  static SberAccountFact _mergeAccountFacts(
    SberAccountFact primary,
    SberAccountFact incoming,
  ) {
    // The account is authoritative for its balance; a linked card can show a
    // different available amount. Input DOM order must not change net worth.
    final account = primary.linkedCardLastFours.isNotEmpty ? primary : incoming;
    final cards = <String>{
      ...primary.linkedCardLastFours,
      ...incoming.linkedCardLastFours,
      if (primary.type == AccountType.bankCard && primary.lastFour != null)
        primary.lastFour!,
      if (incoming.type == AccountType.bankCard && incoming.lastFour != null)
        incoming.lastFour!,
    }.toList(growable: false)..sort();
    return SberAccountFact(
      id: account.id,
      name: account.name,
      type: account.type,
      currency: primary.currency,
      balance: account.balance,
      exactBalanceMinor: account.balanceMinor,
      availableBalance: incoming.availableBalance ?? primary.availableBalance,
      lastFour: account.lastFour,
      linkedCardLastFours: cards,
      sourceAliases: {
        primary.id,
        incoming.id,
        ...primary.sourceAliases,
        ...incoming.sourceAliases,
      }.toList(),
      historyResources: {
        ...primary.historyResources,
        ...incoming.historyResources,
      }.toList(),
      isLiability: primary.isLiability || incoming.isLiability,
    );
  }

  SberTransactionFact? _transactionFromRow(
    Map<String, dynamic> row,
    SberSyncRange range,
  ) {
    if (row['nonCashKind'] == 'reward' || row['nonCashKind'] == 'service') {
      return null;
    }
    final text = _clean(row['text'] as String?);
    final date = _rowDate(row);
    final normalizedMinor = switch (row['amountValue']) {
      final num value => _moneyMinor(value.toString()),
      final String value => _moneyMinor(value),
      _ => null,
    };
    // The DOM display string is exact. Old JS snapshots rounded amountValue
    // to rubles, so preferring that compatibility field silently lost cents.
    final hasStructuredAmount =
        row.containsKey('amount') || row.containsKey('amountValue');
    final amountMinor =
        _moneyMinor(row['amount'] as String? ?? '') ??
        normalizedMinor ??
        // A partially rendered structured row can already show an account
        // balance or a fee. Neither is a substitute for its missing amount.
        (hasStructuredAmount ? null : _moneyMinor(text));
    final amount = amountMinor == null ? null : (amountMinor.abs() + 50) ~/ 100;
    if (text.isEmpty ||
        date == null ||
        amount == null ||
        !range.contains(date)) {
      return null;
    }
    final amountText = row['amount'] as String? ?? '';
    final operationType = _clean(row['operationType'] as String?);
    final classificationText = '$text $operationType'.toLowerCase();
    final signedText = amountText.trimLeft().replaceAll('\u2212', '-');
    final explicitDebit = signedText.startsWith('-');
    final explicitCredit = signedText.startsWith('+');
    // A failed/cancelled payment is not a refund. A credit reversal is a
    // separate money movement; merchant text must not override a debit sign.
    final cancelled =
        RegExp(
          r'отклон|операци[яю]\s+отменена|отмен[её]нная\s+операция|не\s+выполнена',
        ).hasMatch(
          operationType.isEmpty
              ? classificationText
              : operationType.toLowerCase(),
        );
    final refund =
        !explicitDebit &&
        !cancelled &&
        (classificationText.contains('возврат') ||
            (explicitCredit && classificationText.contains('отмена операци')));
    final income =
        !explicitDebit &&
        (refund ||
            explicitCredit ||
            classificationText.contains('зачислен') ||
            classificationText.contains('зарплат') ||
            classificationText.contains('перевод от') ||
            classificationText.contains('поступлен') ||
            classificationText.contains('входящ') ||
            classificationText.contains('получен'));
    final transfer =
        classificationText.contains('перевод') ||
        classificationText.contains('между своими') ||
        classificationText.contains('пополнение') ||
        classificationText.contains('зачислен') ||
        classificationText.contains('сбп');
    final fee = RegExp(r'комисси|плата за перевод').hasMatch(
      operationType.isEmpty ? classificationText : operationType.toLowerCase(),
    );
    final internalTransfer =
        !fee &&
        transfer &&
        RegExp(
          r'между\s+(?:своими|собственными)|на\s+сво[юий]\s+(?:карт|сч[её]т)|со\s+своего\s+(?:сч[её]та|карт)',
          caseSensitive: false,
        ).hasMatch(classificationText);
    final status = cancelled
        ? 'CANCELLED'
        : classificationText.contains('обработ') ||
              classificationText.contains('ожида')
        ? 'PENDING'
        : refund
        ? 'REFUND'
        : 'POSTED';
    final sourceId = _clean(row['id'] as String?);
    final observationKey = _clean(row['observationKey'] as String?);
    final fingerprint = _stableId(
      'transaction',
      '$sourceId|$date|$amountMinor|$text|${sourceId.isEmpty ? observationKey : ''}',
    );
    final rawMerchant = _clean(row['merchant'] as String?);
    final merchant = _merchantCandidate(rawMerchant);
    final structuredDescription = _clean(row['description'] as String?);
    final rejectedMerchant = rawMerchant.isNotEmpty && merchant == null;
    final description = rejectedMerchant && operationType.isNotEmpty
        ? operationType
        : structuredDescription.isNotEmpty
        ? structuredDescription
        : [
            merchant,
            operationType,
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final loyaltyAmount = switch (row['loyaltyAmount']) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value.replaceAll(',', '.')),
      _ => null,
    };
    return SberTransactionFact(
      sourceId: sourceId.isEmpty ? fingerprint : sourceId,
      accountId: _accountId(row['account'] as String?),
      date: date,
      amount: amount.abs(),
      exactAmountMinor: amountMinor!.abs(),
      currency: _currency(text),
      description: description.isEmpty ? text : description,
      merchant: merchant,
      category: _clean(row['category'] as String?).isEmpty
          ? null
          : _clean(row['category'] as String?),
      status: status,
      fingerprint: fingerprint,
      isTransfer: transfer,
      isIncome: income,
      isInternalTransfer: internalTransfer,
      operationType: operationType.isEmpty ? null : operationType,
      loyaltyReward: loyaltyAmount == null
          ? null
          : SberLoyaltyReward(amount: loyaltyAmount),
    );
  }

  DateTime? _rowDate(Map<String, dynamic> row) {
    final normalized = DateTime.tryParse(_clean(row['dateIso'] as String?));
    return normalized ??
        _date(row['date'] as String? ?? _clean(row['text'] as String?));
  }

  static String? _merchantCandidate(String? source) {
    final value = _clean(source);
    if (value.isEmpty) return null;
    final normalized = value.toLowerCase().replaceAll('ё', 'е');
    final rewardOnly = RegExp(
      r'^[+\-−]?\s*\d+(?:[,.]\d+)?\s*(?:балл(?:а|ов|ы)?|бонус(?:а|ов|ы)?|спасибо)?$',
    ).hasMatch(normalized);
    final operationLabel = RegExp(
      r'^(?:оплата|входящий перевод|исходящий перевод|перевод по|возврат|отмена операции|списание бонусов|начисление бонусов)',
    ).hasMatch(normalized);
    final rewardLabel = RegExp(
      r'(?:сбер)?спасибо|бонус|балл',
    ).hasMatch(normalized);
    return rewardOnly || operationLabel || rewardLabel ? null : value;
  }

  static String _clean(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _accountIdentityName(String value) => _clean(
    value
        .toLowerCase()
        .replaceAll(RegExp(r'(?:\*{2,}|x{2,}|•{2,})\s*\d{4}'), ' ')
        .replaceAll(RegExp(r'\b(?:баланс|остаток|доступно)\b.*'), ' ')
        .replaceAll(RegExp(r'[^a-zа-яё0-9]+'), ' '),
  );

  static String _accountId(String? value) {
    final source = _clean(value);
    // Product cards and history links contain the same provider identifier.
    // Both paths must use the same namespace before mapping to Synoball.
    return source.isEmpty ? '' : _stableId('account', 'external:$source');
  }

  static String _title(String text) {
    final parts = text.split(RegExp(r'\s{2,}|\n'))
      ..removeWhere((part) => _money(part) != null);
    return (parts.isEmpty ? text : parts.first).trim();
  }

  static int? _money(String text) {
    final minor = _moneyMinor(text);
    return minor == null ? null : minor.sign * ((minor.abs() + 50) ~/ 100);
  }

  static int? _moneyMinor(String text) {
    text = text.replaceAll('\u2212', '-');
    final match =
        RegExp(
          r'([+-]?\d[\d\s]*)(?:[,\.](\d{1,2}))?\s*(?:₽|руб\.?|RUB|\$|USD|€|EUR|CNY|¥)',
          caseSensitive: false,
        ).firstMatch(text) ??
        RegExp(
          r'^\s*([+-]?\d[\d\s]*)(?:[,\.](\d{1,2}))?\s*$',
          caseSensitive: false,
        ).firstMatch(text);
    if (match == null) return null;
    final rawWhole = match.group(1)!.replaceAll(RegExp(r'\s'), '');
    final whole = int.tryParse(rawWhole);
    if (whole == null) return null;
    final fraction = int.tryParse((match.group(2) ?? '').padRight(2, '0')) ?? 0;
    final units = whole.abs() * 100 + fraction;
    return rawWhole.startsWith('-') ? -units : units;
  }

  static String _currency(String text) {
    final upper = text.toUpperCase();
    if (upper.contains('USD') || text.contains(r'$')) return 'USD';
    if (upper.contains('EUR') || text.contains('€')) return 'EUR';
    if (upper.contains('CNY') || text.contains('¥')) return 'CNY';
    return 'RUB';
  }

  static DateTime? _date(String text) {
    final now = DateTime.now();
    final lower = text.toLowerCase();
    final relativeDay = lower.contains('позавчера')
        ? 2
        : lower.contains('вчера')
        ? 1
        : lower.contains('сегодня')
        ? 0
        : null;
    if (relativeDay != null) {
      final date = now.subtract(Duration(days: relativeDay));
      return _withTime(date, text);
    }
    final numeric = RegExp(
      r'(\d{1,2})[.\-/](\d{1,2})(?:[.\-/](\d{2,4}))?',
    ).firstMatch(text);
    if (numeric != null) {
      var year = int.tryParse(numeric.group(3) ?? '') ?? now.year;
      if (year < 100) year += 2000;
      if (numeric.group(3) == null) {
        year =
            DateTime(
              now.year,
              int.parse(numeric.group(2)!),
              int.parse(numeric.group(1)!),
            ).isAfter(now)
            ? now.year - 1
            : now.year;
      }
      return _withTime(
        DateTime(
          year,
          int.parse(numeric.group(2)!),
          int.parse(numeric.group(1)!),
        ),
        text,
      );
    }
    const months = {
      'янв': 1,
      'фев': 2,
      'мар': 3,
      'апр': 4,
      'май': 5,
      'июн': 6,
      'июл': 7,
      'авг': 8,
      'сен': 9,
      'окт': 10,
      'ноя': 11,
      'дек': 12,
    };
    final named = RegExp(
      r'(\d{1,2})\s+([а-яё]{3,})\s*(\d{4})?',
      caseSensitive: false,
    ).firstMatch(text.toLowerCase());
    if (named == null) return null;
    final month = months.entries
        .firstWhere(
          (entry) => named.group(2)!.startsWith(entry.key),
          orElse: () => const MapEntry('', 0),
        )
        .value;
    if (month == 0) return null;
    final explicitYear = int.tryParse(named.group(3) ?? '');
    final day = int.parse(named.group(1)!);
    final year =
        explicitYear ??
        (DateTime(now.year, month, day).isAfter(now) ? now.year - 1 : now.year);
    return _withTime(DateTime(year, month, day), text);
  }

  static DateTime _withTime(DateTime date, String text) {
    final time = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(text);
    return time == null
        ? date
        : DateTime(
            date.year,
            date.month,
            date.day,
            int.parse(time.group(1)!),
            int.parse(time.group(2)!),
          );
  }

  static String _stableId(String prefix, String value) {
    var hash = 2166136261;
    for (final byte in utf8.encode(value.toLowerCase())) {
      hash ^= byte;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 'sber-$prefix-${hash.toRadixString(16)}';
  }
}

const _accountsScript = r'''(() => {
  /* QESTO_SBER_READ_V1: structured visible product facts only. */
  const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
  const visible = (node) => {
    const s = getComputedStyle(node);
    const rect = node.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  };
  const money = /[+\u2212-]?\d[\d\s]*(?:[,\.]\d{1,2})?\s*(?:₽|руб\.?|RUB|\$|USD|€|EUR|CNY|¥)/i;
  const hrefOf = (node) => (node.getAttribute('href') || node.href || '').split('?')[0];
  const routeId = (href) => (href.match(/\/cta\/details\/([^/]+)/i) || [])[1] || '';
  const values = [];
  // A card shown under an account is not another source of capital. Treat
  // the account route as authoritative and keep card suffixes as relations.
  const anchors = Array.from(document.querySelectorAll('a[href*="/app/cta/details/"]')).filter(visible);
  for (const node of anchors) {
    const href = hrefOf(node);
    const aria = clean(node.getAttribute('aria-label'));
    const ownText = clean(node.innerText);
    let context = ownText || aria;
    let relationRoot = node;
    let parent = node.parentElement;
    for (let depth = 0; depth < 4 && parent; depth++, parent = parent.parentElement) {
      // Never cross into the wallet/another product. Its total and suffixes
      // belong to multiple accounts, even when the entire block is short.
      if (parent.matches('body,main,nav') ||
          parent.querySelectorAll('a[href*="/app/cta/details/"]').length !== 1) break;
      const candidate = clean(parent.innerText);
      if (!candidate || candidate.length > 700) break;
      relationRoot = parent;
      if (money.test(candidate)) {
        context = candidate;
        break;
      }
    }
    const hint = aria.match(/(?:баланс|остаток|доступно)[^0-9+-]*([+-]?\d[\d\s]*(?:[,\.]\d{1,2})?)\.?\s*(₽|руб\.?|RUB|\$|USD|€|EUR|CNY|¥)/i);
    const balanceHint = hint ? hint[1] + ' ' + hint[2] : '';
    const balance = (ownText.match(money) || [])[0] || balanceHint || (context.match(money) || [])[0] || '';
    if (!balance) continue;
    const kind = 'account';
    const name = (aria.match(/^(.+?)(?:\.?\s+Баланс|\.?\s+Привязана|$)/i) || [])[1] || aria;
    const linkedNodes = relationRoot
      ? Array.from(relationRoot.querySelectorAll('a[href*="/app/cards/details/"],button[aria-label],[role="button"][aria-label]'))
          .filter(linked => linked.matches('a[href*="/app/cards/details/"]') || /карт/i.test(linked.getAttribute('aria-label') || ''))
      : [];
    const cards = Array.from(new Set(linkedNodes.flatMap((linked) => {
      const cardText = clean((linked.getAttribute('aria-label') || '') + ' ' + (linked.innerText || ''));
      return Array.from(cardText.matchAll(/(?:\D|^)(\d{4})(?=\D|$)/g)).map((match) => match[1]);
    })));
    values.push({
      id: routeId(href) || node.getAttribute('data-id') || node.getAttribute('data-testid') || '',
      kind,
      name: clean(name),
      identityText: clean(aria + ' ' + ownText),
      text: context.slice(0, 700),
      balance,
      available: (context.match(/(?:доступно|available)[^0-9+-]*([+-]?\d[\d\s]*(?:[,\.]\d{1,2})?\s*(?:₽|руб\.?|RUB|\$|USD|€|EUR|CNY|¥))/i) || [])[1] || '',
      cards,
      historyResources: linkedNodes.filter(n => n.matches('a[href*="/app/cards/details/"]'))
        .map(n => 'card:' + (hrefOf(n).match(/\/cards\/details\/(\d+)$/) || [])[1])
        .filter(v => /^card:\d+$/.test(v)),
    });
  }
  // The expanded wallet may show card tiles instead of account anchors.
  // Keep these as product observations; merge them with explicit linked cards.
  for (const node of Array.from(document.querySelectorAll('a[href*="/app/cards/details/"]')).filter(visible)) {
    const id = (hrefOf(node).match(/\/cards\/details\/(\d+)$/) || [])[1];
    const text = clean(node.innerText || node.getAttribute('aria-label'));
    const balance = (text.match(money) || [])[0];
    if (!id || !balance) continue;
    values.push({id, kind:'card', name:clean((node.innerText || '').split('\n')[0]),
      identityText:text, text, balance, available:balance, cards:[], historyResources:['card:' + id]});
  }
  return JSON.stringify(values.filter((row, i, all) => all.findIndex((item) => item.id === row.id && item.kind === row.kind) === i).slice(0, 200));
})()''';

const _transactionsScript = r'''(() => {
  /* QESTO_SBER_READ_V1: visible transaction facts, never page internals. */
  const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
  const resource = new URL(location.href).searchParams.get('usedResource') || '';
  const productFilter = document.querySelector('[data-filter="product"]');
  const selectedProduct = clean(productFilter && productFilter.innerText);
  const resourceAccount = /^card:\d+$/.test(resource) && /\d{4}/.test(selectedProduct)
      ? resource.substring(5) : '';
  const visible = (node) => {
    const s = getComputedStyle(node);
    const rect = node.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  };
  const money = /[+-]?\d[\d\s]*(?:[,\.]\d{1,2})?\s*(?:₽|руб\.?|RUB|\$|USD|€|EUR|CNY|¥)/i;
  const rewardMarker = /(?:сбер)?спасибо|бонус(?:а|ов|ы)?|балл(?:а|ов|ы)?/i;
  const signedNumber = /[+\u2212-]\s*\d[\d\s]*(?:[,\.]\d{1,2})?/;
  const labelledReward = /\d[\d\s]*(?:[,\.]\d{1,2})?\s*(?:спасибо|бонус(?:а|ов|ы)?|балл(?:а|ов|ы)?)/i;
  const service = /(?:получить|сформировать|заказать|скачать)?\s*(?:выписк|справк|документ)/i;
  // Restrict textual dates to real Russian month names. The previous generic
  // `number + word` branch treated a loyalty reward such as
  // "+12,45 Московский транспорт" as the impossible date "45 Московский"
  // and discarded the otherwise valid monetary operation.
  const datePattern = /(?:0?[1-9]|[12]\d|3[01])[.\-/](?:0?[1-9]|1[0-2])(?:[.\-/]\d{2,4})?|(?:0?[1-9]|[12]\d|3[01])\s+(?:январ[ья]|феврал[ья]|марта?|апрел[ья]|ма[йя]|июн[ья]|июл[ья]|августа?|сентябр[ья]|октябр[ья]|ноябр[ья]|декабр[ья])(?:\s+\d{4})?|сегодня|вчера|позавчера/i;
  const amountValue = (raw) => {
    const normalized = clean(raw).replace(/[\u00a0\u202f]/g, ' ').replace(/\u2212/g, '-');
    const match = normalized.match(/([+-]?\d[\d ]*)(?:[,\.]([0-9]{1,2}))?/);
    if (!match) return null;
    const whole = Number(match[1].replace(/\s/g, ''));
    if (!Number.isFinite(whole)) return null;
    const fraction = Number(String(match[2] || '').padEnd(2, '0')) || 0;
    return Math.abs(whole) + fraction / 100;
  };
  const dateIso = (raw, context) => {
    const source = clean(raw).toLowerCase();
    const now = new Date();
    let date = null;
    if (source.includes('позавчера')) date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 2);
    else if (source.includes('вчера')) date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    else if (source.includes('сегодня')) date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const numeric = source.match(/(\d{1,2})[.\-/](\d{1,2})(?:[.\-/](\d{2,4}))?/);
    if (!date && numeric) {
      let year = numeric[3] ? Number(numeric[3]) : now.getFullYear();
      if (year < 100) year += 2000;
      date = new Date(year, Number(numeric[2]) - 1, Number(numeric[1]));
      if (!numeric[3] && date > now) date.setFullYear(date.getFullYear() - 1);
    }
    const months = {янв:0,фев:1,мар:2,апр:3,май:4,июн:5,июл:6,авг:7,сен:8,окт:9,ноя:10,дек:11};
    const named = source.match(/(\d{1,2})\s+([а-яё]{3,})\s*(\d{4})?/i);
    if (!date && named) {
      const key = Object.keys(months).find((value) => named[2].startsWith(value));
      if (key) {
        date = new Date(Number(named[3] || now.getFullYear()), months[key], Number(named[1]));
        if (!named[3] && date > now) date.setFullYear(date.getFullYear() - 1);
      }
    }
    if (!date || Number.isNaN(date.getTime())) return '';
    const time = clean(context).match(/\b(\d{1,2}):(\d{2})\b/);
    if (time) date.setHours(Number(time[1]), Number(time[2]), 0, 0);
    const two = (value) => String(value).padStart(2, '0');
    return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}T${two(date.getHours())}:${two(date.getMinutes())}:00`;
  };
  const groupedDate = (node) => {
    // The aria label of the enclosing day group is authoritative. Inspect it
    // before row text because rows can start with a signed loyalty amount.
    const labelledGroup = node.closest('ul[aria-label],ol[aria-label]');
    const labelledDate = clean(labelledGroup?.getAttribute('aria-label') || '').match(datePattern)?.[0] || '';
    if (labelledDate) return labelledDate;
    const section = node.closest('section');
    if (section) {
      for (const child of Array.from(section.children)) {
        if (child.contains(node)) continue;
        const value = clean(child.innerText).match(datePattern)?.[0] || '';
        if (value) return value;
      }
    }
    const own = clean(node.innerText).match(datePattern)?.[0] || '';
    if (own) return own;
    let branch = node;
    for (let depth = 0; branch && depth < 5; depth++, branch = branch.parentElement) {
      let sibling = branch.previousElementSibling;
      while (sibling) {
        const value = clean(sibling.innerText).match(datePattern)?.[0] || '';
        if (value) return value;
        sibling = sibling.previousElementSibling;
      }
    }
    return '';
  };
  const directText = (node) => clean(Array.from(node.childNodes || [])
    .filter((child) => child.nodeType === 3)
    .map((child) => child.textContent || '')
    .join(' '));
  const semanticLeaves = (node) => Array.from(node.querySelectorAll(
    'p,span,[aria-label],[data-testid],[data-test]'
  )).map((element) => ({
    element,
    text: directText(element) || clean(element.getAttribute('aria-label') || ''),
  })).filter((entry) => entry.text);
  const rewardNumber = /^[+\u2212-]\s*\d[\d\s]*(?:[,\.]\d{1,2})?$/;
  const genericOperation = /^(?:оплата(?:\s+товаров)?|входящий\s+перевод|исходящий\s+перевод|перевод\s+(?:по|между|на|со)|между\s+(?:своими|собственными)|пополнение|зачисление|возврат|отмена\s+операци|списание\s+бонусов|начисление\s+бонусов|в\s+обработке|исполнено|отменено)/i;
  const auxiliaryMoney = /баланс|остаток|доступно|комисси[яи]|(?:плат[её]жный|накопительный|текущий)\s+сч[её]т\s*:/i;
  const isPrimaryAmount = (entry, row) => {
    if (!money.test(entry.text) || auxiliaryMoney.test(entry.text)) return false;
    // The label and its balance/fee can live in sibling spans. Inspect a
    // compact one-amount container, never the entire multi-amount row.
    let parent = entry.element.parentElement;
    for (let depth = 0; parent && parent !== row && depth < 3; depth++, parent = parent.parentElement) {
      const context = clean(parent.innerText);
      const amounts = context.match(new RegExp(money.source, 'gi')) || [];
      if (context.length <= 220 && amounts.length === 1 && auxiliaryMoney.test(context)) return false;
    }
    return true;
  };
  const validMerchant = (value) => {
    const candidate = clean(value);
    if (!candidate || candidate.length > 180) return false;
    if (money.test(candidate) || datePattern.test(candidate) || rewardNumber.test(candidate)) return false;
    if (rewardMarker.test(candidate) || genericOperation.test(candidate)) return false;
    return /[a-zа-яё]/i.test(candidate);
  };
  const rewardContext = (entry, rowText) => {
    if (rewardMarker.test(rowText)) return true;
    let branch = entry.element.parentElement;
    for (let depth = 0; branch && depth < 3; depth++, branch = branch.parentElement) {
      if (branch.querySelector('svg,[aria-label*="спасибо" i],[data-testid*="bonus" i],[data-test*="bonus" i]')) return true;
    }
    return false;
  };
  const decimalValue = (raw) => {
    const normalized = clean(raw).replace(/[\s\u00a0\u202f]/g, '').replace(/\u2212/g, '-').replace(',', '.');
    const value = Number(normalized);
    return Number.isFinite(value) ? value : null;
  };
  const fallbackSelectors = 'tr,[role="row"],[data-testid*="transaction" i],[data-testid*="operation" i],[data-test*="transaction" i],[data-test*="operation" i],[class*="transaction" i],[class*="operation" i],#HISTORY a[href]';
  const rows = [];
  const operationGroupLink = (node) => {
    const group = node.closest('ul[aria-label],ol[aria-label]');
    return /операци/i.test(clean(group?.getAttribute('aria-label') || ''));
  };
  // CSS attribute-selector flag `i` is ASCII-only in Chromium. It did not
  // match Sber's capitalized Cyrillic aria-label "Операции ...", so links on
  // alternative routes (notably /app/payments/sbp) disappeared completely.
  const operationLinks = Array.from(new Set(document.querySelectorAll(
    'section ul[aria-label] li > a[href],section ol[aria-label] li > a[href],a[href*="/app/operations/details"],a[href*="/app/transfers/sberhub"],a[href*="/app/payments/sbp"]'
  ))).filter((node) => operationGroupLink(node) || /\/app\/(?:operations\/details|transfers\/sberhub|payments\/sbp)/i.test(node.getAttribute('href') || '')).filter(visible);
  const candidates = operationLinks.length > 0
    ? operationLinks
    : Array.from(document.querySelectorAll(fallbackSelectors)).filter(visible);
  candidates.forEach((original, ordinal) => {
    let node = original;
    if (original.matches('a')) {
      node = original.closest('tr,[role="row"],li') || original.parentElement || original;
    }
    if (!node || !visible(node)) return;
    const rawText = String(node.innerText || original.innerText || '');
    const text = clean(rawText);
    const date = groupedDate(node);
    const leaves = semanticLeaves(node);
    const amountLeaf = leaves.find((entry) => isPrimaryAmount(entry, node));
    // Raw-text fallback is only for old layouts without semantic amount
    // leaves. Do not reintroduce an explicitly excluded balance or commission.
    const fallbackAmountLine = leaves.some((entry) => money.test(entry.text)) ? '' :
      rawText.split(/[\r\n]+/).map(clean).find((line) => money.test(line) && !auxiliaryMoney.test(line)) || '';
    const amount = amountLeaf?.text.match(money)?.[0] || fallbackAmountLine.match(money)?.[0] || '';
    let amountRow = amountLeaf?.element.parentElement || null;
    let merchantEntry = null;
    for (let depth = 0; amountRow && depth < 5; depth++, amountRow = amountRow.parentElement) {
      const local = leaves.filter((entry) => amountRow.contains(entry.element));
      merchantEntry = local.find((entry) => entry !== amountLeaf && validMerchant(entry.text)) || null;
      if (merchantEntry) break;
    }
    if (!merchantEntry) merchantEntry = leaves.find((entry) => validMerchant(entry.text)) || null;
    const rewardEntry = leaves.find((entry) =>
      entry !== amountLeaf && rewardNumber.test(entry.text) &&
      (!amountRow || !amountRow.contains(entry.element)) && rewardContext(entry, text)
    ) || null;
    const markerReward = rewardMarker.test(text)
      ? text.match(signedNumber)?.[0] || text.match(labelledReward)?.[0] || ''
      : '';
    const rewardAmount = rewardEntry?.text || markerReward;
    const operationEntry = leaves.find((entry) =>
      entry !== merchantEntry && entry !== amountLeaf && entry !== rewardEntry &&
      genericOperation.test(entry.text)
    ) || null;
    const operationType = operationEntry?.text || '';
    const merchant = merchantEntry?.text || '';
    const description = [merchant, operationType].filter(Boolean).join(' · ');
    const serviceRow = service.test(operationType || text);
    // Keep an incomplete monetary row visible to Dart diagnostics. Dropping
    // it here used to hide extraction failures from the completeness report.
    if (!text && !operationLinks.includes(original)) return;
    const attrs = (name) => node.getAttribute(name) || original.getAttribute(name) || '';
    const detail = original.getAttribute('href') || '';
    let detailUrl = null;
    try { detailUrl = new URL(detail, window.location.href); } catch (_) {}
    const detailPathId = ((detailUrl?.pathname || detail.split('?')[0]).match(/\/details\/([^/]+)$/i) || [])[1] || '';
    const detailId = detailUrl?.searchParams.get('uohId') ||
      detailUrl?.searchParams.get('srcDocumentId') ||
      detailUrl?.searchParams.get('documentId') ||
      detailUrl?.searchParams.get('operationId') ||
      detailUrl?.searchParams.get('transactionId') || detailPathId;
    let account = attrs('data-account-id') || attrs('data-account') || '';
    const accountLink = node.querySelector('a[href*="/app/cta/details/"]');
    if (!account && accountLink) account = (accountLink.getAttribute('href') || '').split('/').pop() || '';
    if (!account) account = resourceAccount;
    rows.push({
      id: attrs('data-operation-id') || attrs('data-transaction-id') || attrs('data-document-id') || attrs('data-uoh-id') || attrs('data-id') || detailId,
      account,
      merchant: attrs('data-merchant') || attrs('data-merchant-name') || merchant,
      category: attrs('data-category') || attrs('data-category-name') || '',
      description,
      operationType,
      text: text.slice(0, 900),
      amount,
      date,
      amountValue: amountValue(amount),
      dateIso: dateIso(date, text),
      observationKey: detail || [date, amount, merchant, operationType, account].join('|'),
      ordinal,
      // A missing purchase amount plus an inline reward is still an incomplete
      // purchase, not a bonus-only record. Require explicit reward semantics.
      nonCashKind: /^(?:списание|начисление)\s+бонусов/i.test(operationType) ? 'reward' : !amount && serviceRow ? 'service' : '',
      reward: rewardAmount,
      loyaltyAmount: rewardAmount ? decimalValue(rewardAmount) : null,
    });
  });
  return JSON.stringify(rows.filter((row, index, all) =>
    !row.id || all.findIndex((item) => item.id === row.id) === index
  ).slice(0, 500));
})()''';

const _scrollScript = r'''(() => {
  /* QESTO_SBER_READ_V1: advance a visible read-only history list. */
  const amount = Math.max(Math.min(window.innerHeight * 0.32, 340), 220);
  const rowSelector = 'section ul[aria-label] li > a[href],section ol[aria-label] li > a[href],a[href*="/app/operations/details"],a[href*="/app/transfers/sberhub"],a[href*="/app/payments/sbp"]';
  const rows = Array.from(document.querySelectorAll(rowSelector)).filter((node) => {
    const group = node.closest('ul[aria-label],ol[aria-label]');
    return /операци/i.test(String(group?.getAttribute('aria-label') || '')) ||
      /\/app\/(?:operations\/details|transfers\/sberhub|payments\/sbp)/i.test(node.getAttribute('href') || '');
  });
  const last = rows.length > 0 ? rows[rows.length - 1] : null;
  const targets = [];
  const addScrollableAncestors = (start) => {
    let parent = start?.parentElement || null;
    while (parent) {
      const style = getComputedStyle(parent);
      if (parent.scrollHeight > parent.clientHeight + 24 &&
          /(auto|scroll|overlay)/i.test(style.overflowY)) {
        targets.push(parent);
      }
      parent = parent.parentElement;
    }
  };
  addScrollableAncestors(last);
  const loadMore = Array.from(document.querySelectorAll('button,[role="button"]'))
    .find((node) => /^(?:(?:показать|загрузить|открыть)\s+(?:ещ[её]|больше)|ещ[её]\s+операци)[^\n]{0,40}$/i
      .test(String(node.innerText || node.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim()));
  addScrollableAncestors(loadMore);
  if (document.scrollingElement) targets.push(document.scrollingElement);
  const uniqueTargets = Array.from(new Set(targets));
  const target = uniqueTargets.find((candidate) => {
    const style = getComputedStyle(candidate);
    const maximum = Math.max(0, candidate.scrollHeight - candidate.clientHeight);
    return maximum > candidate.scrollTop + 1 &&
      (candidate === document.scrollingElement || /(auto|scroll|overlay)/i.test(style.overflowY));
  });
  if (!target) return '0';
  const before = target.scrollTop;
  const maximum = Math.max(0, target.scrollHeight - target.clientHeight);
  target.scrollTop = Math.min(before + amount, maximum);
  target.dispatchEvent(new Event('scroll', {bubbles: true}));
  return String(target.scrollTop > before ? 1 : 0);
})()''';

const _loadMoreTransactionsScript = r'''(() => {
  /* QESTO_SBER_READ_V1: expand only the read-only operation history. */
  const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
  const visible = (node) => {
    const style = getComputedStyle(node);
    const rect = node.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' &&
      rect.width > 0 && rect.height > 0 && !node.disabled;
  };
  const matches = Array.from(document.querySelectorAll('button,[role="button"]'))
    .filter(visible)
    .filter((node) => /^(?:(?:показать|загрузить|открыть)\s+(?:ещ[её]|больше)|ещ[её]\s+операци)[^\n]{0,40}$/i.test(clean(node.innerText || node.getAttribute('aria-label'))));
  if (matches.length === 0) return '0';
  const operationRows = Array.from(document.querySelectorAll(
    'section ul[aria-label] li > a[href],section ol[aria-label] li > a[href],a[href*="/app/operations/details"],a[href*="/app/transfers/sberhub"],a[href*="/app/payments/sbp"]'
  )).filter((node) => {
    const group = node.closest('ul[aria-label],ol[aria-label]');
    return /операци/i.test(String(group?.getAttribute('aria-label') || '')) ||
      /\/app\/(?:operations\/details|transfers\/sberhub|payments\/sbp)/i.test(node.getAttribute('href') || '');
  });
  const lastRow = operationRows.length > 0 ? operationRows[operationRows.length - 1] : null;
  if (lastRow) {
    const rowBottom = lastRow.getBoundingClientRect().bottom;
    matches.sort((left, right) =>
      Math.abs(left.getBoundingClientRect().top - rowBottom) -
      Math.abs(right.getBoundingClientRect().top - rowBottom));
  }
  const button = matches[0];
  button.click();
  return '1';
})()''';

const _hasMoreTransactionsScript = r'''(() => {
  /* QESTO_SBER_READ_V1: detect remaining read-only history pagination. */
  const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
  const matches = Array.from(document.querySelectorAll('button,[role="button"]'))
    // Disabled pagination can mean a pending request, not end of history.
    .some((node) => /^(?:(?:показать|загрузить|открыть)\s+(?:ещ[её]|больше)|ещ[её]\s+операци)[^\n]{0,40}$/i
      .test(clean(node.innerText || node.getAttribute('aria-label'))));
  return String(matches ? 1 : 0);
})()''';

const _hydrationScrollScript = r'''(() => {
  /* QESTO_SBER_READ_V1: slowly expose lazy dashboard sections. */
  const candidates = [document.scrollingElement, ...Array.from(document.querySelectorAll('*'))]
    .filter((node) => node && node.scrollHeight > node.clientHeight + 24 && getComputedStyle(node).overflowY !== 'hidden')
    .sort((left, right) => (right.scrollHeight - right.clientHeight) - (left.scrollHeight - left.clientHeight));
  const target = candidates[0] || document.scrollingElement;
  if (!target) return '0';
  const before = target.scrollTop;
  const amount = Math.max(240, Math.min(360, window.innerHeight * 0.32));
  target.scrollTop = Math.min(target.scrollTop + amount, target.scrollHeight);
  return String(target.scrollTop > before ? 1 : 0);
})()''';

const _scrollToTopScript = r'''(() => {
  /* QESTO_SBER_READ_V1: leave the bank page in a predictable position. */
  const candidates = [document.scrollingElement, ...Array.from(document.querySelectorAll('*'))]
    .filter((node) => node && node.scrollHeight > node.clientHeight + 24 && getComputedStyle(node).overflowY !== 'hidden')
    .sort((left, right) => (right.scrollHeight - right.clientHeight) - (left.scrollHeight - left.clientHeight));
  const target = candidates[0] || document.scrollingElement;
  if (!target) return '0';
  target.scrollTop = 0;
  return '1';
})()''';
