enum BankConnectionSyncState {
  connected,
  syncing,
  authRequired,
  temporaryError,
  failed,
  disconnected,
  disabled,
}

enum BankSyncResult {
  success,
  partial,
  networkError,
  bankUnavailable,
  authRequired,
  parserError,
  timeout,
  unknownError,
  cancelled,
}

enum BankSyncExecutionMode { manual, background }

class BankSyncMetadata {
  const BankSyncMetadata({
    this.backgroundSyncEnabled = false,
    this.state = BankConnectionSyncState.disconnected,
    this.lastResult,
    this.lastAttemptAt,
    this.lastScheduledSyncAt,
    this.lastSuccessfulSyncAt,
    this.lastHistorySyncThrough,
    this.lastFailureAt,
    this.lastFailureReason,
    this.nextScheduledSyncAt,
    this.lastImportedTransactionAt,
    this.consecutiveFailures = 0,
    this.syncDurationMs,
    this.importedCount = 0,
    this.updatedCount = 0,
    this.deduplicatedCount = 0,
    this.lastBrowserMode,
  });

  final bool backgroundSyncEnabled;
  final BankConnectionSyncState state;
  final BankSyncResult? lastResult;
  final DateTime? lastAttemptAt;
  final DateTime? lastScheduledSyncAt;
  final DateTime? lastSuccessfulSyncAt;

  /// Verified history endpoint, not job completion or newest operation date.
  final DateTime? lastHistorySyncThrough;
  final DateTime? lastFailureAt;
  final String? lastFailureReason;
  final DateTime? nextScheduledSyncAt;
  final DateTime? lastImportedTransactionAt;
  final int consecutiveFailures;
  final int? syncDurationMs;
  final int importedCount;
  final int updatedCount;
  final int deduplicatedCount;
  final BankSyncExecutionMode? lastBrowserMode;

  bool get needsAuthentication => state == BankConnectionSyncState.authRequired;
  bool get isSyncing => state == BankConnectionSyncState.syncing;

  BankSyncMetadata copyWith({
    bool? backgroundSyncEnabled,
    BankConnectionSyncState? state,
    BankSyncResult? lastResult,
    bool clearLastResult = false,
    DateTime? lastAttemptAt,
    DateTime? lastScheduledSyncAt,
    DateTime? lastSuccessfulSyncAt,
    DateTime? lastHistorySyncThrough,
    DateTime? lastFailureAt,
    String? lastFailureReason,
    bool clearLastFailureReason = false,
    DateTime? nextScheduledSyncAt,
    bool clearNextScheduledSyncAt = false,
    DateTime? lastImportedTransactionAt,
    int? consecutiveFailures,
    int? syncDurationMs,
    int? importedCount,
    int? updatedCount,
    int? deduplicatedCount,
    BankSyncExecutionMode? lastBrowserMode,
  }) {
    return BankSyncMetadata(
      backgroundSyncEnabled:
          backgroundSyncEnabled ?? this.backgroundSyncEnabled,
      state: state ?? this.state,
      lastResult: clearLastResult ? null : lastResult ?? this.lastResult,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastScheduledSyncAt: lastScheduledSyncAt ?? this.lastScheduledSyncAt,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
      lastHistorySyncThrough:
          lastHistorySyncThrough ?? this.lastHistorySyncThrough,
      lastFailureAt: lastFailureAt ?? this.lastFailureAt,
      lastFailureReason: clearLastFailureReason
          ? null
          : lastFailureReason ?? this.lastFailureReason,
      nextScheduledSyncAt: clearNextScheduledSyncAt
          ? null
          : nextScheduledSyncAt ?? this.nextScheduledSyncAt,
      lastImportedTransactionAt:
          lastImportedTransactionAt ?? this.lastImportedTransactionAt,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      syncDurationMs: syncDurationMs ?? this.syncDurationMs,
      importedCount: importedCount ?? this.importedCount,
      updatedCount: updatedCount ?? this.updatedCount,
      deduplicatedCount: deduplicatedCount ?? this.deduplicatedCount,
      lastBrowserMode: lastBrowserMode ?? this.lastBrowserMode,
    );
  }

