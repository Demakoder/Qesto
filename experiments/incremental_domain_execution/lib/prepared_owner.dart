import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto/features/transaction_import/services/sber_transaction_projection.dart';
import 'package:qesto/synoball/analytics/qesto_read_model.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_synthetic_sync/protocol.dart';

/// One isolated, explicitly bound domain owner. Full projections remain the
/// production implementations. No publication before a durable receipt.
class PreparedDomainOwner {
  PreparedDomainOwner(this.workspace, this.lineage, this.user);
  final String workspace, lineage, user;
  SynoballCore? _core;
  UserFinancialData? _data;
  int? _revision;
  String? _policy;
  int _generation = 0;
  static const codec = UserFinancialDataCodec();
  int fullLoads = 0, forks = 0;

  void loadVerified(UserFinancialData data, int revision) {
    invalidate();
    if (!user.startsWith('synthetic-4a-') ||
        data.user.id != user ||
        data.synoballState == null ||
        revision < 0 ||
        data.synoballState!.transactions.any(
          (t) => t.entityId != 'ent-$user',
        )) {
      throw StateError('owner binding');
    }
    _data = data;
    _revision = revision;
    _policy = digest(data.classification.toJson());
    _core = SynoballCore(
      initialState: data.synoballState!,
      categoryPolicy: data.classification.policy,
    );
    fullLoads++;
  }

  PreparedDomainCommand prepare(
    NoteCommand command,
    int expectedRevision,
    DateTime time,
    String policyFingerprint,
  ) {
    if (_core == null ||
        _revision != expectedRevision ||
        command.workspace != workspace ||
        command.epoch != lineage ||
        policyFingerprint != _policy) {
      throw StateError('stale-domain-owner');
    }
    final before = _data!;
    final shown = before.transactions
        .where((t) => t.id == command.target)
        .firstOrNull;
    if (shown == null) throw StateError('visible target required');
    final fork = _core!.forkForCommand(
      ids: CommandIds(command.changeId),
      clock: () => time,
    );
    forks++;
    if (!applyQestoTransactionEdit(
      fork,
      shown.copyWith(comment: command.note),
      actorId: user,
      displayed: shown,
    ))
      throw StateError('missing target');
    final state = fork.state;
    final read = const QestoReadModelService().build(state);
    final after = before.copyWith(
      synoballState: state,
      accounts: read.accounts,
      transactions: projectSberTransactions(
        read.transactions,
        before.classification.policy,
      ).toList(),
    );
    return PreparedDomainCommand._(
      this,
      command.changeId,
      expectedRevision,
      before,
      after,
      fork,
      policyFingerprint,
      _generation,
    );
  }

  void acceptDurable(
    PreparedDomainCommand prepared, {
    required int revision,
    required String durableJson,
    required String commandId,
  }) {
    if (!identical(prepared._owner, this) ||
        prepared.generation != _generation ||
        _revision != prepared.baseRevision ||
        revision != prepared.baseRevision + 1 ||
        commandId != prepared.commandId ||
        _policy != prepared.policy ||
        codec.encode(prepared.after) != durableJson) {
      invalidate();
      throw StateError('durable receipt/state mismatch');
    }
    _data = prepared.after;
    _core = prepared.core;
    _revision = revision;
    _generation++;
  }

  void invalidate() {
    _generation++;
    _core = null;
    _data = null;
    _revision = null;
    _policy = null;
  }

  UserFinancialData get current =>
      _data ?? (throw StateError('owner unloaded'));
}

class PreparedDomainCommand {
  PreparedDomainCommand._(
    this._owner,
    this.commandId,
    this.baseRevision,
    this.before,
    this.after,
    this.core,
    this.policy,
    this.generation,
  );
  final PreparedDomainOwner _owner;
  final String commandId, policy;
  final int baseRevision;
  final int generation;
  final UserFinancialData before, after;
  final SynoballCore core;
}
