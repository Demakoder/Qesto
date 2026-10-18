import 'dart:convert';
import 'package:test/test.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import '../lib/oracle.dart';
import 'journal_test.dart' show binding, time;

class CustomPolicy extends CategoryPolicy {}

class CustomEvent extends SynoballEvent {
  CustomEvent()
    : super(
        id: 'custom',
        type: 'probe',
        entityId: 'synthetic',
        occurredAt: time,
      );
}

CoreJournalPreparation admit(
  SynoballState state, {
  CategoryPolicy policy = const CategoryPolicy(),
}) => CoreJournalPreparation.fromState(
  initialState: state,
  policy: policy,
  binding: binding('boundary'),
  ids: CommandIds('boundary'),
  clock: () => time,
  execute: (_) => null,
);

SynoballEvent event(Object value) => SynoballEvent(
  id: 'evt',
  type: 'probe',
  entityId: 'synthetic',
  occurredAt: time,
  payload: {'number': value},
);

void main() {
  test(
    'unreviewed model/policy subclasses fail closed only in journal path',
    () {
      expect(
        () => admit(const SynoballState(), policy: CustomPolicy()),
        throwsUnsupportedError,
      );
      expect(
        () => admit(SynoballState(events: [CustomEvent()])),
        throwsUnsupportedError,
      );
      // Public default constructor still supports the original APIs.
      expect(
        SynoballCore(categoryPolicy: CustomPolicy()).state.transactions,
        isEmpty,
      );
    },
  );
  test('nonfinite event JSON is rejected, not silently converted or reset', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => admit(SynoballState(events: [event(value)])),
        throwsStateError,
      );
    }
  });
  test(
    'full oracle distinguishes numeric representation in nested payload',
    () {
      final before = SynoballState(events: [event(1)]);
      final p = admit(before);
      verifyJournal(before, p.state, p.journal);
      final corrupted = SynoballState.fromJson(
        jsonDecode(jsonEncode(p.state.toJson())),
      );
      corrupted.events.single.payload['number'] = 1.0;
      expect(
        () => verifyJournal(before, corrupted, p.journal),
        throwsStateError,
      );
    },
  );
}
