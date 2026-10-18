import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto/synoball/adapters/qesto_legacy_bridge.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_synthetic_sync/domain.dart' show CommandIds;
import 'package:qesto_synthetic_sync/domain_executor.dart';
import 'package:qesto_synthetic_sync/protocol.dart';
import 'package:qesto_storage_spike/synthetic_trace.dart';

/// One application domain path used locally, on the server, and for replay.
/// It delegates to the actual Qesto preparation; no financial rule is redefined.
class QestoNoteExecutor extends SyncDomainExecutor {
  const QestoNoteExecutor();
  static const profile = 'qesto.note.v1';
  static const codec = UserFinancialDataCodec();
  T phase<T>(String name, T Function() work, {int bytes = 0}) => SyntheticTrace.sync('executor.$name', work);
  @override
  String entityFor(String owner) =>
      const QestoLegacyBridge().entityIdFor(owner);
  UserFinancialData data(String stored, String owner) {
    final d = phase(
      'codec_decode',
      () => codec.decode(stored),
      bytes: stored.length,
    );
    if (!owner.startsWith('synthetic-4a-') ||
        d.user.id != owner ||
        d.synoballState == null ||
        d.synoballState!.transactions.any(
          (t) => t.entityId != entityFor(owner),
        )) {
      throw const ApiError(403, 'QESTO_SYNTHETIC_BINDING_MISMATCH');
    }
    return d;
  }

  @override
  SynoballState read(String stored, String owner) =>
      data(stored, owner).synoballState!;
  String policyDigest(String stored, String owner) => digest({
    'profile': profile,
    'user': owner,
    'entity': entityFor(owner),
    'policy': data(stored, owner).classification.toJson(),
  });
  @override
  void validateCommand(String stored, NoteCommand command, String owner) {
    final d = data(stored, owner);
    final target = d.synoballState!.transactions
        .where((t) => t.id == command.target)
        .firstOrNull;
    if (target == null) throw const ApiError(404, 'TRANSACTION_NOT_FOUND');
    if (target.status == CanonicalTransactionStatus.deleted)
      throw const ApiError(409, 'TRANSACTION_DELETED');
    if (d.transactions.every((t) => t.id != command.target))
      throw const ApiError(409, 'TRANSACTION_NOT_VISIBLE');
  }

  @override
  ExecutedDomainState execute(
    String stored,
    NoteCommand command,
    String owner,
    DateTime time,
  ) {
    validateCommand(stored, command, owner);
    final prepared = phase(
      'synoball_policy_projections',
      () => prepareTransactionNote(
        data(stored, owner),
        command.target,
        command.note,
        ids: CommandIds(command.changeId),
        clock: _ExecutionTime(time).now,
      ),
    );
    return ExecutedDomainState(
      phase('codec_encode', () => codec.encode(prepared.data)),
      prepared.core.state,
    );
  }

  @override
  Map<String, dynamic> metadata(String stored, String owner) => {
    'financial_profile': profile,
    'policy_digest': policyDigest(stored, owner),
  };
  @override
  Map<String, dynamic> effect(
    String before,
    ExecutedDomainState after,
    NoteCommand command,
    String owner,
    DateTime time,
  ) => {
    'domain_effect': {
      ...metadata(before, owner),
      'command': command.body,
      'executed_at': time.toIso8601String(),
      'before_core_digest': digest(read(before, owner).toJson()),
      'after_core_digest': digest(after.core.toJson()),
    },
  };
}

class _ExecutionTime {
  const _ExecutionTime(this.value);
  final DateTime value;
  DateTime now() => value;
}
