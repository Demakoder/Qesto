import 'dart:async';
import 'dart:io';
import 'package:qesto/core/safety/financial_write_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/domain/bank_sync_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sync/bank_sync_manager.dart';
import 'package:qesto/features/bank_browser/sync/bank_sync_scheduler.dart';

void main() {
  late Directory root;
  late BrowserProfileManager profiles;
  late BankProfile profile;
  late _Runner runner;
  late BankSyncManager manager;
  late BankSyncScheduler scheduler;
  final now = DateTime(2026, 9, 9, 14);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('qesto-refresh-test-');
    profiles = BrowserProfileManager(rootDirectory: root);
    profile = await profiles.createProfile(BankConnectorRegistry.sber);
    runner = _Runner();
    manager = BankSyncManager(
      profileManager: profiles,
      runners: [runner],
      clock: () => now,
      networkProbe: () async => true,
    );
    scheduler = BankSyncScheduler(
      profileManager: profiles,
      manager: manager,
      clock: () => now,
      armTimers: false,
    );
  });
  tearDown(() async {
    scheduler.dispose();
    manager.dispose();
    await root.delete(recursive: true);
  });

  test(
    'explicit refresh bypasses schedule cooldown and disabled toggle without enabling it',
    () async {
      await profiles.updateSyncMetadata(
        profile.id,
        BankSyncMetadata(
          state: BankConnectionSyncState.disabled,
          lastSuccessfulSyncAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      final range = SberSyncRange.currentMonth(now);
      final execution = await scheduler.refreshNow(profile.id, range: range);
      expect(execution.result?.isSuccess, isTrue);
      expect(runner.range, same(range));
      expect(runner.calls, 1);
      final stored = (await profiles.getProfile(profile.id))!.syncMetadata;
      expect(stored.lastBrowserMode, BankSyncExecutionMode.background);
      expect(stored.backgroundSyncEnabled, isFalse);
      expect(stored.nextScheduledSyncAt, isNull);
    },
  );

  test('user may retry auth-required once but scheduler may not', () async {
    profile = await profiles.updateSyncMetadata(
      profile.id,
      const BankSyncMetadata(
        backgroundSyncEnabled: true,
        state: BankConnectionSyncState.authRequired,
      ),
    );
    expect(
      (await manager.runBackground(profile)).decision,
      BankSyncStartDecision.authRequired,
    );
    expect(runner.calls, 0);
    runner.result = const BankSyncRunResult(
      result: BankSyncResult.authRequired,
    );
    await scheduler.refreshNow(profile.id);
    expect(runner.calls, 1);
    expect(
      (await profiles.getProfile(profile.id))!.syncMetadata.nextScheduledSyncAt,
      isNull,
    );
  });

  test(
    'explicit refresh cannot steal visible browser or overlap another job',
    () async {
      expect(manager.beginInteractiveSession(profile.id), isTrue);
      expect(
        (await scheduler.refreshNow(profile.id)).decision,
        BankSyncStartDecision.busy,
      );
      expect(runner.calls, 0);
      manager.endInteractiveSession(profile.id);
      runner.gate = Completer<void>();
      final running = scheduler.refreshNow(profile.id);
      await runner.started.future;
      expect(
        (await scheduler.refreshNow(profile.id)).decision,
        BankSyncStartDecision.busy,
      );
      runner.gate!.complete();
      await running;
      expect(runner.calls, 1);
    },
  );

  test(
    'only complete imports advance verified history; old success never moves it backwards',
    () async {
      final previous = now.subtract(const Duration(days: 2));
      await profiles.updateSyncMetadata(
        profile.id,
        BankSyncMetadata(lastHistorySyncThrough: previous),
      );
      runner.result = BankSyncRunResult(
        result: BankSyncResult.partial,
        historySyncedThrough: now,
      );
      await scheduler.refreshNow(profile.id);
      expect(
        (await profiles.getProfile(
          profile.id,
        ))!.syncMetadata.lastHistorySyncThrough,
        previous,
      );
      runner.result = BankSyncRunResult(
        result: BankSyncResult.success,
        historySyncedThrough: now,
      );
      await scheduler.refreshNow(profile.id);
      expect(
        (await profiles.getProfile(
          profile.id,
        ))!.syncMetadata.lastHistorySyncThrough,
        now,
      );
      runner.result = BankSyncRunResult(
        result: BankSyncResult.success,
        historySyncedThrough: previous,
      );
      await scheduler.refreshNow(profile.id);
      expect(
        (await profiles.getProfile(
          profile.id,
        ))!.syncMetadata.lastHistorySyncThrough,
        now,
      );
    },
  );

  test(
    'incremental period includes prior day and does not cap a long offline gap',
    () {
      final since = SberSyncRange.sinceLastSync(DateTime(2026, 9, 8, 23), now);
      expect(since.from, DateTime(2026, 9, 7));
      expect(since.toExclusive, DateTime(2026, 9, 10));
      expect(
        SberSyncRange.sinceLastSync(DateTime(2026, 6, 1), now).from,
        DateTime(2026, 5, 31),
      );
      expect(
        SberSyncRange.sinceLastSync(null, now).from,
        DateTime(2026, 8, 11),
      );
      expect(
        SberSyncRange.sinceLastSync(DateTime(2027), now).from,
        DateTime(2026, 8, 11),
      );
    },
  );

  test(
    'cancel stops pending writes without advancing coverage or failure count',
    () async {
      final covered = now.subtract(const Duration(days: 1));
      await profiles.updateSyncMetadata(
        profile.id,
        BankSyncMetadata(
          backgroundSyncEnabled: true,
          state: BankConnectionSyncState.connected,
          lastHistorySyncThrough: covered,
          consecutiveFailures: 2,
        ),
      );
      runner.gate = Completer<void>();
      final job = scheduler.refreshNow(profile.id);
      await runner.started.future;
      await scheduler.cancelCurrentSync(profile.id);
      final result = await job;
      final metadata = (await profiles.getProfile(profile.id))!.syncMetadata;
      expect(result.result?.result, BankSyncResult.cancelled);
      expect(runner.writes, 0);
      expect(runner.cancels, 1);
      expect(metadata.consecutiveFailures, 2);
      expect(metadata.lastHistorySyncThrough, covered);
      expect(metadata.backgroundSyncEnabled, isTrue);
      expect(metadata.nextScheduledSyncAt!.isAfter(now), isTrue);
      expect(manager.isBusy, isFalse);
    },
  );

  test(
    'disabling automatic sync cancels current job and persists no schedule',
    () async {
      await scheduler.setBackgroundSyncEnabled(profile.id, true);
      runner.gate = Completer<void>();
      final job = scheduler.refreshNow(profile.id);
      await runner.started.future;
      await scheduler.setBackgroundSyncEnabled(profile.id, false);
      expect((await job).result?.result, BankSyncResult.cancelled);
      final metadata = (await profiles.getProfile(profile.id))!.syncMetadata;
      expect(metadata.backgroundSyncEnabled, isFalse);
      expect(metadata.state, BankConnectionSyncState.disabled);
      expect(metadata.nextScheduledSyncAt, isNull);
      expect(runner.writes, 0);
    },
  );

  test('a historical range records its end, not time the job finished', () {
    final historical = SberSyncRange(
      from: DateTime(2026, 7),
      toExclusive: DateTime(2026, 8),
      label: 'July',
    );
    expect(historical.verifiedThrough(now), DateTime(2026, 8));
    expect(SberSyncRange.currentMonth(now).verifiedThrough(now), now);
  });
}

class _Runner
    implements
        RangedBankBackgroundSyncRunner,
        CancellableBankBackgroundSyncRunner {
  @override
  String get bankId => 'sber';
  var calls = 0;
  var cancels = 0;
  var writes = 0;
  SberSyncRange? range;
  Completer<void>? gate;
  final started = Completer<void>();
  BankSyncRunResult result = const BankSyncRunResult(
    result: BankSyncResult.success,
  );
  @override
  Future<BankSyncRunResult> run(BankProfile profile) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    FinancialWriteGuard.check();
    writes++;
    return result;
  }

  @override
  Future<void> cancel(String profileId) async {
    cancels++;
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
