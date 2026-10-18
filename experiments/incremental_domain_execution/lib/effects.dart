import 'dart:convert';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as wire;

/// Local-only v1 effect envelope, produced by the existing full executor/oracle.
/// NOT network JSON Patch and NOT an alternative financial execution algorithm.
/// Captures all codec roots/core collections, including unexpected changed roots.
class DomainEffectsV1 {
  DomainEffectsV1._(
    this.commandId,
    this.workspace,
    this.lineage,
    this.target,
    this.baseRevision,
    this.revision,
    this.policyFingerprint,
    this.roots,
    this.coreCollections,
    this.canonicalFields,
    this.beforeDigest,
  );
  final String commandId, workspace, lineage, target, policyFingerprint;
  final int baseRevision, revision;
  final String beforeDigest;
  final Map<String, Object?> roots;
  final Map<String, Object?> coreCollections;
  final Map<String, List<String>> canonicalFields;
  static const version = 1;
  factory DomainEffectsV1.between(
    UserFinancialData before,
    UserFinancialData after,
    wire.NoteCommand command, {
    required int baseRevision,
  }) {
    if (before.user.id != after.user.id || baseRevision < 0) {
      throw StateError('effect binding');
    }
    const codec = UserFinancialDataCodec();
    final a = jsonDecode(codec.encode(before)) as Map<String, dynamic>;
    final b = jsonDecode(codec.encode(after)) as Map<String, dynamic>;
    final roots = <String, Object?>{};
    final core = <String, Object?>{};
    for (final key in {...a.keys, ...b.keys}) {
      if (wire.canonicalJson(a[key]) != wire.canonicalJson(b[key])) {
        roots[key] = b[key];
      }
    }
    final sa = a['synoball'] as Map, sb = b['synoball'] as Map;
    for (final key in {...sa.keys, ...sb.keys}.cast<String>()) {
      if (wire.canonicalJson(sa[key]) != wire.canonicalJson(sb[key])) {
        core[key] = sb[key];
      }
    }
    final prior = {
      for (final t in sa['transactions'] as List) t['id']: t as Map,
    };
    final fields = <String, List<String>>{};
    for (final t in sb['transactions'] as List) {
      final old = prior.remove(t['id']) ?? {};
      final changed = <String>[
        for (final key in {...old.keys, ...(t as Map).keys}.cast<String>())
          if (wire.canonicalJson(old[key]) != wire.canonicalJson(t[key])) key,
      ];
      if (changed.isNotEmpty) fields[t['id'] as String] = changed;
    }
    for (final id in prior.keys) {
      fields[id as String] = ['__removed__'];
    }
    return DomainEffectsV1._(
      command.changeId,
      command.workspace,
      command.epoch,
      command.target,
      baseRevision,
      baseRevision + 1,
      wire.digest(before.classification.toJson()),
      _freeze(roots) as Map<String, Object?>,
      _freeze(core) as Map<String, Object?>,
      Map.unmodifiable({
        for (final e in fields.entries)
          e.key: List<String>.unmodifiable(e.value),
      }),
      wire.digest(a),
    );
  }
  Map<String, Object?> toJson() => {
    'contract': 'qesto.local-domain-effects.v1', 'version': version,
    'commandId': commandId, 'workspace': workspace, 'lineage': lineage,
    'target': target, 'baseRevision': baseRevision, 'revision': revision,
    'policyFingerprint': policyFingerprint,
    'beforeDigest': beforeDigest,
    'changedRoots': roots.keys.toList(),
    'changedCoreCollections': coreCollections.keys.toList(),
    'canonicalFields': canonicalFields,
    'invalidations': [
      'financial-read-model',
      'analytics',
      'recurring',
      'presentation',
    ],
    // No alias-producing command is supported. Unknown command kinds reject in
    // NoteCommand.parse. Complete collections above include evidence and trash.
    'identityAliases': <String, String>{},
    'capture': 'full-oracle-diff; not a hot-path incremental claim',
  };
  UserFinancialData reconstruct(UserFinancialData before) {
    const codec = UserFinancialDataCodec();
    final root = jsonDecode(codec.encode(before)) as Map<String, dynamic>;
    if (wire.digest(root) != beforeDigest)
      throw StateError('stale effect base');
    root.addAll(roots);
    return codec.decode(jsonEncode(root));
  }
}

Object? _freeze(Object? v) {
  if (v is Map)
    return Map<String, Object?>.unmodifiable({
      for (final e in v.entries) e.key as String: _freeze(e.value),
    });
  if (v is List) return List<Object?>.unmodifiable(v.map(_freeze));
  return v;
}
