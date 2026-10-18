import 'dart:convert';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_synthetic_sync/domain.dart' as domain;
import 'package:qesto_synthetic_sync/protocol.dart' as wire;

/// A transport adapter, not a codec, reconciliation engine or UI projection.
/// Root v7 fields are retained verbatim. Only existing canonical entities and
/// the corresponding legacy comment cache may change in this note-only slice.
class ProfileAdapter {
  static void _projectChangedNotes(
    Map<String, dynamic> data,
    List<dynamic> before,
    List<dynamic> after,
  ) {
    final prior = {for (final t in before) t['id']: t['userNote']};
    final changed = {
      for (final t in after)
        if (prior.containsKey(t['id']) && prior[t['id']] != t['userNote'])
          t['id']: t['userNote'],
    };
    data['transactions'] = [
      for (final raw in data['transactions'] as List)
        if (changed.containsKey(raw['id']))
          {...wire.object(raw), 'comment': changed[raw['id']]}
        else
          raw,
    ];
  }

  static Map<String, dynamic> root(FinancialSnapshot s) =>
      wire.object(jsonDecode(s.json));
  static SynoballState core(FinancialSnapshot s) =>
      SynoballState.fromJson(wire.object(root(s)['synoball']));

  static FinancialSnapshot withCore(
    FinancialSnapshot before,
    SynoballState state,
  ) {
    final data = root(before);
    final beforeTransactions = data['synoball']['transactions'] as List;
    data['synoball'] = state.toJson();
    _projectChangedNotes(
      data,
      beforeTransactions,
      data['synoball']['transactions'] as List,
    );
    return FinancialSnapshot(jsonEncode(data));
  }

  static FinancialSnapshot note(
    FinancialSnapshot before,
    wire.NoteCommand c,
    String owner,
    DateTime now,
  ) => withCore(before, domain.applyNote(core(before), c, owner, now));

  static CanonicalTransaction decodeEntity(Map<String, dynamic> e) {
    final t = wire.object(e['transaction']);
    final amount = wire.object(t['amount']);
    final units = amount['minor_units'];
    if (amount['scale'] != 2 ||
        units is! String ||
        !RegExp(r'^-?(0|[1-9][0-9]{0,17})$').hasMatch(units) ||
        amount['currency'] is! String)
      throw const ContractViolation('invalid-wire-money');
    return CanonicalTransaction.fromJson({
      ...t,
      'amount': Money(
        minorUnits: int.parse(units),
        currency: amount['currency'] as String,
      ).toJson(),
    });
  }

  static FinancialSnapshot incoming(
    FinancialSnapshot before,
    Iterable<Map<String, dynamic>> entities,
  ) {
    final data = root(before), state = wire.object(data['synoball']);
    final beforeTransactions = state['transactions'] as List;
    final transactions = beforeTransactions.map(wire.object).toList();
    final index = {
      for (var i = 0; i < transactions.length; i++) transactions[i]['id']: i,
    };
    for (final e in entities) {
      final t = decodeEntity(e), i = index[t.id];
      if (i == null) throw const ContractViolation('unsupported-remote-insert');
      final next = t.toJson(), old = transactions[i];
      // Fail closed if this note-only protocol starts mutating financial facts.
      // Exact allowlist of existing core-derived fields, plus the note/time.
      const allowed = {
        'userNote',
        'updatedAt',
        'fieldTrust',
        'merchantId',
        'merchantName',
        'merchantConfidence',
        'normalizedDescription',
        'synoballCategory',
        'categoryConfidence',
      };
      for (final key in {...old.keys, ...next.keys}) {
        if (!allowed.contains(key) &&
            canonicalJson(old[key]) != canonicalJson(next[key]))
          throw ContractViolation('unsupported-remote-field:$key');
      }
      transactions[i] = next;
    }
    state['transactions'] = transactions;
    data['synoball'] = state;
    // Do not roundtrip non-transaction provenance through a second serializer.
    _projectChangedNotes(data, beforeTransactions, transactions);
    return FinancialSnapshot(jsonEncode(data));
  }

  /// Preserve the latest local raw/provenance/root data; install server entity
  /// values, then retain complete locally edited targets with pending proposals.
  /// No command is rewritten or rebased. Same-target proposals stay conflicts.
  static FinancialSnapshot project(
    FinancialSnapshot local,
    FinancialSnapshot shadow,
    Set<String> pendingTargets,
  ) {
    final l = root(local), s = root(shadow);
    final localCore = wire.object(l['synoball']);
    final beforeTransactions = localCore['transactions'] as List;
    final localById = {
      for (final t in localCore['transactions'] as List) t['id']: t,
    };
    localCore['transactions'] = [
      for (final t in s['synoball']['transactions'] as List)
        if (pendingTargets.contains(t['id'])) localById[t['id']] else t,
    ];
    l['synoball'] = localCore;
    _projectChangedNotes(
      l,
      beforeTransactions,
      localCore['transactions'] as List,
    );
    return FinancialSnapshot(jsonEncode(l));
  }
}
