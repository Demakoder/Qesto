import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_coordinator_domain.dart';
import 'measure.dart';

/// Two exact-input decoded values per owner/executor. No persisted alternate
/// model, cross-tenant reuse, partial execution, skipped rules or replay cache.
class CachedNoteExecutor extends QestoNoteExecutor {
  final _entries = <({String owner, String source, UserFinancialData data})>[];
  final measurements = Measurements();
  final observations = <String, List<Map<String, int>>>{};
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
    for (final e in _entries) {
      if (e.owner == owner && e.source == stored) return e.data;
    }
    final value = super.data(
      stored,
      owner,
    ); // all binding/schema checks retained
    if (_entries.length == 2) _entries.removeAt(0);
    _entries.add((owner: owner, source: stored, data: value));
    return value;
  }
}

class IncrementalCoordinatorDomain extends QestoCoordinatorDomain {
  IncrementalCoordinatorDomain(
    super.owner,
    super.workspace,
    super.epoch,
    super.policyDigest,
    super.devices,
  );
  @override
  final CachedNoteExecutor executor = CachedNoteExecutor();
}
