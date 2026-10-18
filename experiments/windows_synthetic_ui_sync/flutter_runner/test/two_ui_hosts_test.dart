import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/core/widgets/qesto_elements.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/budget/transaction_details_screen.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';

const codec = UserFinancialDataCodec();

class NoteHost extends StatelessWidget {
  const NoteHost(
    this.name,
    this.controller,
    this.onEdit,
    this.onSync, {
    super.key,
  });
  final String name;
  final BudgetController controller;
  final VoidCallback onEdit, onSync;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Column(
      children: [
        Text(
          '$name ${controller.noteSyncStatus.name}',
          key: Key('$name-status'),
        ),
        QestoButton(
          key: Key('$name-edit'),
          label: '$name Save note',
          onPressed: onEdit,
        ),
        QestoButton(
          key: Key('$name-sync'),
          label: '$name Sync',
          onPressed: onSync,
        ),
        Expanded(
          child: TransactionDetailsScreen(
            controller: controller,
            period: controller.periods.first,
            transactionId: 'container-tx-0',
          ),
        ),
      ],
    ),
  );
}

void main({
  UiSyncHarness Function()? harnessFactory,
  String evidenceFile = '../results/two-ui-hosts.json',
}) {
  testWidgets(
    'real UI A -> durable local -> backend -> UI B and reverse; incoming publication creates no intent',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h =
          harnessFactory?.call() ??
          UiSyncHarness(root: '..', evidence: '../results');
      late WindowsNoteBoundary a, b;
      late BudgetController ca, cb;
      await tester.runAsync(() async {
        await h.start();
        final server = await h.server();
        a = await h.open(
          server,
          0,
          create: true,
          probe: BoundaryProbe.beforeCommitGate,
        );
        b = await h.open(server, 1, create: true);
        ca = BudgetController(
          configuration: budgetConfiguration,
          financialData: (await a.load()).data,
          noteBoundary: a,
        );
        cb = BudgetController(
          configuration: budgetConfiguration,
          financialData: (await b.load()).data,
          noteBoundary: b,
        );
      });
      Future<void>? operation;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildQestoTheme(),
            home: Scaffold(
              body: Row(
                children: [
                  Expanded(
                    child: NoteHost(
                      'A',
                      ca,
                      () => operation = ca.setTransactionNote(
                        'container-tx-0',
                        'UI A note',
                        commandId: 'ui-a',
                      ),
                      () => operation = ca.syncTransactionNotes(),
                    ),
                  ),
                  Expanded(
                    child: NoteHost(
                      'B',
                      cb,
                      () => operation = cb.setTransactionNote(
                        'container-tx-0',
                        'UI B note',
                        commandId: 'ui-b',
                      ),
                      () => operation = cb.syncTransactionNotes(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          final gate = a.stages.first;
          await tester.tap(find.byKey(const Key('A-edit')));
          await gate;
        });
        await tester.pump();
        expect(find.text('UI A note'), findsNothing);
        expect(find.text('user-owned note'), findsNWidgets(2));
        a.releaseProbe();
        await tester.runAsync(() => operation!);
        await tester.pump();
        expect(find.text('UI A note'), findsOneWidget);
        expect(find.text('A localOnly'), findsOneWidget);
        expect((await tester.runAsync(() => a.pending()))!.length, 1);
        Future<void> press(String key) async {
          await tester.runAsync(() async {
            await tester.tap(find.byKey(Key(key)));
            await operation!;
          });
          await tester.pump();
        }

        await press('A-sync');
        await press('B-sync');
        expect(find.text('UI A note'), findsNWidgets(2));
        expect(find.text('B synchronized'), findsOneWidget);
        expect((await tester.runAsync(() => b.pending()))!, isEmpty);
        await press('B-edit');
        expect(find.text('UI B note'), findsOneWidget);
        expect(find.text('B localOnly'), findsOneWidget);
        await press('B-sync');
        await press('A-sync');
        expect(find.text('UI B note'), findsNWidgets(2));
        expect(find.text('A synchronized'), findsOneWidget);
        expect(
          jsonDecode(
            codec.encode(
              ca.mergeInto((await tester.runAsync(() => a.load()))!.data),
            ),
          ),
          jsonDecode(
            codec.encode(
              cb.mergeInto((await tester.runAsync(() => b.load()))!.data),
            ),
          ),
        );
        File(evidenceFile).writeAsStringSync(
          jsonEncode({
            'passed': true,
            'real_controllers': 2,
            'real_qesto_details_widgets': 2,
            'real_qesto_buttons': true,
            'network': 'loopback PostgreSQL',
            'publish_only_after_durable_local_commit': true,
            'bidirectional_notes': true,
            'incoming_generated_commands': 0,
          }),
          flush: true,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        ca.dispose();
        cb.dispose();
        await tester.runAsync(() async {
          await a.close();
          await b.close();
          await h.close();
        });
      }
    },
  );
  test(
    'unsupported synthetic commands reject before any in-memory state or callbacks change',
    () async {
      final h =
          harnessFactory?.call() ??
          UiSyncHarness(root: '..', evidence: '../results');
      await h.start();
      final s = await h.server();
      final owner = await h.open(s, 0, create: true),
          data = (await h.open(s, 1, create: true));
      await data.close();
      final original = (await owner.load()).data;
      final c = BudgetController(
        configuration: budgetConfiguration,
        financialData: original,
        noteBoundary: owner,
      );
      var notifications = 0;
      c.addListener(() => notifications++);
      final before = codec.encode(c.mergeInto(original));
      try {
        final attempts = <Future<void> Function()>[
          () => c.updateTransaction(
            c.transactions.first.copyWith(comment: 'Bypass'),
          ),
          () => c.updateTransactions([
            c.transactions.first.copyWith(comment: 'Batch bypass'),
          ]),
          () => c.deleteTransaction(c.transactions.first.id),
          () => c.setTotalBudget(period: c.periods.first, totalPlan: 1234),
          () => c.createCategory(
            name: 'Bypass category',
            iconKey: 'food',
            colorValue: 0xff009900,
          ),
        ];
        for (final attempt in attempts) {
          await expectLater(attempt(), throwsA(isA<NoteBoundaryFailure>()));
          expect(codec.encode(c.mergeInto(original)), before);
          expect(notifications, 0);
          expect((await owner.load()).revision, 0);
          expect(await owner.pending(), isEmpty);
        }
        expect(
          () => c.periodForOrCreate(DateTime(2099, 1)),
          throwsA(isA<NoteBoundaryFailure>()),
        );
        expect(codec.encode(c.mergeInto(original)), before);
        expect(c.noteRecoveryRequired, false);
      } finally {
        c.dispose();
        await owner.close();
        await h.close();
      }
    },
  );
  test(
    'controller disposed during remote response never publishes stale success',
    () async {
      final h =
          harnessFactory?.call() ??
          UiSyncHarness(root: '..', evidence: '../results');
      await h.start();
      final s = await h.server();
      final a = await h.open(s, 0, create: true),
          initial = (await a.load()).data;
      final c = BudgetController(
        configuration: budgetConfiguration,
        financialData: initial,
        noteBoundary: a,
      );
      await c.setTransactionNote(
        'container-tx-0',
        'Durable but no disposed UI publication',
        commandId: 'dispose-sync',
      );
      final before = codec.encode(c.mergeInto(initial));
      s.fault('dispose-sync', 'after-commit', 'gate');
      final pending = c.syncTransactionNotes();
      final rejected = expectLater(
        pending,
        throwsA(
          isA<NoteBoundaryFailure>().having(
            (e) => e.outcomeUnknown,
            'explicit reload required',
            true,
          ),
        ),
      );
      await s.hit();
      c.dispose();
      s.release();
      await rejected;
      expect(codec.encode(c.mergeInto(initial)), before);
      expect(c.noteRecoveryRequired, true);
      expect((await a.inspectForTest())['checkpoint'], 1);
      await a.close();
      await h.close();
    },
  );
}
