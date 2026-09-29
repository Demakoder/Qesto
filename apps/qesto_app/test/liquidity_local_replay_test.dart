import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/repositories/local_qesto_repository.dart';
import 'package:qesto/desktop/pages/desktop_accounts_page.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/capital/domain/account_capital_service.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

// Opt-in read-only replay. Inputs and detailed diagnostics remain local/ignored.
// No native repository, network, migrations or writes to the real profile.
void main() {
  final directory = Platform.environment['QESTO_LIQUIDITY_REPLAY_DIR'];
  final stage = Platform.environment['QESTO_LIQUIDITY_REPLAY_STAGE'] ?? 'after';
  testWidgets('persisted liquidity pipeline and real chart replay', (
    tester,
  ) async {
    final root = Directory(directory!).absolute;
    final allowed = Directory(
      '../../.codex_tmp',
    ).absolute.resolveSymbolicLinksSync();
    expect(
      root.resolveSymbolicLinksSync().startsWith(
        '$allowed${Platform.pathSeparator}',
      ),
      isTrue,
    );
    expect(['before', 'after'], contains(stage));
    final input = File('${root.path}/financial-snapshot.json');
    final source = input.readAsStringSync();
    final raw = jsonDecode(source) as Map<String, dynamic>;
    final store = _ReadOnlyStore(source);
    final data = await LocalQestoRepository(
      store: store,
      publicStore: store,
    ).getUserFinancialData();
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: data,
    );
    addTearDown(controller.dispose);
    final asOf = controller.referenceDate;
    expect(
      asOf,
      DateTime(2026, 9, 27),
      reason: 'Capture belongs to the reported day',
    );
    final canonical = {
      for (final t in controller.synoballState.transactions) t.id: t,
    };
    final canonicalAccounts = {
      for (final a in controller.synoballState.accounts) a.id: a,
    };
    final accounts = {for (final a in controller.accounts) a.id: a};
    final prefs = {
      for (final p in controller.accountPreferences) p.accountId: p,
    };
    const liquidTypes = {
      AccountType.cash,
      AccountType.bankCard,
      AccountType.savings,
      AccountType.deposit,
    };
    final includedIds = accounts.values
        .where(
          (a) =>
              liquidTypes.contains(a.type) &&
              (prefs[a.id]?.includeInTotal ?? true) &&
              !(prefs[a.id]?.isClosed ?? false),
        )
        .map((a) => a.id)
        .toSet();
    const service = AccountCapitalService();
    const cash = CashFlowCalculationService();
    AccountCapitalSnapshot calculate(
      List<BudgetTransaction> rows,
      CapitalPeriod period,
    ) => service.calculate(
      accounts: controller.accounts,
      accountPreferences: controller.accountPreferences,
      transactions: rows,
      upcomingExpenses: controller.upcomingExpenses,
      savingsGoals: controller.savingsGoals,
      goalAllocations: controller.goalAllocations,
      debts: controller.debts,
      synoballState: controller.synoballState,
      asOf: asOf,
      period: period,
      baseCurrency: controller.user.defaultCurrency,
    );
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    int signed(BudgetTransaction t) => switch (t.type) {
      TransactionType.income || TransactionType.refund => t.amount,
      TransactionType.transfer =>
        t.transferDirection == TransferDirection.incoming
            ? t.amount
            : -t.amount,
      _ => -t.amount,
    };
    final from = DateTime(2026, 9, 6), to = DateTime(2026, 9, 28);
    final rows = controller.transactions
        .where((t) => !t.date.isBefore(from) && t.date.isBefore(to))
        .toList();
    final persistedIds = (raw['transactions'] as List)
        .map((t) => t['id'])
        .toSet();
    final inputIds = controller.transactions.map((t) => t.id).toSet();
    final expectedDaily = <DateTime, ({int income, int expense, int other})>{};
    final diagnostics = <Map<String, Object?>>[];
    for (final t in rows) {
      final a = accounts[t.accountId], ca = canonicalAccounts[t.accountId];
      final treatment = cash.treatment(t);
      final one = calculate([t], CapitalPeriod.oneMonth);
      final actualEffect = one.history.last.balance - one.history.first.balance;
      // Independently express the intended observed-liquidity semantics.
      final unresolvedBucket =
          ca?.isVirtual == true && a?.type == AccountType.other;
      final eligible =
          treatment != CashFlowTreatment.ignored &&
          (a == null ||
              unresolvedBucket ||
              (includedIds.contains(a.id) &&
                  (prefs[a.id]?.includeTransactionsInAnalytics ?? true)));
      final expectedEffect = eligible ? signed(t) : 0;
      final d = day(t.date);
      final previous = expectedDaily[d] ?? (income: 0, expense: 0, other: 0);
      expectedDaily[d] = (
        income:
            previous.income +
            (eligible && treatment == CashFlowTreatment.externalInflow
                ? t.amount
                : 0),
        expense:
            previous.expense +
            (eligible && treatment == CashFlowTreatment.externalOutflow
                ? t.amount
                : 0),
        other:
            previous.other +
            (eligible && treatment == CashFlowTreatment.internalTransfer
                ? signed(t)
                : 0),
      );
      final reason = actualEffect != 0
          ? 'included'
          : treatment == CashFlowTreatment.ignored
          ? 'invalid-status-or-non-monetary'
          : treatment == CashFlowTreatment.internalTransfer
          ? 'internal-transfer-blanket-exclusion'
          : a != null && !includedIds.contains(a.id)
          ? 'known-account-outside-liquid-anchor:${a.type.name}'
          : 'other-zero-effect';
      diagnostics.add({
        'id': t.id,
        'persisted': persistedIds.contains(t.id),
        'persistedOccurredAt': canonical[t.id]?.occurredAt.toIso8601String(),
        'chartDateField':
            'BudgetTransaction.date <- CanonicalTransaction.occurredAt',
        'chartDate': t.date.toIso8601String(),
        'day': d.toIso8601String().substring(0, 10),
        'bank': ca?.institutionId,
        'sourceTags': t.tags
            .where((tag) => tag == 'sberbank' || tag == 'sber-live')
            .toList(),
        'amount': t.amount,
        'amountMinor': t.amountMinor,
        'netEffect': signed(t),
        'type': t.type.name,
        'direction':
            t.transferDirection?.name ?? canonical[t.id]?.direction.name,
        'status': canonical[t.id]?.status.name,
        'accountId': t.accountId,
        'accountResolution':
            unresolvedBucket || t.tags.contains('sber-account-unresolved')
            ? 'unresolved'
            : 'resolved',
        'accountType': a?.type.name,
        'isVirtualAccount': ca?.isVirtual,
        'internalTransfer': treatment == CashFlowTreatment.internalTransfer,
        'nonMonetary':
            t.tags.contains('qesto-non-cash') ||
            t.tags.contains('sber-loyalty-only'),
        'liquidAccount': a == null ? null : liquidTypes.contains(a.type),
        'cashFlowUses':
            treatment == CashFlowTreatment.externalInflow ||
            treatment == CashFlowTreatment.externalOutflow,
        'aggregateUses': actualEffect != 0,
        'exclusionReason': reason,
        'actualRowEffect': actualEffect,
        'expectedRowEffect': expectedEffect,
      });
    }
    final snapshot = calculate(controller.transactions, CapitalPeriod.oneMonth);
    final trace = <Map<String, Object?>>[];
    var numericalViolations = 0;
    for (var i = 1; i < snapshot.history.length; i++) {
      final point = snapshot.history[i];
      if (point.date.isBefore(from)) continue;
      final expected =
          expectedDaily[point.date] ?? (income: 0, expense: 0, other: 0);
      final net = expected.income - expected.expense + expected.other;
      final actual = point.balance - snapshot.history[i - 1].balance;
      if (actual != net) numericalViolations++;
      trace.add({
        'date': point.date.toIso8601String().substring(0, 10),
        'income': expected.income,
        'expense': expected.expense,
        'otherNet': expected.other,
        'expectedDailyNet': net,
        'actualDailyNet': actual,
        'calculatedBalance': point.balance,
      });
    }
    final reasons = <String, int>{};
    for (final row in diagnostics) {
      final key = row['exclusionReason'] as String;
      reasons[key] = (reasons[key] ?? 0) + 1;
    }
    final flow = controller.cashFlowForRange(
      from: from,
      toExclusive: to,
      currency: 'RUB',
    );
    final summary = {
      'stage': stage,
      'referenceDate': asOf.toIso8601String(),
      'persistedCount': persistedIds.length,
      'canonicalCount': canonical.length,
      'serviceInputCount': inputIds.length,
      'persistedMissingFromInput': persistedIds.difference(inputIds).toList(),
      'inputAbsentFromPersisted': inputIds.difference(persistedIds).toList(),
      'periodFrom': from.toIso8601String(),
      'periodToExclusive': to.toIso8601String(),
      'periodCount': rows.length,
      'strictlyAfterSeptember6': rows
          .where((t) => !t.date.isBefore(DateTime(2026, 9, 7)))
          .length,
      'aggregateUses': diagnostics
          .where((r) => r['aggregateUses'] == true)
          .length,
      'cashFlowUses': diagnostics
          .where((r) => r['cashFlowUses'] == true)
          .length,
      'reasons': reasons,
      'currentTotal': snapshot.totalLiquidAssets,
      'cashFlowIncomeMinor': flow.externalInflowsMinor,
      'cashFlowExpenseMinor': flow.externalOutflowsMinor,
      'numericalViolations': numericalViolations,
      'dailyTrace': trace,
      'allPeriods': {
        for (final p in CapitalPeriod.values)
          p.name: calculate(controller.transactions, p).history
              .map(
                (v) => {'date': v.date.toIso8601String(), 'balance': v.balance},
              )
              .toList(),
      },
    };
    const encoder = JsonEncoder.withIndent('  ');
    File(
      '${root.path}/operations-$stage.json',
    ).writeAsStringSync(encoder.convert(diagnostics));
    File(
      '${root.path}/summary-$stage.json',
    ).writeAsStringSync(encoder.convert(summary));
    // Aggregate output only; all transaction-level information stays local.
    // ignore: avoid_print
    print(
      jsonEncode(
        Map.of(summary)
          ..remove('allPeriods')
          ..remove('dailyTrace'),
      ),
    );

    for (final entry in {
      'Onest': 'assets/fonts/white_silver/Onest-Variable.ttf',
      'Prata': 'assets/fonts/white_silver/Prata-Regular.ttf',
      'Noto Serif Display':
          'assets/fonts/white_silver/NotoSerifDisplay-Italic.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const boundaryKey = Key('liquidity-replay');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(body: DesktopAccountsPage(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final dynamic painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere(
          (w) => w.painter.runtimeType.toString() == '_BalancePainter',
        )
        .painter;
    expect(
      (painter.points as List<AccountBalancePoint>).map((p) => p.balance),
      snapshot.history.map((p) => p.balance),
    );
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${root.path}/liquidity-$stage.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(input.readAsStringSync(), source);
    expect(store.writes, 0);
    if (stage == 'before') {
      expect(numericalViolations, greaterThan(0));
      expect(
        trace
            .where((d) => (d['date'] as String).compareTo('2026-09-07') > 0)
            .every((d) => d['actualDailyNet'] == 0),
        isTrue,
      );
    } else {
      expect(numericalViolations, 0);
      expect(
        diagnostics.every(
          (r) => r['actualRowEffect'] == r['expectedRowEffect'],
        ),
        isTrue,
      );
      expect(
        trace
            .where((d) => (d['date'] as String).compareTo('2026-09-06') > 0)
            .any((d) => d['actualDailyNet'] != 0),
        isTrue,
      );
      final oneMonthBalances = {
        for (final p in snapshot.history) p.date: p.balance,
      };
      for (final period in CapitalPeriod.values) {
        final other = calculate(controller.transactions, period);
        expect(
          other.history.last.balance,
          snapshot.totalLiquidAssets,
          reason: period.name,
        );
        for (final point in other.history.where(
          (p) => !p.date.isBefore(from),
        )) {
          expect(
            point.balance,
            oneMonthBalances[point.date],
            reason: '${period.name}: ${point.date}',
          );
        }
      }
      final baseline =
          jsonDecode(
                File('${root.path}/summary-before.json').readAsStringSync(),
              )
              as Map;
      expect(summary['cashFlowIncomeMinor'], baseline['cashFlowIncomeMinor']);
      expect(summary['cashFlowExpenseMinor'], baseline['cashFlowExpenseMinor']);
      expect(summary['persistedMissingFromInput'], isEmpty);
      expect(summary['inputAbsentFromPersisted'], isEmpty);
    }
  }, skip: directory == null);
}

class _ReadOnlyStore extends LocalKeyValueStore {
  _ReadOnlyStore(this.source);
  final String source;
  int writes = 0;
  @override
  Future<String?> readString(String key) async =>
      key == 'qesto.user-financial-data.v1' ? source : null;
  @override
  Future<void> writeString(String key, String value) async {
    writes++;
    throw StateError('Read-only replay');
  }

  @override
  Future<void> remove(String key) async {
    writes++;
    throw StateError('Read-only replay');
  }
}
