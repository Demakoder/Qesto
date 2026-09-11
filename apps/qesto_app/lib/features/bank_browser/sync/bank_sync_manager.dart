import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../../../core/safety/financial_write_guard.dart';

import '../config/bank_connector_registry.dart';
import '../data/browser_profile_manager.dart';
import '../domain/bank_browser_models.dart';
import '../domain/bank_sync_models.dart';
import '../sber/sber_connector_models.dart';
import 'bank_sync_config.dart';

typedef BankSyncClock = DateTime Function();
typedef BankNetworkProbe = Future<bool> Function();
typedef BankManualSyncOperation = Future<BankSyncRunResult> Function();

abstract interface class BankBackgroundSyncRunner {
  String get bankId;

  Future<BankSyncRunResult> run(BankProfile profile);
}

abstract interface class CancellableBankBackgroundSyncRunner
    implements BankBackgroundSyncRunner {
  Future<void> cancel(String profileId);
}

abstract interface class RangedBankBackgroundSyncRunner
    implements BankBackgroundSyncRunner {
  Future<BankSyncRunResult> runForRange(
    BankProfile profile,
    SberSyncRange range,
  );
}

class BankSyncManager extends ChangeNotifier {
  BankSyncManager({
    required this.profileManager,
    required Iterable<BankBackgroundSyncRunner> runners,
    this.config = const BankSyncConfig(),
    BankSyncSchedulePolicy? schedulePolicy,
    BankSyncClock? clock,
    BankNetworkProbe? networkProbe,
  }) : schedulePolicy =
           schedulePolicy ?? BankSyncSchedulePolicy(config: config),
       clock = clock ?? DateTime.now,
       networkProbe = networkProbe ?? _defaultNetworkProbe,
       _runners = {for (final runner in runners) runner.bankId: runner};

