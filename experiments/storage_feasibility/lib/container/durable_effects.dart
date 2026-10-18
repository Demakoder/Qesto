part of 'sqlite_container.dart';

/// Local-only experimental envelope. Wire protocol v1 remains inside `intent`.
/// Effects are persisted in the immutable command row, in the SAME transaction
/// as state, journal/revision and delivery/outbox. No schema migration required.
final class EffectsCommitRequest {
  EffectsCommitRequest({
    required Mutation mutation,
    required String effectsJson,
    required Map<String, Object?> binding,
    required this.storageGeneration,
  }) : effectsJson = canonicalJson(jsonDecode(effectsJson)),
       bindingJson = canonicalJson(binding) {
    final b = jsonDecode(bindingJson) as Map;
    final profile = jsonDecode(mutation.snapshot.json) as Map;
    final effects = jsonDecode(this.effectsJson) as Map;
    final core = effects['core'] as Map;
    final app = effects['app'] as Map;
    if (b['commandId'] != mutation.id ||
        b['kind'] != 'transaction.set_note' ||
        b['workspace'] != mutation.partition.workspace ||
        b['lineage'] != mutation.partition.lineage ||
        b['baseRevision'] != mutation.expectedRevision ||
        b['revision'] != mutation.expectedRevision + 1 ||
        b['user'] != (profile['user'] as Map)['id'] ||
        effects['user'] != b['user'] ||
        b['domainVersion'] != '1.0.0' ||
        b['coverage'] != 'core-and-app-note-v1' ||
        b['generation'] is! int ||
        (b['generation'] as int) < 0 ||
        b['policyFingerprint'] is! String ||
        (b['policyFingerprint'] as String).isEmpty ||
        b['snapshotDigest'] != mutation.snapshot.hash ||
        b['effectsDigest'] != digest(this.effectsJson) ||
        b['preparedIdentity'] !=
            digest(
              canonicalJson({
                'effects': b['effectsDigest'],
                'snapshot': mutation.snapshot.hash,
              }),
            ) ||
        storageGeneration < 1 ||
        effects['contract'] != 'qesto.prepared-financial-commit.v1' ||
        core['contract'] != 'qesto.experimental-core-effects.v1' ||
        core['version'] != 1 ||
        core['coreCollectionsComplete'] != true ||
        core['policyChangedDuringExecution'] != false ||
        app['contract'] != 'qesto.note-app-effects.v1' ||
        app['coverage'] != 'requiresDerivedRebuild' ||
        app['unknownDependencies'] is! List ||
        (app['unknownDependencies'] as List).isNotEmpty ||
        canonicalJson((effects['core'] as Map)['binding']) !=
            canonicalJson({
              for (final key in [
                'commandId',
                'workspace',
                'lineage',
                'target',
                'kind',
                'baseRevision',
                'revision',
                'generation',
                'policyFingerprint',
                'domainVersion',
              ])
                key: b[key],
            })) {
      throw const ContractViolation('effects-binding');
    }
    final intent = jsonDecode(mutation.intentJson) as Map<String, dynamic>;
    if (intent.containsKey('_local_effects_v1'))
      throw const ContractViolation('reserved-effects-key');
    _mutation = Mutation(
      id: mutation.id,
      partition: mutation.partition,
      expectedRevision: mutation.expectedRevision,
      snapshot: mutation.snapshot,
      dependencies: mutation.dependencies,
      intentJson: canonicalJson({
        ...intent,
        '_local_effects_v1': {
          'binding': b,
          'effects': effects,
          'storageGeneration': storageGeneration,
        },
      }),
    );
  }
  final String effectsJson, bindingJson;
  final int storageGeneration;
  late final Mutation _mutation;
  String get commandId => _mutation.id;
  String get immutableDigest => digest(_mutation.immutableJson);
}

