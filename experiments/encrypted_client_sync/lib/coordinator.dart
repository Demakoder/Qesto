import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/synthetic_trace.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'profile_adapter.dart';
import 'coordinator_domain.dart';
import 'transport.dart';

typedef SyntheticLocalCommit =
    Future<CommandReceipt> Function(
      w.NoteCommand command,
      VersionedSnapshot before,
      DateTime time,
      Future<void> Function()? beforeCommit,
    );

class Coordinator {
  Coordinator(
    this.store,
    this.partition,
    this.principal,
    this.request, {
    this.domain = const LegacyCoordinatorDomain(),
    this.syntheticLocalCommit,
  });
  final SyncTransactionContainer store;
  final Partition partition;
  final w.Principal principal;
  final Request request;
  final CoordinatorDomain domain;
  final SyntheticLocalCommit? syntheticLocalCommit;
  final Map<String, int> timingsMicros = {};
  void _time(String name, Stopwatch watch) => timingsMicros.update(
    name,
    (v) => v + watch.elapsedMicroseconds,
    ifAbsent: () => watch.elapsedMicroseconds,
  );
  Future<Map<String, dynamic>> _request(
    String method,
    String endpoint, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final watch = Stopwatch()..start();
    try {
      return await request(method, endpoint, body: body, query: query);
    } finally {
      _time('network', watch);
    }
  }

  bool _busy = false;
  Future<T> _single<T>(Future<T> Function() body) async {
    if (_busy) throw const ContractViolation('coordinator-busy');
    _busy = true;
    try {
      return await body();
    } finally {
      _busy = false;
    }
  }

  Future<RemoteContext> context() async {
    final c = await store.readRemoteContext();
    if (c == null) throw const ContractViolation('sync-not-initialized');
    final m = w.object(jsonDecode(c.json));
    domain.validateHeader(m);
    if (m['device'] != principal.device ||
        m['owner'] != principal.user ||
        m['workspace'] != partition.workspace ||
        principal.workspace != partition.workspace ||
        m['epoch'] != partition.lineage ||
        m['format'] != 1)
      throw const ContractViolation('local-identity-mismatch');
    return c;
  }

  static w.NoteCommand command(PendingCommand p) =>
      w.NoteCommand.parse(w.object(jsonDecode(p.immutableJson))['intent']);

  Future<CommandReceipt> edit(
    String id,
    String target,
    String note, {
    DateTime? now,
    int? expectedRevision,
    Future<void> Function()? beforeCommit,
  }) => _single(() async {
    final c = await context(), m = w.object(jsonDecode(c.json));
    final pending = await store.readPendingCommands();
    final old = await store.lookupCommandReceipt(id);
    if (old != null) {
      // A UI retry looks up the durable immutable intent; it never creates a
      // new timestamp/snapshot under an existing command ID.
      final p = pending.where((p) => p.receipt.id == id).firstOrNull;
      if (p == null ||
          domain.command(p).target != target ||
          domain.command(p).note != note)
        throw const ContractViolation('command-id-already-used');
      return old;
    }
    if (pending.any((p) => domain.command(p).target == target))
      throw const ContractViolation('target-has-pending-proposal');
    final s = await store.readSnapshot();
    if (expectedRevision != null && expectedRevision != s.revision)
      throw const ContractViolation('stale-local-revision');
    final revision = m['revisions'][target];
    if (revision == null) throw const ContractViolation('unknown-target');
    final cmd = w.NoteCommand.parse({
      'protocol_version': 1,
      'domain_version': 1,
      'workspace_id': principal.workspace,
      'device_id': principal.device,
      'workspace_epoch': partition.lineage,
      'change_id': id,
      'kind': 'transaction.set_note',
      'transaction_id': target,
      'base_revision': revision,
      'note': note,
    });
    final override = syntheticLocalCommit;
    if (override != null) {
      return override(cmd, s, (now ?? DateTime.now()).toUtc(), beforeCommit);
    }
    final preparationWatch = Stopwatch()..start();
    final prepared = domain.prepare(
      s.value,
      cmd,
      principal.user,
      now ?? DateTime.now().toUtc(),
    );
    _time('local_prepare', preparationWatch);
    await beforeCommit?.call();
    final commitWatch = Stopwatch()..start();
    final receipt = await store.commitMutation(
      Mutation(
        id: id,
        partition: partition,
        expectedRevision: s.revision,
        snapshot: prepared.snapshot,
        intentJson: prepared.intentJson,
      ),
    );
    _time('local_commit', commitWatch);
    return receipt;
  });

