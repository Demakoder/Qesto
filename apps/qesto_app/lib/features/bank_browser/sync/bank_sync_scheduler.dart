import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/bank_connector_registry.dart';
import '../data/browser_profile_manager.dart';
import '../domain/bank_browser_models.dart';
import '../domain/bank_sync_models.dart';
import '../sber/sber_connector_models.dart';
import 'bank_sync_config.dart';
import 'bank_sync_manager.dart';

class BankSyncScheduler extends ChangeNotifier {
  BankSyncScheduler({
    required this.profileManager,
    required this.manager,
    this.config = const BankSyncConfig(),
    BankSyncSchedulePolicy? schedulePolicy,
    BankSyncClock? clock,
    this.armTimers = true,
  }) : schedulePolicy =
           schedulePolicy ?? BankSyncSchedulePolicy(config: config),
       clock = clock ?? DateTime.now;

  final BrowserProfileManager profileManager;
  final BankSyncManager manager;
  final BankSyncConfig config;
  final BankSyncSchedulePolicy schedulePolicy;
  final BankSyncClock clock;
  final bool armTimers;
  final Map<String, BankProfile> _profiles = {};
  Timer? _timer;
  bool _started = false;
  bool _managerListenerAttached = false;
  bool _draining = false;
  bool _disposed = false;

  List<BankProfile> get profiles => List.unmodifiable(_profiles.values);
  BankProfile? profile(String profileId) => _profiles[profileId];
  bool get isRunning => manager.isBusy;
  String? get activeConnectionId => manager.activeConnectionId;

  Future<void> start() async {
    if (_disposed || _started || !config.backgroundBankSyncEnabled) return;
    _started = true;
    manager.addListener(_forwardManagerState);
    _managerListenerAttached = true;
    await refresh(recover: true);
    await runDueNow();
  }

  Future<void> refresh({bool recover = false}) async {
    if (_disposed) return;
    final loaded = await profileManager.listProfiles();
    if (_disposed) return;
    final normalized = <BankProfile>[];
    for (final profile in loaded) {
      if (_disposed) return;
      normalized.add(recover ? await _recover(profile) : profile);
    }
    _profiles
      ..clear()
      ..addEntries(normalized.map((item) => MapEntry(item.id, item)));
    if (!_disposed) {
      notifyListeners();
      _armNextTimer();
    }
  }

  void _forwardManagerState() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setBackgroundSyncEnabled(String profileId, bool enabled) async {
    // Revoke the active job before the first persistence await.
    final cancellation = !enabled
        ? manager.cancelByUser(profileId)
        : Future<void>.value();
    final profile = await profileManager.getProfile(profileId);
    if (profile == null) {
      await cancellation;
      return;
    }
    final now = clock();
    await profileManager.mutateSyncMetadata(profileId, (previous) {
      final state = enabled
          ? previous.needsAuthentication
                ? BankConnectionSyncState.authRequired
                : BankConnectionSyncState.connected
          : BankConnectionSyncState.disabled;
      final next = enabled && state != BankConnectionSyncState.authRequired
          ? schedulePolicy.plannedAfter(now)
          : null;
      return previous.copyWith(
        backgroundSyncEnabled: enabled,
        state: state,
        nextScheduledSyncAt: next,
        clearNextScheduledSyncAt: next == null,
      );
    });
    await cancellation;
    await refresh();
  }

  Future<void> cancelCurrentSync(String profileId) async {
    await manager.cancelByUser(profileId);
    await refresh();
  }

  bool beginInteractiveSession(String profileId) =>
      manager.beginInteractiveSession(profileId);

  /// Called only after the visible browser verifies an authenticated page.
  /// Login is not a successful import: retain coverage and previous counters.
  Future<void> resumeAfterAuthentication(String profileId) async {
    if (_disposed) return;
    await profileManager.mutateSyncMetadata(profileId, (previous) {
      if (!previous.backgroundSyncEnabled ||
          previous.state == BankConnectionSyncState.disabled ||
          !(previous.needsAuthentication ||
              previous.state == BankConnectionSyncState.disconnected)) {
        return previous;
      }
      return previous.copyWith(
        state: BankConnectionSyncState.connected,
        nextScheduledSyncAt: clock(),
      );
    });
    await refresh();
  }

  void endInteractiveSession(String profileId) {
    manager.endInteractiveSession(profileId);
    _armNextTimer();
  }

  Future<BankSyncExecution> runManual(
    BankProfile profile,
    BankManualSyncOperation operation, {
    Future<void> Function()? onCancel,
  }) async {
    final result = await manager.runManual(
      profile,
      operation,
      onCancel: onCancel,
    );
    await refresh();
    return result;
  }

