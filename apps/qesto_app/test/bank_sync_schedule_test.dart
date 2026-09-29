import 'dart:async';
import 'package:qesto/core/safety/financial_write_guard.dart';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/domain/bank_sync_models.dart';
import 'package:qesto/features/bank_browser/sync/bank_sync_config.dart';
import 'package:qesto/features/bank_browser/sync/bank_sync_manager.dart';
import 'package:qesto/features/bank_browser/sync/bank_sync_scheduler.dart';

void main() {
  group('BankSyncSchedulePolicy', () {
    test('hourly jitter always stays inside the configured window', () {
      final policy = BankSyncSchedulePolicy(random: Random(17));

      for (var index = 0; index < 100; index++) {
        final delay = policy.plannedDelay();
        expect(delay, greaterThanOrEqualTo(const Duration(minutes: 54)));
        expect(delay, lessThanOrEqualTo(const Duration(minutes: 66)));
      }
    });

    test('retry backoff uses 10, 30 and 60 minute stages', () {
      const config = BankSyncConfig(jitterPercent: 0, retryJitterPercent: 0);
      final policy = BankSyncSchedulePolicy(config: config, random: Random(1));

      expect(policy.retryDelay(1), const Duration(minutes: 10));
      expect(policy.retryDelay(2), const Duration(minutes: 30));
      expect(policy.retryDelay(3), const Duration(minutes: 60));
      expect(policy.retryDelay(7), const Duration(minutes: 60));
    });
  });

  group('BankSyncManager and scheduler', () {
    late Directory root;
    late BrowserProfileManager profiles;
    late DateTime now;
    late BankSyncConfig config;
    late BankSyncSchedulePolicy policy;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('qesto-bank-sync-test-');
      profiles = BrowserProfileManager(rootDirectory: root);
      now = DateTime(2026, 9, 3, 12);
      config = const BankSyncConfig(
        jitterPercent: 0,
        retryJitterPercent: 0,
        queueSpacing: Duration.zero,
      );
      policy = BankSyncSchedulePolicy(config: config, random: Random(1));
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'success persists counters and schedules from the current cycle',
      () async {
        final profile = await _connectedProfile(profiles);
        final marker = File(
          '${profiles.cefDataDirectory(profile.id).path}${Platform.pathSeparator}session-marker',
        );
        await marker.writeAsString('persistent browser data');
        final runner = _FakeRunner(
          const BankSyncRunResult(
            result: BankSyncResult.success,
            importedCount: 8,
            updatedCount: 3,
            deduplicatedCount: 14,
          ),
        );
        final manager = _manager(profiles, runner, config, policy, () => now);

        final execution = await manager.runBackground(
          profile,
          scheduledAt: now,
        );
        final restored = await profiles.getProfile(profile.id);

        expect(execution.decision, BankSyncStartDecision.started);
        expect(restored?.syncMetadata.state, BankConnectionSyncState.connected);
        expect(restored?.syncMetadata.lastResult, BankSyncResult.success);
        expect(restored?.syncMetadata.importedCount, 8);
        expect(restored?.syncMetadata.updatedCount, 3);
        expect(restored?.syncMetadata.deduplicatedCount, 14);
        expect(
          restored?.syncMetadata.nextScheduledSyncAt,
          now.add(const Duration(hours: 1)),
        );
        expect(await marker.readAsString(), 'persistent browser data');
        manager.dispose();
      },
    );

    test('authentication requirement stops automatic retries', () async {
      final profile = await _connectedProfile(profiles);
      final runner = _FakeRunner(
        const BankSyncRunResult(
          result: BankSyncResult.authRequired,
          failureReason: 'USER_AUTHENTICATION_REQUIRED',
        ),
      );
      final manager = _manager(profiles, runner, config, policy, () => now);

      await manager.runBackground(profile, scheduledAt: now);
      final restored = (await profiles.getProfile(profile.id))!;
      final second = await manager.runBackground(restored, scheduledAt: now);

      expect(restored.syncMetadata.state, BankConnectionSyncState.authRequired);
      expect(restored.syncMetadata.nextScheduledSyncAt, isNull);
      expect(second.decision, BankSyncStartDecision.authRequired);
      expect(runner.calls, 1);
      manager.dispose();
    });

    test(
      'temporary failures back off and do not become failed immediately',
      () async {
        final profile = await _connectedProfile(profiles);
        final runner = _FakeRunner(
          const BankSyncRunResult(
            result: BankSyncResult.networkError,
            failureReason: 'NETWORK_ERROR',
          ),
        );
        final manager = _manager(profiles, runner, config, policy, () => now);

        await manager.runBackground(profile, scheduledAt: now);
        final restored = (await profiles.getProfile(profile.id))!;

        expect(
          restored.syncMetadata.state,
          BankConnectionSyncState.temporaryError,
        );
        expect(restored.syncMetadata.consecutiveFailures, 1);
        expect(
          restored.syncMetadata.nextScheduledSyncAt,
          now.add(const Duration(minutes: 10)),
        );
        manager.dispose();
      },
    );

    test('one profile cannot launch two browser jobs at once', () async {
      final profile = await _connectedProfile(profiles);
      final gate = Completer<void>();
      final runner = _FakeRunner(
        const BankSyncRunResult(result: BankSyncResult.success),
        gate: gate,
      );
      final manager = _manager(profiles, runner, config, policy, () => now);

      final first = manager.runBackground(profile, scheduledAt: now);
      await runner.started.future;
      final second = await manager.runBackground(profile, scheduledAt: now);
      gate.complete();
      await first;

      expect(second.decision, BankSyncStartDecision.busy);
      expect(runner.calls, 1);
      manager.dispose();
    });

    test(
      'partial data preserves counters but never advances successful coverage',
      () async {
        final profile = await _connectedProfile(profiles);
        final manager = _manager(
          profiles,
          _FakeRunner(
            const BankSyncRunResult(
              result: BankSyncResult.partial,
              importedCount: 7,
              failureReason: 'INCOMPLETE_HISTORY',
            ),
          ),
          config,
          policy,
          () => now,
        );
        final previous = profile.syncMetadata.lastSuccessfulSyncAt;
        await manager.runBackground(profile, scheduledAt: now);
        final restored = (await profiles.getProfile(profile.id))!;
        expect(restored.syncMetadata.lastResult, BankSyncResult.partial);
        expect(restored.syncMetadata.importedCount, 7);
        expect(restored.syncMetadata.lastSuccessfulSyncAt, previous);
        manager.dispose();
      },
    );

    test(
      'manual timeout revokes late financial writes and holds ownership until stopped',
      () async {
        final profile = await _connectedProfile(profiles);
        const short = BankSyncConfig(
          totalSyncTimeout: Duration(milliseconds: 5),
        );
        final manager = _manager(
          profiles,
          _FakeRunner(const BankSyncRunResult(result: BankSyncResult.success)),
          short,
          BankSyncSchedulePolicy(config: short),
          () => now,
        );
        final gate = Completer<void>();
        var writes = 0;
        final result = await manager.runManual(profile, () async {
          await gate.future;
          FinancialWriteGuard.check();
          writes++;
          return const BankSyncRunResult(result: BankSyncResult.success);
        });
        expect(result.result?.result, BankSyncResult.timeout);
        expect(manager.isBusy, isTrue);
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(writes, 0);
        expect(manager.isBusy, isFalse);
        expect(
          (await profiles.getProfile(profile.id))!.syncMetadata.lastResult,
          BankSyncResult.timeout,
        );
        manager.dispose();
      },
    );

    test('total timeout cancels the writable browser before unlock', () async {
      final profile = await _connectedProfile(profiles);
      final timeoutConfig = const BankSyncConfig(
        jitterPercent: 0,
        retryJitterPercent: 0,
        totalSyncTimeout: Duration(milliseconds: 5),
        browserShutdownTimeout: Duration(seconds: 1),
        queueSpacing: Duration.zero,
      );
      final timeoutPolicy = BankSyncSchedulePolicy(
        config: timeoutConfig,
        random: Random(1),
      );
      final runner = _CancellableFakeRunner();
      final manager = _manager(
        profiles,
        runner,
        timeoutConfig,
        timeoutPolicy,
        () => now,
      );

      final execution = await manager.runBackground(profile, scheduledAt: now);
      final restored = await profiles.getProfile(profile.id);

      expect(execution.result?.result, BankSyncResult.timeout);
      expect(runner.cancelled, isTrue);
      expect(manager.isBusy, isFalse);
      expect(
        restored?.syncMetadata.state,
        BankConnectionSyncState.temporaryError,
      );
      manager.dispose();
    });

    test('an open visible browser prevents a hidden browser launch', () async {
      final profile = await _connectedProfile(profiles);
      final runner = _FakeRunner(
        const BankSyncRunResult(result: BankSyncResult.success),
      );
      final manager = _manager(profiles, runner, config, policy, () => now);

      expect(manager.beginInteractiveSession(profile.id), isTrue);
      final result = await manager.runBackground(profile, scheduledAt: now);

      expect(result.decision, BankSyncStartDecision.busy);
      expect(runner.calls, 0);
      manager.endInteractiveSession(profile.id);
      manager.dispose();
    });

    test(
      'manual success replaces an old timer with a fresh hourly plan',
      () async {
        final profile = await _connectedProfile(
          profiles,
          next: now.add(const Duration(minutes: 5)),
        );
        final runner = _FakeRunner(
          const BankSyncRunResult(result: BankSyncResult.success),
        );
        final manager = _manager(profiles, runner, config, policy, () => now);
        final scheduler = BankSyncScheduler(
          profileManager: profiles,
          manager: manager,
          config: config,
          schedulePolicy: policy,
          clock: () => now,
          armTimers: false,
        );
        expect(scheduler.beginInteractiveSession(profile.id), isTrue);

        await scheduler.runManual(
          profile,
          () async => const BankSyncRunResult(result: BankSyncResult.success),
        );
        final restored = await profiles.getProfile(profile.id);

        expect(
          restored?.syncMetadata.lastBrowserMode,
          BankSyncExecutionMode.manual,
        );
        expect(
          restored?.syncMetadata.nextScheduledSyncAt,
          now.add(const Duration(hours: 1)),
        );
        scheduler.endInteractiveSession(profile.id);
        scheduler.dispose();
        manager.dispose();
      },
    );

    test(
      'disposed manager reports unavailable, not a false busy lock',
      () async {
        final profile = await _connectedProfile(profiles);
        final runner = _FakeRunner(
          const BankSyncRunResult(result: BankSyncResult.success),
        );
        final manager = _manager(profiles, runner, config, policy, () => now);
        manager.dispose();
        expect(
          (await manager.runBackground(profile)).decision,
          BankSyncStartDecision.unavailable,
        );
        expect(
          (await manager.runManual(
            profile,
            () async => runner.result,
          )).decision,
          BankSyncStartDecision.unavailable,
        );
        expect(manager.beginInteractiveSession(profile.id), isFalse);
        expect(runner.calls, 0);
      },
    );

    test(
      'manual cancellation is idempotent and never unlocks pending work',
      () async {
        final profile = await _connectedProfile(profiles);
        final runner = _FakeRunner(
          const BankSyncRunResult(result: BankSyncResult.success),
        );
        final manager = _manager(profiles, runner, config, policy, () => now);
        final entered = Completer<void>();
        final finish = Completer<void>();
        var cancels = 0;
        var writes = 0;
        final job = manager.runManual(
          profile,
          () async {
            entered.complete();
            await finish.future;
            FinancialWriteGuard.check();
            writes++;
            return runner.result;
          },
          onCancel: () async {
            cancels++;
          },
        );
        await entered.future;
        await Future.wait([
          manager.cancel(profile.id),
          manager.cancel(profile.id),
        ]);
        expect(cancels, 1);
        expect(manager.isBusy, isTrue);
        expect(
          (await manager.runBackground(profile)).decision,
          BankSyncStartDecision.busy,
        );
        finish.complete();
        expect((await job).result?.isSuccess, isFalse);
        expect(writes, 0);
        expect(manager.isBusy, isFalse);
        expect(
          (await manager.runManual(
            profile,
            () async => runner.result,
          )).result?.isSuccess,
          isTrue,
        );
        manager.dispose();
      },
    );

    test('disposing the owner aborts its active browser', () async {
      final profile = await _connectedProfile(profiles);
      final runner = _CancellableFakeRunner();
      final manager = _manager(profiles, runner, config, policy, () => now);
      final job = manager.runBackground(profile);
      await runner.started.future;
      manager.dispose();
      expect((await job).result?.isSuccess, isFalse);
      expect(runner.cancelled, isTrue);
      expect(manager.isBusy, isFalse);
    });

    test(
      'upgrade shortens a legacy timer without an immediate bank request',
      () async {
        final profile = await _connectedProfile(
          profiles,
          next: now.add(const Duration(hours: 3)),
        );
        final runner = _FakeRunner(
          const BankSyncRunResult(result: BankSyncResult.success),
        );
        final manager = _manager(profiles, runner, config, policy, () => now);
        final scheduler = BankSyncScheduler(
          profileManager: profiles,
          manager: manager,
          config: config,
          schedulePolicy: policy,
          clock: () => now,
          armTimers: false,
        );
        await scheduler.start();
        expect(runner.calls, 0);
        expect(
          scheduler.profile(profile.id)?.syncMetadata.nextScheduledSyncAt,
          now.add(const Duration(hours: 1)),
        );
        scheduler.dispose();
        manager.dispose();
      },
    );

    test(
      'verified login resumes auth-paused background without inventing coverage',
      () async {
        final profile = await _connectedProfile(profiles);
        await profiles.mutateSyncMetadata(
          profile.id,
          (m) => m.copyWith(
            state: BankConnectionSyncState.authRequired,
            lastResult: BankSyncResult.authRequired,
            lastSuccessfulSyncAt: now.subtract(const Duration(days: 1)),
          ),
        );
        final runner = _FakeRunner(
          const BankSyncRunResult(result: BankSyncResult.success),
        );
        final manager = _manager(profiles, runner, config, policy, () => now);
        final scheduler = BankSyncScheduler(
          profileManager: profiles,
          manager: manager,
          config: config,
          schedulePolicy: policy,
          clock: () => now,
          armTimers: false,
        );
        await scheduler.start();
        expect(runner.calls, 0);
        await scheduler.resumeAfterAuthentication(profile.id);
        final metadata = scheduler.profile(profile.id)!.syncMetadata;
        expect(metadata.state, BankConnectionSyncState.connected);
        expect(
          metadata.lastSuccessfulSyncAt,
          now.subtract(const Duration(days: 1)),
        );
        expect(metadata.lastResult, BankSyncResult.authRequired);
        expect(metadata.nextScheduledSyncAt, now);
        await scheduler.runDueNow();
        expect(runner.calls, 1);
        await scheduler.setBackgroundSyncEnabled(profile.id, false);
        await scheduler.resumeAfterAuthentication(profile.id);
        expect(
          scheduler.profile(profile.id)!.syncMetadata.state,
          BankConnectionSyncState.disabled,
        );
        scheduler.dispose();
        manager.dispose();
      },
    );

    test(
      'an overdue schedule performs one catch-up sync after restart',
      () async {
        final profile = await _connectedProfile(
          profiles,
          next: now.subtract(const Duration(hours: 12)),
        );
        final runner = _FakeRunner(
          const BankSyncRunResult(result: BankSyncResult.success),
        );
        final manager = _manager(profiles, runner, config, policy, () => now);
        final scheduler = BankSyncScheduler(
          profileManager: profiles,
          manager: manager,
          config: config,
          schedulePolicy: policy,
          clock: () => now,
          armTimers: false,
        );

        await scheduler.start();

        expect(runner.calls, 1);
        final restored = await profiles.getProfile(profile.id);
        expect(
          restored?.syncMetadata.nextScheduledSyncAt,
          now.add(const Duration(hours: 1)),
        );
        scheduler.dispose();
        manager.dispose();
      },
    );
  });
}

