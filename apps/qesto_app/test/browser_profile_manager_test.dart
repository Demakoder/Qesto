import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_sync_models.dart';

void main() {
  late Directory root;
  late BrowserProfileManager manager;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qesto-bank-profile-test-');
    manager = BrowserProfileManager(rootDirectory: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'concurrent profile updates preserve URL and sync metadata, backup recovers',
    () async {
      final profile = await manager.createProfile(BankConnectorRegistry.sber);
      final url = Uri.parse('https://online.sberbank.ru/app/accounts');
      await Future.wait([
        manager.openProfile(profile),
        manager.updateLastKnownUrl(profile, url),
        manager.mutateSyncMetadata(
          profile.id,
          (value) => value.copyWith(importedCount: 7),
        ),
      ]);
      final stored = (await manager.getProfile(profile.id))!;
      expect(stored.lastKnownUrl, url);
      expect(stored.syncMetadata.importedCount, 7);
      await manager.openProfile(stored);
      await File(
        '${manager.profileDirectory(profile.id).path}/profile.json',
      ).writeAsString('{broken');
      final recovered = (await manager.getProfile(profile.id))!;
      expect(recovered.lastKnownUrl, url);
      expect(recovered.syncMetadata.importedCount, 7);
    },
  );

  test('creates isolated persistent profile metadata and CEF folder', () async {
    final first = await manager.createProfile(BankConnectorRegistry.sber);
    final second = await manager.createProfile(BankConnectorRegistry.sber);

    expect(first.id, isNot(second.id));
    expect(await manager.profileExists(first.id), isTrue);
    expect(await manager.cefDataDirectory(first.id).exists(), isTrue);
    expect(await manager.cefDataDirectory(second.id).exists(), isTrue);
    expect(manager.cefDataDirectory(first.id).parent.path, root.path);
    expect(manager.cefDataDirectory(second.id).parent.path, root.path);

    final restored = await manager.getProfile(first.id);
    expect(restored?.bankId, 'sber');
    expect(restored?.lastKnownUrl, BankConnectorRegistry.sber.startUrl);
    expect(restored?.syncMetadata.backgroundSyncEnabled, isTrue);
    expect(restored?.syncMetadata.state, BankConnectionSyncState.disconnected);
  });

  test(
    'persists background scheduling metadata without touching CEF data',
    () async {
      final profile = await manager.createProfile(BankConnectorRegistry.sber);
      final marker = File(
        '${manager.cefDataDirectory(profile.id).path}${Platform.pathSeparator}cookie-marker',
      );
      await marker.writeAsString('browser state');
      final next = DateTime(2026, 9, 3, 18, 30);

      await manager.updateSyncMetadata(
        profile.id,
        profile.syncMetadata.copyWith(
          state: BankConnectionSyncState.connected,
          lastResult: BankSyncResult.success,
          lastSuccessfulSyncAt: DateTime(2026, 9, 3, 15, 30),
          nextScheduledSyncAt: next,
          importedCount: 12,
          deduplicatedCount: 9,
          lastBrowserMode: BankSyncExecutionMode.background,
        ),
      );
      final restored = await manager.getProfile(profile.id);

      expect(restored?.syncMetadata.nextScheduledSyncAt, next);
      expect(restored?.syncMetadata.importedCount, 12);
      expect(restored?.syncMetadata.deduplicatedCount, 9);
      expect(
        restored?.syncMetadata.lastBrowserMode,
        BankSyncExecutionMode.background,
      );
      expect(await marker.readAsString(), 'browser state');
    },
  );

  test(
    'browser presentation updates do not roll back fresh sync metadata',
    () async {
      final stale = await manager.createProfile(BankConnectorRegistry.sber);
      final attempt = DateTime(2026, 9, 3, 12, 30);
      final scheduled = DateTime(2026, 9, 3, 12);
      await manager.updateSyncMetadata(
        stale.id,
        stale.syncMetadata.copyWith(
          state: BankConnectionSyncState.syncing,
          lastAttemptAt: attempt,
          lastScheduledSyncAt: scheduled,
          lastBrowserMode: BankSyncExecutionMode.background,
        ),
      );

      final opened = await manager.openProfile(stale);
      final navigated = await manager.updateLastKnownUrl(
        stale,
        Uri.parse('https://online.sberbank.ru/app/operations'),
      );

      for (final profile in [opened, navigated]) {
        expect(profile.syncMetadata.state, BankConnectionSyncState.syncing);
        expect(profile.syncMetadata.lastAttemptAt, attempt);
        expect(profile.syncMetadata.lastScheduledSyncAt, scheduled);
        expect(
          profile.syncMetadata.lastBrowserMode,
          BankSyncExecutionMode.background,
        );
      }
    },
  );

  test('updates safe last URL and lists most recently opened first', () async {
    final first = await manager.createProfile(BankConnectorRegistry.sber);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final second = await manager.createProfile(BankConnectorRegistry.sber);
    await manager.updateLastKnownUrl(
      first,
      Uri.parse('https://online.sberbank.ru/main'),
    );

    final listed = await manager.listProfiles();
    expect(listed.first.id, second.id);
    expect(
      (await manager.getProfile(first.id))?.lastKnownUrl.toString(),
      'https://online.sberbank.ru/main',
    );
  });

  test('deleting profile wipes browser website data with metadata', () async {
    final profile = await manager.createProfile(BankConnectorRegistry.sber);
    final cookieMarker = File(
      '${manager.cefDataDirectory(profile.id).path}${Platform.pathSeparator}cookie-marker',
    );
    await cookieMarker.writeAsString('sensitive local data');

    await manager.deleteProfile(profile.id);

    expect(await manager.profileDirectory(profile.id).exists(), isFalse);
    expect(await manager.profileExists(profile.id), isFalse);
  });

  test('rejects traversal identifiers', () async {
    expect(
      () => manager.deleteProfile('../outside'),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => manager.cefDataDirectory('../outside'), throwsArgumentError);
  });

  test(
    'empty legacy CEF folder preserves profile identity and metadata',
    () async {
      final profile = await manager.createProfile(BankConnectorRegistry.sber);
      final legacy = Directory(
        '${manager.profileDirectory(profile.id).path}/cef',
      );
      await legacy.create();
      await manager.prepareCefProfile(profile.id);
      expect(manager.cefDataDirectory(profile.id).parent.path, root.path);
      expect((await manager.getProfile(profile.id))!.id, profile.id);
      expect(await legacy.exists(), isTrue);
    },
  );

  test(
    'nonempty legacy profile fails closed without losing its contents',
    () async {
      final profile = await manager.createProfile(BankConnectorRegistry.sber);
      final legacy = Directory(
        '${manager.profileDirectory(profile.id).path}/cef',
      );
      await legacy.create();
      final marker = File('${legacy.path}/fixture');
      await marker.writeAsString('retained');
      await expectLater(
        manager.prepareCefProfile(profile.id),
        throwsStateError,
      );
      expect(await marker.readAsString(), 'retained');
      expect((await manager.getProfile(profile.id))!.id, profile.id);
    },
  );
}