  final BrowserProfileManager profileManager;
  final BankSyncConfig config;
  final BankSyncSchedulePolicy schedulePolicy;
  final BankSyncClock clock;
  final BankNetworkProbe networkProbe;
  final Map<String, BankBackgroundSyncRunner> _runners;
  final Set<String> _interactiveConnections = {};
  final Set<String> _runningConnections = {};
  String? _activeConnectionId;
  final Set<FinancialWriteGuard> _guards = {};
  final Map<String, FinancialWriteGuard> _profileGuards = {};
  final Map<String, Future<void> Function()> _aborters = {};
  final Map<String, Future<void>> _aborting = {};
  final Set<String> _userCancelled = {};
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final guard in _guards) {
      guard.cancel();
    }
    for (final id in _profileGuards.keys.toList()) {
      unawaited(cancel(id));
    }
    super.dispose();
  }

  /// Revoke writes immediately; native shutdown is bounded and idempotent.
  /// Ownership is released only when the original job actually finishes.
  Future<void> cancel(String profileId) {
    if (!_profileGuards.containsKey(profileId)) return Future.value();
    _profileGuards[profileId]?.cancel();
    return _aborting.putIfAbsent(profileId, () async {
      try {
        await _aborters[profileId]?.call().timeout(
          config.browserShutdownTimeout,
        );
      } on Object {
        // Never unlock a still-running job just because shutdown failed.
      }
    });
  }

  bool get isBusy => _activeConnectionId != null;
  bool isCancelling(String profileId) => _userCancelled.contains(profileId);

  Future<void> cancelByUser(String profileId) async {
    if (!isSyncing(profileId)) return;
    _userCancelled.add(profileId);
    if (!_disposed) notifyListeners();
    await cancel(profileId);
  }

  String? get activeConnectionId => _activeConnectionId;
  bool isSyncing(String profileId) => _runningConnections.contains(profileId);
  bool hasInteractiveSession(String profileId) =>
      _interactiveConnections.contains(profileId);

  bool beginInteractiveSession(String profileId) {
    if (_disposed) return false;
    if (_activeConnectionId != null ||
        _interactiveConnections.isNotEmpty ||
        _runningConnections.contains(profileId)) {
      return false;
    }
    _interactiveConnections.add(profileId);
    notifyListeners();
    return true;
  }

  void endInteractiveSession(String profileId) {
    if (_interactiveConnections.remove(profileId) && !_disposed) {
      notifyListeners();
    }
  }

  Future<BankSyncExecution> runBackground(
    BankProfile profile, {
    DateTime? scheduledAt,
    bool userInitiated = false,
    SberSyncRange? range,
  }) async {
    if (_disposed) {
      return const BankSyncExecution(
        decision: BankSyncStartDecision.unavailable,
      );
    }
    final bank = BankConnectorRegistry.byId(profile.bankId);
    if (!config.backgroundBankSyncEnabled ||
        bank?.supportsBackgroundSync != true ||
        !_runners.containsKey(profile.bankId)) {
      return const BankSyncExecution(
        decision: BankSyncStartDecision.unsupported,
      );
    }
    final metadata = profile.syncMetadata;
    if (!userInitiated &&
        (!metadata.backgroundSyncEnabled ||
            metadata.state == BankConnectionSyncState.disabled)) {
      return const BankSyncExecution(decision: BankSyncStartDecision.disabled);
    }
    if (!userInitiated && metadata.needsAuthentication) {
      return const BankSyncExecution(
        decision: BankSyncStartDecision.authRequired,
      );
    }
    final now = clock();
    final lastSuccess = metadata.lastSuccessfulSyncAt ?? profile.lastSyncAt;
    if (!userInitiated &&
        lastSuccess != null &&
        now.difference(lastSuccess) < config.minimumInterval) {
      return const BankSyncExecution(decision: BankSyncStartDecision.tooRecent);
    }
    if (range != null &&
        _runners[profile.bankId] is! RangedBankBackgroundSyncRunner) {
      return const BankSyncExecution(
        decision: BankSyncStartDecision.unsupported,
      );
    }
    if (!_acquire(profile.id, allowInteractiveOwner: false)) {
      return const BankSyncExecution(decision: BankSyncStartDecision.busy);
    }

    final attempt = now;
    final guard = FinancialWriteGuard();
    _guards.add(guard);
    _profileGuards[profile.id] = guard;
    final runner = _runners[profile.bankId]!;
    if (runner is CancellableBankBackgroundSyncRunner) {
      _aborters[profile.id] = () => runner.cancel(profile.id);
    }
    Future<BankSyncRunResult>? work;
    var workDone = false;
    try {
      await _markSyncing(
        profile,
        mode: BankSyncExecutionMode.background,
        attempt: attempt,
        scheduledAt: userInitiated
            ? attempt
            : scheduledAt ?? metadata.nextScheduledSyncAt ?? attempt,
      );
      final online = await networkProbe().timeout(config.pageLoadTimeout);
      await guard.run(() async => FinancialWriteGuard.check());
      if (!online) {
        final result = const BankSyncRunResult(
          result: BankSyncResult.networkError,
          failureReason: 'NETWORK_UNAVAILABLE',
        );
        await _complete(profile.id, result, attempt: attempt);
        return BankSyncExecution(
          decision: BankSyncStartDecision.offline,
          result: result,
        );
      }
      work = guard
          .run(() async {
            final result =
                range != null && runner is RangedBankBackgroundSyncRunner
                ? await runner.runForRange(profile, range)
                : await runner.run(profile);
            FinancialWriteGuard.check();
            return result;
          })
          .whenComplete(() => workDone = true);
      final result = await work.timeout(config.totalSyncTimeout);
      await _complete(profile.id, result, attempt: attempt);
      return BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } on FinancialWriteCancelled {
      const result = BankSyncRunResult(result: BankSyncResult.cancelled);
      await _complete(profile.id, result, attempt: attempt);
      return const BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } on TimeoutException {
      guard.cancel();
      await cancel(profile.id);
      final result = const BankSyncRunResult(
        result: BankSyncResult.timeout,
        failureReason: 'TOTAL_SYNC_TIMEOUT',
      );
      await _complete(profile.id, result, attempt: attempt);
      return BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } on SocketException {
      final result = const BankSyncRunResult(
        result: BankSyncResult.networkError,
        failureReason: 'NETWORK_ERROR',
      );
      await _complete(profile.id, result, attempt: attempt);
      return BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } on Object {
      final result = BankSyncRunResult(
        result: _userCancelled.contains(profile.id)
            ? BankSyncResult.cancelled
            : BankSyncResult.unknownError,
        failureReason: _userCancelled.contains(profile.id)
            ? null
            : 'BACKGROUND_SYNC_ERROR',
      );
      await _complete(profile.id, result, attempt: attempt);
      return BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } finally {
      guard.cancel();
      _guards.remove(guard);
      if (work != null && !workDone) {
        // Keep ownership until the old native job has actually stopped.
        unawaited(
          work.then<void>(
            (_) => _release(profile.id),
            onError: (Object _, StackTrace _) => _release(profile.id),
          ),
        );
      } else {
        _release(profile.id);
      }
    }
  }

  Future<BankSyncExecution> runManual(
    BankProfile profile,
    BankManualSyncOperation operation, {
    Future<void> Function()? onCancel,
  }) async {
    if (_disposed) {
      return const BankSyncExecution(
        decision: BankSyncStartDecision.unavailable,
      );
    }
    if (!_acquire(profile.id, allowInteractiveOwner: true)) {
      return const BankSyncExecution(decision: BankSyncStartDecision.busy);
    }
    final attempt = clock();
    final guard = FinancialWriteGuard();
    _guards.add(guard);
    _profileGuards[profile.id] = guard;
    if (onCancel != null) _aborters[profile.id] = onCancel;
    Future<BankSyncRunResult>? work;
    var workDone = false;
    try {
      await _markSyncing(
        profile,
        mode: BankSyncExecutionMode.manual,
        attempt: attempt,
      );
      work = guard
          .run(() async {
            final result = await operation();
            FinancialWriteGuard.check();
            return result;
          })
          .whenComplete(() => workDone = true);
      final result = await work.timeout(config.totalSyncTimeout);
      await _complete(profile.id, result, attempt: attempt);
      return BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } on FinancialWriteCancelled {
      const result = BankSyncRunResult(result: BankSyncResult.cancelled);
      await _complete(profile.id, result, attempt: attempt);
      return const BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } on TimeoutException {
      guard.cancel();
      await cancel(profile.id);
      final result = const BankSyncRunResult(
        result: BankSyncResult.timeout,
        failureReason: 'MANUAL_SYNC_TIMEOUT',
      );
      await _complete(profile.id, result, attempt: attempt);
      return BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } on Object {
      final result = BankSyncRunResult(
        result: _userCancelled.contains(profile.id)
            ? BankSyncResult.cancelled
            : BankSyncResult.unknownError,
        failureReason: _userCancelled.contains(profile.id)
            ? null
            : 'MANUAL_SYNC_ERROR',
      );
      await _complete(profile.id, result, attempt: attempt);
      return BankSyncExecution(
        decision: BankSyncStartDecision.started,
        result: result,
      );
    } finally {
      guard.cancel();
      _guards.remove(guard);
      if (work != null && !workDone) {
        unawaited(
          work.then<void>(
            (_) => _release(profile.id),
            onError: (Object _, StackTrace _) => _release(profile.id),
          ),
        );
      } else {
        _release(profile.id);
      }
    }
  }

  bool _acquire(String profileId, {required bool allowInteractiveOwner}) {
    if (_disposed) return false;
    if (_activeConnectionId != null ||
        _runningConnections.contains(profileId)) {
      return false;
    }
    if (_interactiveConnections.isNotEmpty &&
        !(allowInteractiveOwner &&
            _interactiveConnections.length == 1 &&
            _interactiveConnections.contains(profileId))) {
      return false;
    }
    _activeConnectionId = profileId;
    _runningConnections.add(profileId);
    notifyListeners();
    return true;
  }

  void _release(String profileId) {
    _userCancelled.remove(profileId);
    _profileGuards.remove(profileId);
    _aborters.remove(profileId);
    _aborting.remove(profileId);
    _runningConnections.remove(profileId);
    if (_activeConnectionId == profileId) _activeConnectionId = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _markSyncing(
    BankProfile profile, {
    required BankSyncExecutionMode mode,
    required DateTime attempt,
    DateTime? scheduledAt,
  }) async {
    if (_disposed) return;
    await profileManager.mutateSyncMetadata(
      profile.id,
      (latest) => latest.copyWith(
        state: BankConnectionSyncState.syncing,
        lastAttemptAt: attempt,
        lastScheduledSyncAt: scheduledAt,
        lastBrowserMode: mode,
      ),
    );
    if (!_disposed) notifyListeners();
  }

  Future<void> _complete(
    String profileId,
    BankSyncRunResult result, {
    required DateTime attempt,
  }) async {
    if (_disposed) return;
    final profile = await profileManager.getProfile(profileId);
    if (profile == null || _disposed) return;
    final finished = clock();
    await profileManager.mutateSyncMetadata(profileId, (previous) {
      if (result.result == BankSyncResult.cancelled) {
        final next = previous.backgroundSyncEnabled
            ? schedulePolicy.plannedAfter(finished)
            : null;
        return previous.copyWith(
          state: previous.backgroundSyncEnabled
              ? BankConnectionSyncState.connected
              : BankConnectionSyncState.disabled,
          lastResult: BankSyncResult.cancelled,
          nextScheduledSyncAt: next,
          clearNextScheduledSyncAt: next == null,
          syncDurationMs: finished.difference(attempt).inMilliseconds,
        );
      }
      final failures = result.isSuccess ? 0 : previous.consecutiveFailures + 1;
      final next = _nextAfterResult(
        previous: previous,
        result: result,
        finished: finished,
        failures: failures,
      );
      final state = switch (result.result) {
        BankSyncResult.success => BankConnectionSyncState.connected,
        BankSyncResult.cancelled => BankConnectionSyncState.connected,
        BankSyncResult.authRequired => BankConnectionSyncState.authRequired,
        BankSyncResult.parserError ||
        BankSyncResult.partial ||
        BankSyncResult.networkError ||
        BankSyncResult.bankUnavailable ||
        BankSyncResult.timeout => BankConnectionSyncState.temporaryError,
        BankSyncResult.unknownError when failures >= 6 =>
          BankConnectionSyncState.failed,
        BankSyncResult.unknownError => BankConnectionSyncState.temporaryError,
      };
      final metadata = previous.copyWith(
        state: previous.state == BankConnectionSyncState.disabled
            ? BankConnectionSyncState.disabled
            : state,
        lastResult: result.result,
        lastSuccessfulSyncAt: result.isSuccess ? finished : null,
        lastHistorySyncThrough:
            result.isSuccess &&
                result.historySyncedThrough != null &&
                (previous.lastHistorySyncThrough == null ||
                    result.historySyncedThrough!.isAfter(
                      previous.lastHistorySyncThrough!,
                    ))
            ? result.historySyncedThrough
            : null,
        lastFailureAt: result.isSuccess ? null : finished,
        lastFailureReason: result.failureReason,
        clearLastFailureReason: result.isSuccess,
        nextScheduledSyncAt: next,
        clearNextScheduledSyncAt: next == null,
        lastImportedTransactionAt: result.lastImportedTransactionAt,
        consecutiveFailures: failures,
        syncDurationMs: finished.difference(attempt).inMilliseconds,
        importedCount: result.importedCount,
        updatedCount: result.updatedCount,
        deduplicatedCount: result.deduplicatedCount,
      );
      return metadata;
    });
    if (!_disposed) notifyListeners();
  }

  DateTime? _nextAfterResult({
    required BankSyncMetadata previous,
    required BankSyncRunResult result,
    required DateTime finished,
    required int failures,
  }) {
    if (!previous.backgroundSyncEnabled || result.requiresAuthentication) {
      return null;
    }
    if (result.isSuccess) {
      final scheduled = previous.lastScheduledSyncAt;
      final scheduledIsCurrentCycle =
          previous.lastBrowserMode == BankSyncExecutionMode.background &&
          scheduled != null &&
          !finished.isBefore(scheduled) &&
          finished.difference(scheduled) < config.baseInterval;
      return schedulePolicy.plannedAfter(
        scheduledIsCurrentCycle ? scheduled : finished,
      );
    }
    final parserLimitReached =
        result.result == BankSyncResult.parserError &&
        failures > config.parserRetryLimit;
    final retryLimitReached = failures > config.retrySchedule.length;
    if (parserLimitReached || retryLimitReached) {
      return schedulePolicy.plannedAfter(finished);
    }
    return schedulePolicy.retryAfter(finished, failures);
  }

  static Future<bool> _defaultNetworkProbe() async {
    try {
      final values = await InternetAddress.lookup(
        'online.sberbank.ru',
      ).timeout(const Duration(seconds: 5));
      return values.isNotEmpty;
    } on Object {
      return false;
    }
  }
}
