import 'dart:convert';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'profile_adapter.dart';

class PreparedLocalNote {
  const PreparedLocalNote(this.snapshot, this.intentJson);
  final FinancialSnapshot snapshot;
  final String intentJson;
}

abstract class CoordinatorDomain {
  const CoordinatorDomain();
  String entityFor(String owner) => owner;
  void validateHeader(Map<String, dynamic> response) {}
  w.NoteCommand command(PendingCommand p);
  PreparedLocalNote prepare(
    FinancialSnapshot before,
    w.NoteCommand command,
    String owner,
    DateTime time,
  );
  FinancialSnapshot incoming(
    FinancialSnapshot before,
    Map<String, dynamic> bundle,
    String owner,
  );
  FinancialSnapshot project(
    FinancialSnapshot local,
    FinancialSnapshot shadow,
    List<PendingCommand> remaining,
    String owner,
  );
}

class LegacyCoordinatorDomain extends CoordinatorDomain {
  const LegacyCoordinatorDomain();
  @override
  w.NoteCommand command(PendingCommand p) =>
      w.NoteCommand.parse(w.object(jsonDecode(p.immutableJson))['intent']);
  @override
  PreparedLocalNote prepare(
    FinancialSnapshot before,
    w.NoteCommand command,
    String owner,
    DateTime time,
  ) => PreparedLocalNote(
    ProfileAdapter.note(before, command, owner, time),
    jsonEncode(command.body),
  );
  @override
  FinancialSnapshot incoming(
    FinancialSnapshot before,
    Map<String, dynamic> bundle,
    String owner,
  ) => ProfileAdapter.incoming(
    before,
    (bundle['entities'] as List).map(w.object),
  );
  @override
  FinancialSnapshot project(
    FinancialSnapshot local,
    FinancialSnapshot shadow,
    List<PendingCommand> remaining,
    String owner,
  ) => ProfileAdapter.project(local, shadow, {
    for (final p in remaining) command(p).target,
  });
}
