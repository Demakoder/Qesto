import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_durable_effects_experiment/harness.dart';
import 'package:qesto_durable_effects_experiment/windows_driver.dart';
import '../../../windows_synthetic_ui_sync/flutter_runner/test/two_ui_hosts_test.dart'
    show NoteHost;

const codec = UserFinancialDataCodec();
void main() {
  testWidgets(
    'two rendered clients: durable delta, reverse sync, lost ACK, idempotent retry and repeated page',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = effectsHarness();
      final opened = <EffectsNoteBoundary>[];
      late EffectsNoteBoundary a, b;
      late BudgetController ca, cb;
      late dynamic server;
      var ready = false;
      await tester.runAsync(() async {
        try {
          await h.start(count: 60);
          server = await h.server();
          a = EffectsNoteBoundary(await h.open(server, 0, create: true));
          opened.add(a);
          b = EffectsNoteBoundary(await h.open(server, 1, create: true));
          opened.add(b);
          ca = BudgetController(
            configuration: budgetConfiguration,
            financialData: (await a.inner.load()).data,
            noteBoundary: a,
          );
          cb = BudgetController(
            configuration: budgetConfiguration,
            financialData: (await b.inner.load()).data,
            noteBoundary: b,
          );
          ready = true;
        } finally {
          if (!ready) {
            for (final o in opened) {
              await o.close();
            }
            await h.close();
          }
        }
      });
      if (!ready) return;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildQestoTheme(),
            home: Scaffold(
              body: Row(
                children: [
                  Expanded(child: NoteHost('A', ca, () {}, () {})),
                  Expanded(child: NoteHost('B', cb, () {}, () {})),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await ca.setTransactionNote(
            'container-tx-0',
            'Forward ☕',
            commandId: 'four-f-a',
          );
          expect(ca.lastNotePublicationWasDelta, isTrue);
          expect(a.fullReloads, 0);
          expect((await a.inner.pending()).length, 1);
          expect(await b.inner.pending(), isEmpty);
        });
        await tester.pump();
        expect(find.text('Forward ☕'), findsOneWidget);
        await tester.runAsync(() async {
          await ca.syncTransactionNotes();
          await cb.syncTransactionNotes();
        });
        await tester.pump();
        expect(find.text('Forward ☕'), findsNWidgets(2));
        await tester.runAsync(() async {
          expect(await b.inner.pending(), isEmpty);
          await cb.setTransactionNote(
            'container-tx-0',
            'Reverse ✓',
            commandId: 'four-f-b',
          );
          expect(cb.lastNotePublicationWasDelta, isTrue);
          // Exact durable command replay: owner returns a verified full fallback,
          // never executes a second command or sends a fabricated partial result.
          final before = (await b.inner.load()).revision;
          final duplicate = await b.commitDelta(
            TransactionNoteIntent(
              commandId: 'four-f-b',
              transactionId: 'container-tx-0',
              note: 'Reverse ✓',
              expectedRevision: before - 1,
            ),
          );
          expect(duplicate, isNull);
          expect((await b.inner.load()).revision, before);
          await expectLater(
            b.commitDelta(
              TransactionNoteIntent(
                commandId: 'four-f-b',
                transactionId: 'container-tx-0',
                note: 'collision',
                expectedRevision: before - 1,
              ),
            ),
            throwsA(isA<NoteBoundaryFailure>()),
          );
          await cb.syncTransactionNotes();
          await ca.syncTransactionNotes();
        });
        await tester.pump();
        expect(find.text('Reverse ✓'), findsNWidgets(2));
        await tester.runAsync(() async {
          await ca.setTransactionNote(
            'container-tx-1',
            'ACK survival',
            commandId: 'four-f-lost',
          );
          server.fault('four-f-lost', 'after-commit', 'drop-response');
          try {
            await ca.syncTransactionNotes();
          } on NoteBoundaryFailure {
            /* server durable receipt is recovered by retry */
          }
          server.clearFault();
          // Sync transport failure may require a fresh controller, never a second
          // writer. The existing owner remains the sole native connection here.
          if (ca.noteRecoveryRequired) {
            final loaded = await a.inner.load();
            ca.dispose();
            ca = BudgetController(
              configuration: budgetConfiguration,
              financialData: loaded.data,
              noteBoundary: a,
              initialNoteRevision: loaded.revision,
            );
          }
          await ca.syncTransactionNotes();
          await cb.syncTransactionNotes();
          final beforeRepeat = codec.encode((await b.inner.load()).data);
          await cb.syncTransactionNotes(pushPending: false);
          expect(codec.encode((await b.inner.load()).data), beforeRepeat);
          expect(await a.inner.pending(), isEmpty);
          expect(await b.inner.pending(), isEmpty);
          final sa = (await a.inner.load()).data,
              sb = (await b.inner.load()).data;
          final actual = jsonDecode(codec.encode(ca.mergeInto(sa)));
          expect(actual, jsonDecode(codec.encode(cb.mergeInto(sb))));
          expect(actual, (await h.serverState())['state']);
          File('../results/two-clients.json').writeAsStringSync(
            jsonEncode({
              'passed': true,
              'rendered_hosts': 2,
              'full_codec_v7_server_parity': true,
              'bidirectional': true,
              'lost_ack_recovered': true,
              'repeat_pull_unchanged': true,
              'duplicate_command_no_write': true,
              'incoming_outbox': 0,
              'remote_path':
                  'unchanged full authoritative validation and full UI reload',
              'protocol': 'v1 unchanged',
            }),
          );
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        ca.dispose();
        cb.dispose();
        await tester.runAsync(() async {
          for (final o in opened) {
            await o.close(cancelPending: true);
          }
          await h.close();
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
