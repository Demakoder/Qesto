import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_synthetic_sync/domain.dart' show CommandIds;
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';

void main() {
  test(
    'STOP GATE actual BudgetController default path equals server executor with all audit/event/tags values',
    () async {
      final initial = syntheticFixture(
        fixturePath:
            '../../storage_feasibility/test/fixtures/container_profile_v7.json',
      );
      final time = DateTime.utc(2026, 10, 13);
      const codec = UserFinancialDataCodec(), executor = QestoNoteExecutor();
      final c = BudgetController(
        configuration: budgetConfiguration,
        financialData: initial,
        synoballClock: () => time,
        synoballIds: CommandIds('actual-controller'),
      );
      try {
        final cmd = w.NoteCommand.parse({
          'protocol_version': 1,
          'domain_version': 1,
          'workspace_id': 'synthetic-4a-gate',
          'device_id': 'synthetic-4a-device',
          'workspace_epoch': 'synthetic-4a-epoch',
          'change_id': 'actual-controller',
          'kind': 'transaction.set_note',
          'transaction_id': 'container-tx-0',
          'base_revision': '0',
          'note': 'Actual controller note',
        });
        await c.updateTransaction(
          c.transactions.first.copyWith(comment: cmd.note),
        );
        final result = executor.execute(
          codec.encode(initial),
          cmd,
          syntheticUser,
          time,
        );
        expect(
          jsonDecode(codec.encode(c.mergeInto(initial))),
          jsonDecode(result.stored),
        );
        expect(c.synoballState.toJson(), result.core.toJson());
        File('../results/controller-semantic-gate.json').writeAsStringSync(
          jsonEncode({
            'passed': true,
            'actual_controller': true,
            'tags_audit_events_full_equality': true,
            'clock_ids_controlled': true,
            'network_used': false,
          }),
          flush: true,
        );
      } finally {
        c.dispose();
      }
    },
  );
}
