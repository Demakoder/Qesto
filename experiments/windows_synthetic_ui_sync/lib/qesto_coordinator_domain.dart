import 'dart:convert';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_synthetic_sync/domain.dart' show transactionWire;
import 'package:qesto_encrypted_sync_experiment/coordinator_domain.dart';
import 'qesto_note_executor.dart';

/// Incoming effects are verified by exact common-executor replay, including ALL
/// tags, audit/events, money and derived effects. No protected-field exemptions.
class QestoCoordinatorDomain extends CoordinatorDomain {
  const QestoCoordinatorDomain(
    this.owner,
    this.workspace,
    this.epoch,
    this.policyDigest,
    this.devices,
  );
  final String owner, workspace, epoch, policyDigest;
  final List<String> devices;
  QestoNoteExecutor get executor => const QestoNoteExecutor();
  @override
  String entityFor(String owner) => executor.entityFor(owner);
  @override
  void validateHeader(Map<String, dynamic> r) {
    if (r['financial_profile'] != QestoNoteExecutor.profile ||
        r['policy_digest'] != policyDigest) {
      throw const ContractViolation('financial-semantics-mismatch');
    }
  }

  Map<String, dynamic> _intent(PendingCommand p) =>
      w.object(w.object(jsonDecode(p.immutableJson))['intent']);
  @override
  w.NoteCommand command(PendingCommand p) =>
      w.NoteCommand.parse(_intent(p)['wire']);
  void _bound(w.NoteCommand c) {
    if (c.workspace != workspace ||
        c.epoch != epoch ||
        !devices.contains(c.device)) {
      throw const ContractViolation('domain-command-binding');
    }
  }

  @override
  PreparedLocalNote prepare(
    FinancialSnapshot before,
    w.NoteCommand command,
    String owner,
    DateTime time,
  ) {
    _bound(command);
    final result = executor.execute(before.json, command, owner, time.toUtc());
    return PreparedLocalNote(
      FinancialSnapshot(result.stored),
      jsonEncode({
        'wire': command.body,
        'financial_profile': QestoNoteExecutor.profile,
        'policy_digest': policyDigest,
        'executed_at': time.toUtc().toIso8601String(),
      }),
    );
  }

  @override
  FinancialSnapshot incoming(
    FinancialSnapshot before,
    Map<String, dynamic> bundle,
    String owner,
  ) {
    final receipt = w.object(bundle['receipt']);
    if (receipt['status'] == 'conflict') return before;
    final effect = w.object(bundle['domain_effect']);
    validateHeader(effect);
    final cmd = w.NoteCommand.parse(effect['command']);
    _bound(cmd);
    if (cmd.changeId != receipt['change_id'] ||
        cmd.target != receipt['transaction_id'] ||
        cmd.contentDigest != receipt['content_digest']) {
      throw const ContractViolation('domain-effect-receipt-mismatch');
    }
    // Bind peer commands too, not only receipts for this device's outbox.
    if (w.decimal(receipt['revision']) != cmd.baseRevision + 1) {
      throw const ContractViolation('domain-command-revision-mismatch');
    }
    if (effect['before_core_digest'] !=
        w.digest(executor.read(before.json, owner).toJson())) {
      throw const ContractViolation('domain-before-state-mismatch');
    }
    final time = DateTime.parse(effect['executed_at'] as String);
    if (!time.isUtc || time.toIso8601String() != effect['executed_at'])
      throw const ContractViolation('domain-time-mismatch');
    final result = executor.execute(before.json, cmd, owner, time);
    if (effect['after_core_digest'] != w.digest(result.core.toJson()))
      throw const ContractViolation('domain-after-state-mismatch');
    final previous = {
      for (final t in executor.read(before.json, owner).transactions) t.id: t,
    };
    final expected = {
      for (final t in result.core.transactions)
        if (canonicalJson(previous[t.id]!.toJson()) !=
            canonicalJson(t.toJson()))
          t.id: transactionWire(t),
    };
    // A no-op receipt still publishes its target revision, as in existing 3a.
    if (!expected.containsKey(cmd.target))
      expected[cmd.target] = transactionWire(
        result.core.transactions.firstWhere((t) => t.id == cmd.target),
      );
    final actual = {
      for (final raw in bundle['entities'] as List)
        (raw['transaction'] as Map)['id']: raw['transaction'],
    };
    if (canonicalJson(expected) != canonicalJson(actual))
      throw const ContractViolation('domain-entity-effect-mismatch');
    return FinancialSnapshot(result.stored);
  }

  @override
  FinancialSnapshot project(
    FinancialSnapshot local,
    FinancialSnapshot shadow,
    List<PendingCommand> remaining,
    String owner,
  ) {
    var result = shadow;
    // Replay only outstanding note proposals using their unchanged original
    // intent and local clock. Conflicts remain in outbox; shadow stays authoritative.
    for (final p in remaining) {
      final intent = _intent(p);
      validateHeader(intent);
      final cmd = command(p);
      _bound(cmd);
      final time = DateTime.parse(intent['executed_at'] as String);
      result = FinancialSnapshot(
        executor.execute(result.json, cmd, owner, time).stored,
      );
    }
    // Local unrelated v7 root fields/provenance remain byte-value equivalent.
    final l = w.object(jsonDecode(local.json)),
        r = w.object(jsonDecode(result.json));
    for (final key in l.keys.where(
      (k) => k != 'synoball' && k != 'transactions' && k != 'accounts',
    )) {
      if (canonicalJson(l[key]) != canonicalJson(r[key]))
        throw ContractViolation('unrelated-root-mismatch:$key');
      r[key] = l[key];
    }
    return FinancialSnapshot(jsonEncode(r));
  }
}
