import 'dart:convert';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'domain.dart';
import 'protocol.dart';

class ExecutedDomainState {
  const ExecutedDomainState(this.stored, this.core);
  final String stored;
  final SynoballState core;
}

/// Optional domain port. Existing 3a callers keep the identical legacy executor.
abstract class SyncDomainExecutor {
  const SyncDomainExecutor();
  void observe(String phase, int micros, {int bytes = 0, int entities = 0}) {}
  String entityFor(String user) => user;
  SynoballState read(String stored, String owner);
  void validateCommand(String stored, NoteCommand command, String owner) {}
  ExecutedDomainState execute(
    String stored,
    NoteCommand command,
    String owner,
    DateTime time,
  );
  Map<String, dynamic> metadata(String stored, String owner) => {};
  Map<String, dynamic> effect(
    String before,
    ExecutedDomainState after,
    NoteCommand command,
    String owner,
    DateTime time,
  ) => {};
}

class LegacySyncDomainExecutor extends SyncDomainExecutor {
  const LegacySyncDomainExecutor();
  @override
  SynoballState read(String stored, String owner) =>
      SynoballState.fromJson(object(jsonDecode(stored)));
  @override
  ExecutedDomainState execute(
    String stored,
    NoteCommand command,
    String owner,
    DateTime time,
  ) {
    final next = applyNote(read(stored, owner), command, owner, time);
    return ExecutedDomainState(jsonEncode(next.toJson()), next);
  }
}
