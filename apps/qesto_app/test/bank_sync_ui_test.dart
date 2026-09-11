import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qesto/desktop/pages/desktop_bank_connections_page.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/domain/bank_sync_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sync/bank_sync_config.dart';
import 'package:qesto/features/bank_browser/sync/bank_sync_manager.dart';
import 'package:qesto/features/bank_browser/sync/bank_sync_scheduler.dart';

void main() {
  testWidgets('bank card exposes background status and persistent toggle', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(const {});
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('qesto-bank-ui-test-'),
    );
    if (root == null) fail('Could not create the temporary profile directory.');
    final profiles = BrowserProfileManager(rootDirectory: root);
    final created = await tester.runAsync(
      () => profiles.createProfile(BankConnectorRegistry.sber),
    );
    if (created == null) fail('Could not create the test bank profile.');
    await tester.runAsync(
      () => profiles.updateSyncMetadata(
        created.id,
        created.syncMetadata.copyWith(
          state: BankConnectionSyncState.connected,
          nextScheduledSyncAt: DateTime(2026, 9, 3, 18),
          lastHistorySyncThrough: DateTime.now().subtract(
            const Duration(days: 1),
          ),
        ),
      ),
    );
    const config = BankSyncConfig(jitterPercent: 0);
    final runner = _NoopRunner();
    final manager = BankSyncManager(
      profileManager: profiles,
      runners: [runner],
      config: config,
      networkProbe: () async => true,
    );
    final scheduler = BankSyncScheduler(
      profileManager: profiles,
      manager: manager,
      config: config,
      armTimers: false,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scheduler.dispose();
      manager.dispose();
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopBankConnectionsPage(
            profileManager: profiles,
            bankSyncScheduler: scheduler,
          ),
        ),
      ),
    );
    await tester.pump();
    for (var index = 0; index < 40; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.text('Автоматическая синхронизация').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('Автоматическая синхронизация'), findsOneWidget);
    expect(find.text('Подключён'), findsOneWidget);
    expect(
      find.byKey(const Key('bank-background-sync-toggle')),
      findsOneWidget,
    );
    expect(find.text('Обновить сейчас'), findsOneWidget);

    await tester.runAsync(() => tester.tap(find.text('Обновить сейчас')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('С последней успешной синхронизации'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Начать синхронизацию')));
    // This path performs real disk I/O. Fake-time pumpAndSettle cannot finish
    // it; allow the real async zone to reach the result even during APK builds.
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      if (find.text('Сбер обновлён в фоне').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.byType(BankBrowserPage), findsNothing);
    expect(runner.range?.label, 'С последней успешной синхронизации');
    expect(find.text('Сбер обновлён в фоне'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();

    // The toggle performs real serialized file I/O. Start it in the real
    // async zone so a subsequent runAsync read cannot await a fake-zone queue.
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('bank-background-sync-toggle'))),
    );
    await tester.pump();
    BankProfile? restored;
    for (var index = 0; index < 20; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final value = await tester.runAsync<Object?>(
        () => profiles.getProfile(created.id),
      );
      restored = value as BankProfile?;
      if (restored?.syncMetadata.backgroundSyncEnabled == false) break;
    }
    expect(restored?.syncMetadata.backgroundSyncEnabled, isFalse);
    expect(restored?.syncMetadata.state, BankConnectionSyncState.disabled);
    await tester.runAsync(() => scheduler.start());
    runner.gate = Completer<void>();
    Future<BankSyncExecution>? running;
    await tester.runAsync(() async {
      running = scheduler.refreshNow(created.id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      if (find.byKey(const Key('bank-sync-cancel')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const Key('bank-sync-cancel')), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('bank-background-sync-toggle')))
          .onChanged,
      isNotNull,
    );
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('bank-sync-cancel'))),
    );
    final stopped = await tester.runAsync(() => running!);
    expect(stopped?.result?.result, BankSyncResult.cancelled);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _NoopRunner
    implements
        RangedBankBackgroundSyncRunner,
        CancellableBankBackgroundSyncRunner {
  SberSyncRange? range;
  Completer<void>? gate;

  @override
  String get bankId => 'sber';

  @override
  Future<BankSyncRunResult> run(BankProfile profile) async {
    await gate?.future;
    return const BankSyncRunResult(result: BankSyncResult.success);
  }

  @override
  Future<void> cancel(String profileId) async {
    if (gate != null && !gate!.isCompleted) gate!.complete();
  }

  @override
  Future<BankSyncRunResult> runForRange(
    BankProfile profile,
    SberSyncRange range,
  ) {
    this.range = range;
    return run(profile);
  }
}