  void _header(Map<String, dynamic> response) {
    domain.validateHeader(response);
    w.versions(response['protocol_version'], response['domain_version']);
    if (response['workspace_id'] != principal.workspace ||
        response['workspace_epoch'] != partition.lineage)
      throw const ContractViolation('remote-partition-mismatch');
  }

  void _receipt(Map<String, dynamic> r, w.NoteCommand cmd) {
    _header(r);
    if (r['change_id'] != cmd.changeId ||
        r['content_digest'] != cmd.contentDigest ||
        r['transaction_id'] != cmd.target ||
        w.decimal(r['commit_seq']) <= 0 ||
        !['accepted', 'conflict'].contains(r['status']))
      throw const ContractViolation('invalid-server-receipt');
    final rev = w.decimal(r['revision']);
    if (r['status'] == 'accepted' && rev != cmd.baseRevision + 1)
      throw const ContractViolation('incompatible-accepted-revision');
    if (r['status'] == 'conflict') {
      final conflict = w.object(r['conflict']);
      if (conflict['base_revision'] != '${cmd.baseRevision}' ||
          conflict['proposed_note'] != cmd.note ||
          conflict['current_revision'] != r['revision'] ||
          rev <= cmd.baseRevision ||
          (conflict['current_note'] != null &&
              conflict['current_note'] is! String))
        throw const ContractViolation('invalid-conflict-receipt');
    }
  }

  Future<void> _ack(PendingCommand p, Map<String, dynamic> r) async {
    await store.markCommandAcknowledged(_syntheticReceipt(p, r));
  }

  SyntheticReceipt _syntheticReceipt(PendingCommand p, Map<String, dynamic> r) {
    _receipt(r, domain.command(p));
    final receipt = SyntheticReceipt(
      'server-${r['commit_seq']}',
      p.receipt.id,
      partition,
      p.receipt.contentDigest,
      r['status'] == 'accepted'
          ? DeliveryState.accepted
          : DeliveryState.conflict,
      canonicalJson(r),
    );
    return receipt;
  }

