import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_note_driver.dart';
import 'package:qesto_windows_boundary_experiment/note_sync_binding.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_coordinator_domain.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as wire;
import 'package:qesto_durable_effects_experiment/windows_driver.dart';
import 'package:qesto_durable_effects_experiment/prepared_commit.dart';

void main() {
  late Directory dir;
  late SqliteContainer store;
  late SyntheticNoteDriver driver;
  late SyntheticRemoteLifetime lifetime;
  late String initial;
  const partition = Partition('synthetic-4g-lifetime', 'synthetic-epoch');
  setUp(() async {
    dir = createSpikeDirectory();
    initial = encodeSynthetic(count: 60);
    final state = FinancialSnapshot(initial);
    store = await SqliteContainer.migrate(dir.path,
      MigrationManifest('lifetime', partition, state.hash), state, incremental: true);
    final policy = const QestoNoteExecutor().policyDigest(initial, syntheticUser);
    await store.initializeRemoteContext(canonicalJson({
      'format': 1, 'checkpoint': 0, 'workspace': partition.workspace,
      'owner': syntheticUser, 'device': 'synthetic-device', 'epoch': partition.lineage,
      'cursor': 'opaque-test-cursor', 'revisions': {'container-tx-0': '0'}, 'pages': {},
      'financial_profile': QestoNoteExecutor.profile, 'policy_digest': policy,
    }));
    driver = await const EffectsDriverFactory(boundedLifetime: true).open(store,
      NoteSyncBinding(principal: const wire.Principal('synthetic-no-network', syntheticUser,
        'synthetic-device', 'synthetic-4g-lifetime'), endpoint: Uri.parse('http://127.0.0.1:1'),
        domain: QestoCoordinatorDomain(syntheticUser, partition.workspace,
          partition.lineage, policy, ['synthetic-device'])));
    lifetime = driver as SyntheticRemoteLifetime;
  });
  tearDown(() => store.close());

  Future<void> rewriteContext(void Function(Map<String, dynamic>) change) async {
    final m = jsonDecode((await store.readRemoteContext())!.json) as Map<String, dynamic>;
    change(m); final json = canonicalJson(m);
    store.raw.execute('UPDATE sync_context SET body=?,digest=?', [json, digest(json)]);
  }

  test('unchanged verified pull resumes, zero incoming outbox', () async {
    await lifetime.beginRemote(); await lifetime.completeRemote();
    expect(lifetime.lifetimeMetrics, {'reused': 1, 'readmitted': 0});
    expect((await store.readSnapshot()).value.json, initial);
    expect(await store.readPendingCommands(), isEmpty);
  });
  for (final field in ['cursor', 'revisions', 'pages']) {
    test('same numeric checkpoint does not hide changed $field', () async {
      await lifetime.beginRemote();
      await rewriteContext((m) => m[field] = field == 'cursor' ? 'different' : {'changed': '1'});
      await lifetime.completeRemote();
      expect(lifetime.lifetimeMetrics, {'reused': 0, 'readmitted': 1});
    });
  }
  for (final field in ['device', 'owner', 'workspace', 'epoch', 'policy_digest', 'financial_profile']) {
    test('changed $field fails closed', () async {
      await lifetime.beginRemote();
      await rewriteContext((m) => m[field] = 'foreign');
      await expectLater(lifetime.completeRemote(), throwsA(anything));
      expect(lifetime.lifetimeMetrics['reused'], 0);
    });
  }
  test('warmed chunk mutation cannot retain owner', () async {
    await lifetime.beginRemote();
    store.raw.execute("UPDATE json_chunks SET body='broken' WHERE scope='state' AND slot=0");
    await expectLater(lifetime.completeRemote(), throwsA(isA<ContractViolation>()));
    expect(lifetime.lifetimeMetrics['reused'], 0);
  });
  test('new pending command and receipt-only update both require admission', () async {
    await lifetime.beginRemote();
    final receipt = await store.commitMutation(Mutation(
      id: 'synthetic-pending', partition: partition, expectedRevision: 0,
      snapshot: FinancialSnapshot(initial), intentJson: '{}'));
    await lifetime.completeRemote();
    expect(lifetime.lifetimeMetrics, {'reused': 0, 'readmitted': 1});
    await lifetime.beginRemote();
    await store.markCommandAcknowledged(SyntheticReceipt(
      'synthetic-receipt', receipt.id, partition, receipt.contentDigest,
      DeliveryState.accepted, '{}'));
    await lifetime.completeRemote();
    expect(lifetime.lifetimeMetrics, {'reused': 0, 'readmitted': 2});
    expect((await store.readPendingCommands()).single.receipt.state,
      DeliveryState.accepted);
  });
  test('same checkpoint with changed delivery metadata requires admission', () async {
    await lifetime.beginRemote();
    await store.commitMutation(Mutation(id: 'synthetic-pending', partition: partition,
      expectedRevision: 0, snapshot: FinancialSnapshot(initial), intentJson: '{}'));
    await lifetime.completeRemote();
    await lifetime.beginRemote();
    store.raw.execute("UPDATE delivery SET attempts=attempts+1 WHERE id='synthetic-pending'");
    await lifetime.completeRemote();
    expect(lifetime.lifetimeMetrics, {'reused': 0, 'readmitted': 2});
  });
  test('rotation changes generation and forces admission', () async {
    await lifetime.beginRemote(); await store.rotateKey(); await lifetime.completeRemote();
    expect(lifetime.lifetimeMetrics, {'reused': 0, 'readmitted': 1});
  });
  test('owner blocks preparation while remote validation is in progress', () async {
    final owner = await DurableEffectsOwner.load(store);
    final generation = owner.generation;
    owner.suspendForRemote();
    expect(() => owner.prepare(commandId: 'blocked', target: 'container-tx-0',
      note: 'no speculative during pull', time: DateTime.utc(2026, 10, 18)),
      throwsA(isA<EffectsOwnerFailure>()));
    store.verify();
    expect(owner.resumeUnchangedAfterRemote(await store.readSnapshot()), true);
    expect(owner.generation, generation);
    owner.invalidate('worker-loss');
    expect(owner.resumeUnchangedAfterRemote(await store.readSnapshot()), false);
  });
}
