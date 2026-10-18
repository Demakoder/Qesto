import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_durable_effects_experiment/windows_driver.dart';

const codec = UserFinancialDataCodec();
final time = DateTime.utc(2026, 10, 16);
UserFinancialData fixture() => syntheticFixture(
  count: 60,
  fixturePath:
      '../../storage_feasibility/test/fixtures/container_profile_v7.json',
);

void main() {
  for (final mode in ['ordinary', 'stale-policy', 'audit-only']) {
    testWidgets(
      'real worker/controller $mode: atomic delta or verified fallback, full codec parity',
      (tester) async {
        var data = fixture();
        if (mode == 'stale-policy') {
          final raw = jsonDecode(codec.encode(data));
          for (final t in raw['synoball']['transactions']) {
            t['synoballCategory'] = 'business';
            t['userCategoryOverride'] = null;
            t['tags'] = ['user-label:qa'];
          }
          data = codec.decode(jsonEncode(raw));
        }
        if (mode == 'audit-only') {
          for (var i = 0; i < 2; i++) {
            data = prepareTransactionNote(
              data,
              'container-tx-0',
              'same',
              ids: CommandIds('seed-$i'),
              clock: () => time,
            ).data;
          }
        }
        late WindowsNoteBoundary worker;
        late EffectsNoteBoundary boundary;
        late BudgetController controller;
        await tester.runAsync(() async {
          worker = await WindowsNoteBoundary.open(
            SyntheticWindowsProfile.create(),
            initialSnapshot: codec.encode(data),
            incremental: true,
            effectsDriver: const EffectsDriverFactory(),
            bookkeeping: SyntheticBookkeeping(time),
            probe: BoundaryProbe.beforeCommitGate,
          );
          boundary = EffectsNoteBoundary(worker);
          controller = BudgetController(
            configuration: budgetConfiguration,
            financialData: data,
            noteBoundary: boundary,
          );
        });
        var notifications = 0;
        controller.addListener(() => notifications++);
        final before = codec.encode(controller.mergeInto(data));
        final note = mode == 'audit-only' ? 'same' : 'UI delta ☕';
        Future<void>? save;
        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Text(
                controller.transactions
                        .firstWhere((t) => t.id == 'container-tx-0')
                        .comment ??
                    '',
              ),
            ),
          ),
        );
        try {
          await tester.runAsync(() async {
            final staged = worker.stages.firstWhere(
              (s) => s == 'before-commit',
            );
            save = controller.setTransactionNote(
              'container-tx-0',
              note,
              commandId: 'ui-$mode',
            );
            await staged;
          });
          await tester.pump();
          expect(codec.encode(controller.mergeInto(data)), before);
          expect(notifications, 0);
          worker.releaseProbe();
          await tester.runAsync(() => save!);
          await tester.pump();
          expect(notifications, 1);
          expect(controller.noteRevision, 1);
          expect(find.text(note), findsOneWidget);
          final full = prepareTransactionNote(
            data,
            'container-tx-0',
            note,
            ids: CommandIds('ui-$mode'),
            clock: () => time,
          );
          expect(
            jsonDecode(codec.encode(controller.mergeInto(data))),
            jsonDecode(codec.encode(full.data)),
          );
          final loaded = (await tester.runAsync(() => worker.load()))!;
          expect(
            jsonDecode(codec.encode(loaded.data)),
            jsonDecode(codec.encode(full.data)),
          );
          if (mode == 'stale-policy') {
            expect(boundary.fullReloads, 1);
            expect(controller.lastNotePublicationWasDelta, isFalse);
          } else {
            expect(boundary.fullReloads, 0);
            expect(controller.lastNotePublicationWasDelta, isTrue);
          }
          await tester.runAsync(() async {
            File('../results/ui-$mode.json').writeAsStringSync(
              jsonEncode({
                'full_parity': true,
                'no_speculative_publication': true,
                'notifications': notifications,
                'delta': controller.lastNotePublicationWasDelta,
                'fallbacks': boundary.fullReloads,
                'delta_bytes': boundary.lastDeltaBytes,
                'full_codec_bytes': utf8.encode(codec.encode(full.data)).length,
                'timings': boundary.lastTimings,
                'publication_us': controller.lastNotePublicationMicros,
              }),
            );
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          await tester.runAsync(() => boundary.close(cancelPending: true));
        }
      },
    );
  }
  for (final mode in ['disposed', 'cancelled', 'changed']) {
    testWidgets('no false success after $mode during committed result', (
      tester,
    ) async {
      final data = fixture();
      late WindowsNoteBoundary worker;
      late BudgetController c;
      late EffectsNoteBoundary b;
      await tester.runAsync(() async {
        worker = await WindowsNoteBoundary.open(
          SyntheticWindowsProfile.create(),
          initialSnapshot: codec.encode(data),
          incremental: true,
          effectsDriver: const EffectsDriverFactory(),
          probe: BoundaryProbe.afterCommitGate,
        );
        b = EffectsNoteBoundary(worker);
        c = BudgetController(
          configuration: budgetConfiguration,
          financialData: data,
          noteBoundary: b,
        );
      });
      final before = codec.encode(c.mergeInto(data)),
          cancel = NoteCancellation();
      Future<void>? pending;
      await tester.runAsync(() async {
        final staged = worker.stages.firstWhere((s) => s == 'after-commit');
        pending = c.setTransactionNote(
          'container-tx-0',
          'not-published',
          commandId: 'ui-$mode',
          cancellation: cancel,
        );
        // Attach error observer before release, without consuming the original.
        pending!.then((_) {}, onError: (Object _) {});
        await staged;
      });
      if (mode == 'disposed') c.dispose();
      if (mode == 'cancelled') cancel.cancel();
      if (mode == 'changed') c.refreshLocalReadModel();
      worker.releaseProbe();
      await tester.runAsync(() async {
        await expectLater(
          pending!,
          throwsA(
            isA<NoteBoundaryFailure>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              true,
            ),
          ),
        );
      });
      expect(codec.encode(c.mergeInto(data)), before);
      if (mode != 'disposed') c.dispose();
      await tester.runAsync(() => b.close(cancelPending: true));
    });
  }
}