  Future<Map<String, dynamic>> _retry(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await action();
      } catch (e) {
        final transient =
            e is SocketException ||
            e is HttpException ||
            e is TimeoutException ||
            (e is w.ApiError && e.status == 503);
        if (!transient || attempt >= 2) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 100 * (1 << attempt)),
        );
      }
    }
  }

  Future<void> push() => _single(() async {
    await context();
    for (final p in await store.readPendingCommands()) {
      if (![
        DeliveryState.queued,
        DeliveryState.inFlight,
      ].contains(p.receipt.state))
        continue;
      final cmd = domain.command(p);
      final r = await _retry(() => _request('POST', 'push', body: cmd.body));
      await _ack(p, r); // no cursor movement, even after successful HTTP200
    }
  });

  Future<Map<String, dynamic>> page({int limit = 10}) async {
    final m = w.object(jsonDecode((await context()).json));
    return _retry(
      () => _request(
        'GET',
        'changes',
        query: {'cursor': m['cursor'] as String, 'limit': '$limit'},
      ),
    );
  }

  Future<bool> applyPage(Map<String, dynamic> page) => _single(() async {
    final applyWatch = Stopwatch()..start();
    final c = await context(), m = w.object(jsonDecode(c.json));
    _header(page);
    final pageId = w.digest(page), pages = w.object(m['pages']);
    if (pages.containsKey(pageId)) return false;
    var seq = await store.readCheckpoint();
    if (w.decimal(page['from_seq']) != seq)
      throw const ContractViolation('stale-remote-page');
    final high = w.decimal(page['high']);
    if (high < seq ||
        page['has_more'] is! bool ||
        page['next_cursor'] is! String ||
        (page['next_cursor'] as String).isEmpty)
      throw const ContractViolation('invalid-page-boundary');
    final bundles = page['bundles'] as List;
    if (bundles.length > 100) throw const ContractViolation('page-bound');
    var shadow = c.shadow;
    final revisions = w.object(m['revisions']),
        receipts = <String, Map<String, dynamic>>{};
    // Validate the WHOLE page before persisting even one receipt.
    for (final raw in bundles) {
      final b = w.object(raw);
      if (w.decimal(b['seq']) != ++seq || seq > high)
        throw const ContractViolation('server-sequence-gap');
      final r = w.object(b['receipt']);
      _header(r);
      if (r['commit_seq'] != b['seq'])
        throw const ContractViolation('bundle-receipt-sequence');
      w.identifier(r['change_id']);
      w.identifier(r['transaction_id']);
      if (r['content_digest'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(r['content_digest'] as String) ||
          receipts.containsKey(r['change_id']))
        throw const ContractViolation('invalid-bundle-receipt');
      final entities = (b['entities'] as List).map(w.object).toList();
      if (!['accepted', 'conflict'].contains(r['status']) ||
          (r['status'] == 'conflict' && entities.isNotEmpty))
        throw const ContractViolation('invalid-bundle-status');
      final seen = <String>{};
      for (final e in entities) {
        final t = ProfileAdapter.decodeEntity(e);
        if (t.entityId != domain.entityFor(principal.user) ||
            !seen.add(t.id) ||
            !revisions.containsKey(t.id) ||
            w.decimal(e['revision']) != w.decimal(revisions[t.id]) + 1)
          throw const ContractViolation('incompatible-entity-revision');
        revisions[t.id] = e['revision'];
      }
      if (r['status'] == 'accepted' && !seen.contains(r['transaction_id']))
        throw const ContractViolation('missing-accepted-entity');
      if (r['status'] == 'accepted' &&
          revisions[r['transaction_id']] != r['revision'])
        throw const ContractViolation('receipt-entity-revision-mismatch');
      shadow = SyntheticTrace.sync('remote.verified-domain-replay', () => domain.incoming(shadow, b, principal.user));
      receipts[r['change_id'] as String] = r;
    }
    if ((seq < high) != page['has_more'] || (bundles.isEmpty && seq != high))
      throw const ContractViolation('incomplete-page');
    final before = await store.readSnapshot();
    final pending = await store.readPendingCommands();
    for (final p in pending) {
      final r = receipts[p.receipt.id];
      if (r != null) {
        final cmd = domain.command(p);
        _receipt(r, cmd);
        // Bind the local proposal to its authoritative entity at the exact
        // journal position, not to the final page (which may be newer).
        if (r['status'] == 'accepted') {
          final bundle = bundles.firstWhere(
            (b) => b['receipt']['change_id'] == cmd.changeId,
          );
          final entity = (bundle['entities'] as List).firstWhere(
            (e) => e['transaction']['id'] == cmd.target,
          );
          if (entity['transaction']['userNote'] != cmd.note)
            throw const ContractViolation('receipt-note-mismatch');
        }
      }
    }
    if (bundles.isEmpty) return false;
    // Pull-derived receipts, coverage, financial rows and cursor commit together.
    // A prior push ACK is independently durable and remains idempotent here.
    final incomingReceipts = [
      for (final p in pending)
        if (receipts[p.receipt.id] != null)
          _syntheticReceipt(p, receipts[p.receipt.id]!),
    ];
    final covered = [
      for (final p in pending)
        if (receipts[p.receipt.id]?['status'] == 'accepted') p.receipt.id,
    ];
    pages[pageId] = '$seq';
    m['cursor'] = page['next_cursor'];
    m['checkpoint'] = seq;
    m['revisions'] = revisions;
    m['pages'] = pages;
    final projection = SyntheticTrace.sync('remote.pending-projection', () => domain.project(
      before.value,
      shadow,
      pending.where((p) => !covered.contains(p.receipt.id)).toList(),
      principal.user,
    ));
    _time('remote_prepare', applyWatch);
    final commitWatch = Stopwatch()..start();
    await store.applyRemoteBundle(
      RemoteBundle(
        id: pageId,
        partition: partition,
        fromCursor: w.decimal(page['from_seq']),
        toCursor: seq,
        expectedRevision: before.revision,
        shadow: shadow,
        projection: projection,
        syncContextJson: canonicalJson(m),
        coveredCommands: covered,
        receipts: incomingReceipts,
      ),
    );
    _time('remote_commit', commitWatch);
    return true;
  });

  Future<void> pull() async {
    for (var i = 0; i < 1000; i++) {
      final p = await page();
      await applyPage(p);
      if (p['has_more'] == false) return;
    }
    throw const ContractViolation('pull-page-limit');
  }

  Future<void> sync() async {
    await push();
    await pull();
  }
}
