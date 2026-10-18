import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_coordinator_domain.dart';
import 'package:qesto_incremental_sync_experiment/measure.dart';

/// Admission budget in estimated bytes, NOT a promise bounding process RSS.
/// Large documents execute the unchanged full path without retained decode cache.
/// One exact source per owner; schema/entity validation runs on every miss.
class BoundedNoteExecutor extends QestoNoteExecutor {
  BoundedNoteExecutor({this.budgetBytes = 32 * 1024 * 1024});
  final int budgetBytes;
  ({String owner, String source, UserFinancialData value})? _entry;
  int retainedEstimate = 0, hits = 0, misses = 0, rejected = 0;
  final measurements = Measurements();
  final observations = <String, List<Map<String, int>>>{};
  static int estimate(String source) => source.length * 16;
  void clear() {
    _entry = null;
    retainedEstimate = 0;
  }

  @override
  T phase<T>(String name, T Function() work, {int bytes = 0}) =>
      measurements.run(name, work, bytes: bytes);
  @override
  void observe(String phase, int micros, {int bytes = 0, int entities = 0}) =>
      observations.putIfAbsent(phase, () => []).add({
        'wall_us': micros,
        'bytes': bytes,
        'entities': entities,
      });
  @override
  UserFinancialData data(String stored, String owner) {
    final entry = _entry;
    if (entry != null && entry.owner == owner && entry.source == stored) {
      hits++;
      return entry.value;
    }
    clear(); // drop old graphs BEFORE allocating the replacement
    misses++;
    final value = super.data(stored, owner);
    final cost = estimate(stored);
    if (cost <= budgetBytes) {
      _entry = (owner: owner, source: stored, value: value);
      retainedEstimate = cost;
    } else {
      rejected++;
    }
    return value;
  }
}

class BoundedCoordinatorDomain extends QestoCoordinatorDomain {
  BoundedCoordinatorDomain(
    super.owner,
    super.workspace,
    super.epoch,
    super.policyDigest,
    super.devices,
  );
  @override
  final executor = BoundedNoteExecutor();
}