  Future<void> runDueNow() async {
    if (_disposed || _draining || !_started) return;
    _draining = true;
    _timer?.cancel();
    try {
      final now = clock();
      final due =
          _profiles.values.where((profile) {
            final metadata = profile.syncMetadata;
            final next = metadata.nextScheduledSyncAt;
            return metadata.backgroundSyncEnabled &&
                !metadata.needsAuthentication &&
                metadata.state != BankConnectionSyncState.disabled &&
                next != null &&
                !next.isAfter(now);
          }).toList()..sort(
            (left, right) => left.syncMetadata.nextScheduledSyncAt!.compareTo(
              right.syncMetadata.nextScheduledSyncAt!,
            ),
          );
      for (var index = 0; index < due.length; index++) {
        if (_disposed) break;
        final latest = await profileManager.getProfile(due[index].id);
        if (latest == null || _disposed) continue;
        final result = await manager.runBackground(
          latest,
          scheduledAt: latest.syncMetadata.nextScheduledSyncAt,
        );
        if (result.decision == BankSyncStartDecision.busy) {
          await _rescheduleBusy(latest);
        } else if (result.decision == BankSyncStartDecision.tooRecent) {
          await _rescheduleAfterMinimumInterval(latest);
        }
        if (index + 1 < due.length && config.queueSpacing > Duration.zero) {
          await Future<void>.delayed(config.queueSpacing);
        }
      }
      await refresh();
    } finally {
      _draining = false;
      _armNextTimer();
    }
  }

  /// Explicit refresh uses the same off-screen runtime as the hourly job.
  /// It bypasses only scheduling gates, never the browser/profile lock.
  Future<BankSyncExecution> refreshNow(
    String profileId, {
    SberSyncRange? range,
  }) async {
    if (_disposed) {
      return const BankSyncExecution(
        decision: BankSyncStartDecision.unavailable,
      );
    }
    final latest = await profileManager.getProfile(profileId);
    if (latest == null) {
      return const BankSyncExecution(
        decision: BankSyncStartDecision.unavailable,
      );
    }
    final result = await manager.runBackground(
      latest,
      userInitiated: true,
      range: range,
    );
    await refresh();
    return result;
  }

  Future<BankProfile> _recover(BankProfile profile) async {
    final bank = BankConnectorRegistry.byId(profile.bankId);
    if (bank?.supportsBackgroundSync != true) return profile;
    final now = clock();
    var metadata = profile.syncMetadata;
    if (!metadata.backgroundSyncEnabled) {
      if (metadata.state != BankConnectionSyncState.disabled ||
          metadata.nextScheduledSyncAt != null) {
        metadata = metadata.copyWith(
          state: BankConnectionSyncState.disabled,
          clearNextScheduledSyncAt: true,
        );
      }
    } else if (metadata.needsAuthentication) {
      metadata = metadata.copyWith(clearNextScheduledSyncAt: true);
    } else if (metadata.state == BankConnectionSyncState.syncing) {
      final failures = metadata.consecutiveFailures + 1;
      metadata = metadata.copyWith(
        state: BankConnectionSyncState.temporaryError,
        lastResult: BankSyncResult.unknownError,
        lastFailureAt: now,
        lastFailureReason: 'INTERRUPTED_BY_APP_RESTART',
        consecutiveFailures: failures,
        nextScheduledSyncAt: schedulePolicy.retryAfter(now, failures),
      );
    } else if (metadata.nextScheduledSyncAt != null &&
        metadata.nextScheduledSyncAt!.isAfter(
          now.add(config.baseInterval * (1 + config.jitterPercent)),
        )) {
      // Upgrade an older three-hour plan without running a burst on startup.
      metadata = metadata.copyWith(
        nextScheduledSyncAt: schedulePolicy.plannedAfter(now),
      );
    } else if (metadata.nextScheduledSyncAt == null) {
      final lastSuccess = metadata.lastSuccessfulSyncAt ?? profile.lastSyncAt;
      final overdue =
          lastSuccess != null &&
          now.difference(lastSuccess) >= config.baseInterval;
      metadata = metadata.copyWith(
        state: metadata.state == BankConnectionSyncState.disconnected
            ? BankConnectionSyncState.connected
            : metadata.state,
        nextScheduledSyncAt: overdue
            ? now
            : schedulePolicy.plannedAfter(lastSuccess ?? now),
      );
    }
    if (metadata == profile.syncMetadata) return profile;
    return profileManager.updateSyncMetadata(profile.id, metadata);
  }

  Future<void> _rescheduleBusy(BankProfile profile) async {
    await profileManager.mutateSyncMetadata(
      profile.id,
      (current) => current.copyWith(
        nextScheduledSyncAt: clock().add(config.busyRescheduleDelay),
      ),
    );
  }

  Future<void> _rescheduleAfterMinimumInterval(BankProfile profile) async {
    final lastSuccess =
        profile.syncMetadata.lastSuccessfulSyncAt ?? profile.lastSyncAt;
    final earliest = (lastSuccess ?? clock()).add(config.minimumInterval);
    final planned = schedulePolicy.plannedAfter(lastSuccess ?? clock());
    await profileManager.mutateSyncMetadata(
      profile.id,
      (current) => current.copyWith(
        nextScheduledSyncAt: planned.isAfter(earliest) ? planned : earliest,
      ),
    );
  }

  void _armNextTimer() {
    _timer?.cancel();
    if (!armTimers || !_started || _draining || _disposed) return;
    final now = clock();
    final nextValues = _profiles.values
        .where(
          (profile) =>
              profile.syncMetadata.backgroundSyncEnabled &&
              !profile.syncMetadata.needsAuthentication &&
              profile.syncMetadata.state != BankConnectionSyncState.disabled,
        )
        .map((profile) => profile.syncMetadata.nextScheduledSyncAt)
        .whereType<DateTime>()
        .toList();
    if (nextValues.isEmpty) return;
    nextValues.sort();
    final delay = nextValues.first.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(runDueNow());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_managerListenerAttached) {
      manager.removeListener(_forwardManagerState);
    }
    super.dispose();
  }
}
