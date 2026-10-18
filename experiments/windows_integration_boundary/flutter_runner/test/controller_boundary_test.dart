import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/repositories/local_qesto_repository.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';

const fixturePath =
    '../../storage_feasibility/test/fixtures/container_profile_v7.json';
const codec = UserFinancialDataCodec();
const command = 'parity';
void main() {
  test(
    'synthetic injection cannot share production save callback or silently fall back',
    () async {
      final initial = syntheticFixture(fixturePath: fixturePath);
      final owner = await WindowsNoteBoundary.open(
        SyntheticWindowsProfile.create(),
        initialSnapshot: codec.encode(initial),
      );
      try {
        expect(
          () => BudgetController(
            configuration: budgetConfiguration,
            financialData: initial,
            noteBoundary: owner,
            onChanged: () async {},
          ),
          throwsArgumentError,
        );
        final c = BudgetController(
          configuration: budgetConfiguration,
          financialData: initial,
          noteBoundary: owner,
        );
        try {
          final before = codec.encode(c.mergeInto(initial));
          await expectLater(
            c.setTotalBudget(period: c.periods.first, totalPlan: 123),
            throwsA(
              isA<NoteBoundaryFailure>().having(
                (e) => e.code,
                'code',
                'unsupported-synthetic-financial-command',
              ),
            ),
          );
          expect(codec.encode(c.mergeInto(initial)), before);
          expect(c.noteRecoveryRequired, false);
          expect((await owner.load()).revision, 0);
        } finally {
          c.dispose();
        }
      } finally {
        await owner.close();
      }
    },
  );
  test(
    'actual default controller/repository and worker give identical full financial results with configured policy',
    () async {
      final initial = syntheticFixture(fixturePath: fixturePath);
      final runtime = SyntheticBookkeeping(DateTime.utc(2026, 10, 12));
      final repo = LocalQestoRepository(store: MemoryKeyValueStore());
      late BudgetController old;
      var saves = 0;
      old = BudgetController(
        configuration: budgetConfiguration,
        financialData: initial,
        synoballClock: runtime.now,
        synoballIds: SyntheticIds(command),
        onChanged: () async {
          saves++;
          await repo.saveUserFinancialData(old.mergeInto(initial));
        },
      );
      final owner = await WindowsNoteBoundary.open(
        SyntheticWindowsProfile.create(),
        initialSnapshot: codec.encode(initial),
        bookkeeping: runtime,
      );
      final fresh = BudgetController(
        configuration: budgetConfiguration,
        financialData: initial,
        noteBoundary: owner,
      );
      try {
        final beforeCash = old.cashFlowForRange(
          from: DateTime(2026, 9, 1),
          toExclusive: DateTime(2026, 10, 1),
        );
        await old.updateTransaction(
          old.transactions.first.copyWith(comment: 'Точная заметка 13 ₽'),
        );
        await fresh.setTransactionNote(
          'container-tx-0',
          'Точная заметка 13 ₽',
          commandId: command,
        );
        expect(saves, 1);
        expect(old.noteBoundary, isNull);
        expect(
          jsonDecode(codec.encode(fresh.mergeInto(initial))),
          jsonDecode(codec.encode(old.mergeInto(initial))),
        );
        expect(
          fresh.synoballState.transactions.first.amount.minorUnits,
          486122,
        );
        expect(fresh.synoballState.transactions[1].amount.currency, 'USD');
        expect(
          fresh.synoballState.transactions.first.userCategoryOverride,
          'fitness-custom',
        );
        expect(
          fresh.synoballState.transactions[1].tags,
          contains('user-category-rule:synthetic-rule'),
        );
        expect(fresh.synoballState.transactions.last.status.name, 'deleted');
        expect(fresh.accounts.length, initial.accounts.length);
        expect(fresh.savingsGoals.length, initial.savingsGoals.length);
        expect(fresh.debts.length, initial.debts.length);
        expect(
          fresh.investmentAccounts.length,
          initial.investmentAccounts.length,
        );
        final after = fresh.cashFlowForRange(
          from: DateTime(2026, 9, 1),
          toExclusive: DateTime(2026, 10, 1),
        );
        expect(after.externalInflowsMinor, beforeCash.externalInflowsMinor);
        expect(after.externalOutflowsMinor, beforeCash.externalOutflowsMinor);
        final stored = await repo.store.readString(
          'qesto.user-financial-data.v1',
        );
        expect(
          jsonDecode(stored!),
          jsonDecode(codec.encode(old.mergeInto(initial))),
        );
      } finally {
        old.dispose();
        fresh.dispose();
        await owner.close();
      }
    },
  );
  testWidgets(
    'actual native boundary publishes only after commit; UI buttons respond while worker is waiting',
    (tester) async {
      final initial = syntheticFixture(fixturePath: fixturePath);
      final owner = (await tester.runAsync(
        () => WindowsNoteBoundary.open(
          SyntheticWindowsProfile.create(),
          initialSnapshot: codec.encode(initial),
          probe: BoundaryProbe.beforeCommitGate,
        ),
      ))!;
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: initial,
        noteBoundary: owner,
      );
      var notifications = 0, presses = 0;
      controller.addListener(() {
        notifications++;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Column(
              children: [
                Text(controller.transactions.first.comment!),
                TextButton(
                  onPressed: () {
                    presses++;
                  },
                  child: const Text('responsive'),
                ),
              ],
            ),
          ),
        ),
      );
      late Future<void> saving;
      await tester.runAsync(() async {
        final gate = owner.stages.first;
        saving = controller.setTransactionNote(
          'container-tx-0',
          'Published after commit',
          commandId: 'widget-note',
        );
        await gate;
      });
      expect(notifications, 0);
      expect(find.text('user-owned note'), findsOneWidget);
      await tester.tap(find.text('responsive'));
      await tester.pump();
      expect(presses, 1);
      owner.releaseProbe();
      await tester.runAsync(() => saving);
      await tester.pump();
      expect(notifications, 1);
      expect(find.text('Published after commit'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(() => owner.close());
    },
  );
  for (final probe in [
    BoundaryProbe.beforeCommitError,
    BoundaryProbe.afterCommitError,
  ]) {
    test(
      'controller retains old state and no success notification on $probe',
      () async {
        final initial = syntheticFixture(fixturePath: fixturePath);
        final owner = await WindowsNoteBoundary.open(
          SyntheticWindowsProfile.create(),
          initialSnapshot: codec.encode(initial),
          probe: probe,
        );
        final c = BudgetController(
          configuration: budgetConfiguration,
          financialData: initial,
          noteBoundary: owner,
        );
        var notifications = 0;
        c.addListener(() {
          notifications++;
        });
        try {
          await expectLater(
            c.setTransactionNote(
              'container-tx-0',
              'Must not publish',
              commandId: 'failure',
            ),
            throwsA(isA<NoteBoundaryFailure>()),
          );
          expect(c.transactions.first.comment, 'user-owned note');
          expect(notifications, 0);
          expect(
            c.noteRecoveryRequired,
            probe == BoundaryProbe.afterCommitError,
          );
          expect(
            (await owner.load()).revision,
            probe == BoundaryProbe.afterCommitError ? 1 : 0,
          );
        } finally {
          c.dispose();
          await owner.close();
        }
      },
    );
  }
  test('stale UI note is rejected while first note awaits commit', () async {
    final initial = syntheticFixture(fixturePath: fixturePath);
    final owner = await WindowsNoteBoundary.open(
      SyntheticWindowsProfile.create(),
      initialSnapshot: codec.encode(initial),
      probe: BoundaryProbe.beforeCommitGate,
    );
    final c = BudgetController(
      configuration: budgetConfiguration,
      financialData: initial,
      noteBoundary: owner,
    );
    try {
      final gate = owner.stages.first;
      final saving = c.setTransactionNote(
        'container-tx-0',
        'First',
        commandId: 'first',
      );
      await gate;
      await expectLater(
        c.setTransactionNote('container-tx-1', 'Stale UI', commandId: 'second'),
        throwsA(isA<NoteBoundaryFailure>()),
      );
      owner.releaseProbe();
      await saving;
      expect(c.noteRevision, 1);
    } finally {
      c.dispose();
      await owner.close();
    }
  });
  test(
    'disposal after commit before response does not publish and requires reload',
    () async {
      final initial = syntheticFixture(fixturePath: fixturePath);
      final owner = await WindowsNoteBoundary.open(
        SyntheticWindowsProfile.create(),
        initialSnapshot: codec.encode(initial),
        probe: BoundaryProbe.afterCommitGate,
      );
      final c = BudgetController(
        configuration: budgetConfiguration,
        financialData: initial,
        noteBoundary: owner,
      );
      final gate = owner.stages.first;
      final saving = c.setTransactionNote(
        'container-tx-0',
        'Durable after disposal',
        commandId: 'disposed',
      );
      final rejected = expectLater(saving, throwsA(isA<NoteBoundaryFailure>()));
      await gate;
      c.dispose();
      owner.releaseProbe();
      await rejected;
      expect(c.transactions.first.comment, 'user-owned note');
      expect(
        (await owner.load()).data.transactions.first.comment,
        'Durable after disposal',
      );
      await owner.close();
    },
  );
}
