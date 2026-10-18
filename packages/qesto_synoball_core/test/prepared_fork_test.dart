import 'dart:convert';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:test/test.dart';
import 'runtime_contract_test.dart' show input;
import 'support/parity_scenarios.dart' show parityNow;

class _Ids extends SynoballIdFactory {
  _Ids(this.scope);
  final String scope;
  int nextId = 0;
  @override
  String next(String prefix) => '$prefix-$scope-${nextId++}';
}

void main() {
  test(
    'prepared fork isolates owned indexes, evidence and derived writes; full state parity',
    () {
      final source = SynoballCore(
        ids: _Ids('seed-core'),
        clock: () => parityNow,
      );
      source.ingest(StatementAdapter(ids: _Ids('seed-adapter')), input());
      final initial = jsonEncode(source.state.toJson());
      final now = parityNow.add(const Duration(days: 1));
      final fork = source.forkForCommand(ids: _Ids('cmd'), clock: () => now);
      final full = SynoballCore(
        initialState: source.state,
        ids: _Ids('cmd'),
        clock: () => now,
      );
      for (final core in [fork, full]) {
        final tx = core.transactions.single;
        core.updateTransaction(
          tx.copyWith(
            userNote: 'synthetic',
            userCategoryOverride: 'sport',
            tags: ['user-field:note', 'user-field:category'],
          ),
          actorId: 'synthetic',
        );
        core.ingest(StatementAdapter(ids: _Ids('repeat')), input());
        core.deleteTransaction(tx.id, actorId: 'synthetic');
        core.ingest(StatementAdapter(ids: _Ids('deleted-repeat')), input());
        core.restoreDeletedTransaction(tx.id, actorId: 'synthetic');
        core.setCategoryPolicy(
          const CategoryPolicy(redirects: {'sport': 'fitness'}),
        );
      }
      expect(fork.state.toJson(), full.state.toJson());
      expect(jsonEncode(source.state.toJson()), initial);
      expect(fork.transactions.single.updatedAt, now);
      expect(fork.transactions.single.amount.minorUnits, 486122);
      expect(fork.transactions.single.userCategoryOverride, 'fitness');
      expect(fork.state.auditEntries.last.id, startsWith('aud-cmd-'));
    },
  );
}