Future<BankProfile> _connectedProfile(
  BrowserProfileManager profiles, {
  DateTime? next,
}) async {
  final created = await profiles.createProfile(BankConnectorRegistry.sber);
  return profiles.updateSyncMetadata(
    created.id,
    created.syncMetadata.copyWith(
      backgroundSyncEnabled: true,
      state: BankConnectionSyncState.connected,
      nextScheduledSyncAt: next,
    ),
  );
}

BankSyncManager _manager(
  BrowserProfileManager profiles,
  BankBackgroundSyncRunner runner,
  BankSyncConfig config,
  BankSyncSchedulePolicy policy,
  DateTime Function() clock,
) => BankSyncManager(
  profileManager: profiles,
  runners: [runner],
  config: config,
  schedulePolicy: policy,
  clock: clock,
  networkProbe: () async => true,
);

class _FakeRunner implements BankBackgroundSyncRunner {
  _FakeRunner(this.result, {this.gate});

  final BankSyncRunResult result;
  final Completer<void>? gate;
  final started = Completer<void>();
  int calls = 0;

  @override
  String get bankId => 'sber';

  @override
  Future<BankSyncRunResult> run(BankProfile profile) async {
    calls += 1;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    return result;
  }
}

class _CancellableFakeRunner implements CancellableBankBackgroundSyncRunner {
  final _gate = Completer<void>();
  final started = Completer<void>();
  bool cancelled = false;

  @override
  String get bankId => 'sber';

  @override
  Future<BankSyncRunResult> run(BankProfile profile) async {
    started.complete();
    await _gate.future;
    return const BankSyncRunResult(result: BankSyncResult.success);
  }

  @override
  Future<void> cancel(String profileId) async {
    cancelled = true;
    if (!_gate.isCompleted) _gate.complete();
  }
}
