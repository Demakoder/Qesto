import 'dart:convert';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';

/// Independent full state verifier, NEVER part of recording or execution.
/// Replays positional writes and compares every root/value with the old path.
Map<String, dynamic> replayJournal(
  SynoballState before,
  CoreEffectsJournal journal, {
  bool dropLastForNegativeTest = false,
}) {
  final json = jsonDecode(jsonEncode(before.toJson())) as Map<String, dynamic>;
  final writes = dropLastForNegativeTest
      ? journal.writes.take(journal.writes.length - 1)
      : journal.writes;
  for (final effect in writes) {
    final list = json[effect.collection] as List;
    if (effect.before != null) {
      if (effect.index >= list.length ||
          !_equal(list[effect.index], effect.before)) {
        throw StateError(
          'Journal precondition: ${effect.collection}/${effect.index}',
        );
      }
      if (effect.after == null) {
        list.removeAt(effect.index);
      } else {
        list[effect.index] = effect.after;
      }
    } else {
      if (effect.index != list.length) throw StateError('Journal append order');
      list.add(effect.after);
    }
  }
  return json;
}

void verifyJournal(
  SynoballState before,
  SynoballState after,
  CoreEffectsJournal journal, {
  bool dropLastForNegativeTest = false,
}) {
  if (!_equal(
    replayJournal(
      before,
      journal,
      dropLastForNegativeTest: dropLastForNegativeTest,
    ),
    after.toJson(),
  )) {
    throw StateError('Incomplete journal: full core state differs');
  }
}

bool _equal(Object? a, Object? b) {
  if (a is num && b is num) return a.runtimeType == b.runtimeType && a == b;
  if (a is Map && b is Map)
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_equal(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