  Map<String, Object?> toJson() => {
    'backgroundSyncEnabled': backgroundSyncEnabled,
    'state': state.name,
    'lastResult': lastResult?.name,
    'lastAttemptAt': _date(lastAttemptAt),
    'lastScheduledSyncAt': _date(lastScheduledSyncAt),
    'lastSuccessfulSyncAt': _date(lastSuccessfulSyncAt),
    'lastHistorySyncThrough': _date(lastHistorySyncThrough),
    'lastFailureAt': _date(lastFailureAt),
    'lastFailureReason': lastFailureReason,
    'nextScheduledSyncAt': _date(nextScheduledSyncAt),
    'lastImportedTransactionAt': _date(lastImportedTransactionAt),
    'consecutiveFailures': consecutiveFailures,
    'syncDurationMs': syncDurationMs,
    'importedCount': importedCount,
    'updatedCount': updatedCount,
    'deduplicatedCount': deduplicatedCount,
    'lastBrowserMode': lastBrowserMode?.name,
  };

  factory BankSyncMetadata.fromJson(Map<String, Object?> json) {
    return BankSyncMetadata(
      backgroundSyncEnabled: json['backgroundSyncEnabled'] == true,
      state: _enumByName(
        BankConnectionSyncState.values,
        json['state'],
        BankConnectionSyncState.disconnected,
      ),
      lastResult: _nullableEnumByName(
        BankSyncResult.values,
        json['lastResult'],
      ),
      lastAttemptAt: _parseDate(json['lastAttemptAt']),
      lastScheduledSyncAt: _parseDate(json['lastScheduledSyncAt']),
      lastSuccessfulSyncAt: _parseDate(json['lastSuccessfulSyncAt']),
      lastHistorySyncThrough: _parseDate(json['lastHistorySyncThrough']),
      lastFailureAt: _parseDate(json['lastFailureAt']),
      lastFailureReason: json['lastFailureReason'] as String?,
      nextScheduledSyncAt: _parseDate(json['nextScheduledSyncAt']),
      lastImportedTransactionAt: _parseDate(json['lastImportedTransactionAt']),
      consecutiveFailures: _integer(json['consecutiveFailures']),
      syncDurationMs: switch (json['syncDurationMs']) {
        final num value => value.toInt(),
        _ => null,
      },
      importedCount: _integer(json['importedCount']),
      updatedCount: _integer(json['updatedCount']),
      deduplicatedCount: _integer(json['deduplicatedCount']),
      lastBrowserMode: _nullableEnumByName(
        BankSyncExecutionMode.values,
        json['lastBrowserMode'],
      ),
    );
  }

  static String? _date(DateTime? value) => value?.toUtc().toIso8601String();

  static DateTime? _parseDate(Object? value) => switch (value) {
    final String source when source.isNotEmpty => DateTime.tryParse(
      source,
    )?.toLocal(),
    _ => null,
  };

  static int _integer(Object? value) => switch (value) {
    final num number => number.toInt(),
    _ => 0,
  };

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? source,
    T fallback,
  ) => values.where((value) => value.name == source).firstOrNull ?? fallback;

  static T? _nullableEnumByName<T extends Enum>(
    List<T> values,
    Object? source,
  ) => values.where((value) => value.name == source).firstOrNull;
}

class BankSyncRunResult {
  const BankSyncRunResult({
    required this.result,
    this.failureReason,
    this.importedCount = 0,
    this.updatedCount = 0,
    this.deduplicatedCount = 0,
    this.lastImportedTransactionAt,
    this.historySyncedThrough,
  });

  final BankSyncResult result;
  final String? failureReason;
  final int importedCount;
  final int updatedCount;
  final int deduplicatedCount;
  final DateTime? lastImportedTransactionAt;
  final DateTime? historySyncedThrough;

  bool get isSuccess => result == BankSyncResult.success;
  bool get requiresAuthentication => result == BankSyncResult.authRequired;
}

enum BankSyncStartDecision {
  started,
  unavailable,
  busy,
  disabled,
  authRequired,
  tooRecent,
  unsupported,
  offline,
}

class BankSyncExecution {
  const BankSyncExecution({required this.decision, this.result});

  final BankSyncStartDecision decision;
  final BankSyncRunResult? result;
}