/// Not constructible, subclassable or implementable outside this library.
/// The unexported authority is valid only for one live verified container.
/// It is NOT a server acceptance receipt and is NOT serialized over SendPort.
final class DurableEffectsReceipt {
  DurableEffectsReceipt._(
    this._authority,
    this.commandId,
    this.revision,
    this.storageGeneration,
    this.bindingJson,
    this.commandDigest,
    this.manifestDigest,
    this.checkpoint,
  );
  final Object _authority;
  final String commandId, bindingJson, commandDigest, manifestDigest;
  final int revision, storageGeneration, checkpoint;
}

extension DurableEffectsContainer on SqliteContainer {
  Future<DurableEffectsReceipt> commitEffects(
    EffectsCommitRequest request,
  ) async {
    _usable();
    if (requiresReopen)
      throw const ContractViolation('effects-reopen-required');
    if (request.storageGeneration != generation)
      throw const ContractViolation('effects-storage-generation');
    _partition(request._mutation.partition);
    await commitMutation(request._mutation); // returns only AFTER native COMMIT
    try {
      fault?.call('effects-after-commit');
      return await _exclusive(() async => _issueEffectsReceipt(request));
    } catch (_) {
      _policy.poisoned =
          true; // durable outcome may exist; no speculative rollback
      rethrow;
    }
  }

  /// Recovery after a SAFE reopen, using exactly the old immutable request.
  /// Does not create a command and does not treat an absent command as success.
  Future<DurableEffectsReceipt> resolveEffects(EffectsCommitRequest request) =>
      _exclusive(() async => _issueEffectsReceipt(request));

  DurableEffectsReceipt _issueEffectsReceipt(EffectsCommitRequest request) {
    if (requiresReopen)
      throw const ContractViolation('effects-reopen-required');
    _partition(request._mutation.partition);
    if (request.storageGeneration != generation)
      throw const ContractViolation('effects-storage-generation');
    final row = _db.select('SELECT * FROM commands WHERE id=?', [
      request.commandId,
    ]);
    if (row.length != 1) throw const ContractViolation('effects-not-committed');
    final body = row.single['body'] as String;
    if (body != request._mutation.immutableJson ||
        digest(body) != row.single['digest']) {
      throw const ContractViolation('effects-command-mismatch');
    }
    final revision = row.single['revision'] as int;
    final state =
        _snapshot(); // verifies warm-cache guards and all changed chunks
    final journal = _db.select('SELECT * FROM journal WHERE revision=?', [
      revision,
    ]);
    final delivery = _db.select('SELECT * FROM delivery WHERE id=?', [
      request.commandId,
    ]);
    if (state.revision != revision ||
        revision != request._mutation.expectedRevision + 1 ||
        state.value.hash != request._mutation.snapshot.hash ||
        journal.length != 1 ||
        journal.single['kind'] != 'local' ||
        journal.single['reference'] != request.commandId ||
        journal.single['digest'] != state.value.hash ||
        delivery.length != 1) {
      throw const ContractViolation('effects-stale-or-incomplete');
    }
    final stored =
        _db.select('SELECT snapshot FROM state').single['snapshot'] as String;
    return DurableEffectsReceipt._(
      _effectsAuthority,
      request.commandId,
      revision,
      generation,
      request.bindingJson,
      digest(body),
      digest(stored),
      _cursor,
    );
  }

  Future<void> verifyEffectsReceipt(
    DurableEffectsReceipt receipt,
    EffectsCommitRequest request,
  ) => _exclusive(() async {
    if (!identical(receipt._authority, _effectsAuthority)) {
      throw const ContractViolation('effects-foreign-authority');
    }
    final actual = _issueEffectsReceipt(request);
    if (receipt.commandId != actual.commandId ||
        receipt.revision != actual.revision ||
        receipt.storageGeneration != actual.storageGeneration ||
        receipt.bindingJson != actual.bindingJson ||
        receipt.commandDigest != actual.commandDigest ||
        receipt.manifestDigest != actual.manifestDigest ||
        receipt.checkpoint != actual.checkpoint) {
      throw const ContractViolation('effects-receipt-mismatch');
    }
  });
}
