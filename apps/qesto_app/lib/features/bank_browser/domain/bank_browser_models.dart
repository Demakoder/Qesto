import 'bank_sync_models.dart';

enum BankBrowserLifecycle { closed, opening, loading, ready, error }

enum NavigationDecision { allow, block, openExternally, requireConfirmation }

enum BankBrowserLoadState { idle, started, committed, finished, failed }

enum BrowserMode { auth, read }

enum BrowserPresentationMode { visible, background }

enum ReadOnlyBrowserValue { documentTitle, locationOrigin }

class BankConnectorConfig {
  const BankConnectorConfig({
    required this.bankId,
    required this.displayName,
    required this.startUrl,
    required this.allowedOrigins,
    this.authOrigins = const {},
    this.supportsBackgroundSync = false,
  });

  final String bankId;
  final String displayName;
  final Uri startUrl;
  final Set<String> allowedOrigins;
  final Set<String> authOrigins;
  final bool supportsBackgroundSync;

  Set<String> get allTrustedOrigins => {...allowedOrigins, ...authOrigins};
}

class BankProfile {
  const BankProfile({
    required this.id,
    required this.bankId,
    required this.displayName,
    required this.createdAt,
    required this.lastOpenedAt,
    this.lastKnownUrl,
    this.lastSyncAt,
    this.syncMetadata = const BankSyncMetadata(),
  });

  final String id;
  final String bankId;
  final String displayName;
  final DateTime createdAt;
  final DateTime lastOpenedAt;
  final Uri? lastKnownUrl;
  final DateTime? lastSyncAt;
  final BankSyncMetadata syncMetadata;

  BankProfile copyWith({
    DateTime? lastOpenedAt,
    Uri? lastKnownUrl,
    DateTime? lastSyncAt,
    BankSyncMetadata? syncMetadata,
  }) {
    return BankProfile(
      id: id,
      bankId: bankId,
      displayName: displayName,
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      lastKnownUrl: lastKnownUrl ?? this.lastKnownUrl,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      syncMetadata: syncMetadata ?? this.syncMetadata,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'bankId': bankId,
    'displayName': displayName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toUtc().toIso8601String(),
    'lastKnownUrl': lastKnownUrl?.toString(),
    'lastSyncAt': lastSyncAt?.toUtc().toIso8601String(),
    'syncMetadata': syncMetadata.toJson(),
  };

  static BankProfile fromJson(Map<String, Object?> json) {
    final lastSyncAt = switch (json['lastSyncAt']) {
      final String value when value.isNotEmpty => DateTime.tryParse(
        value,
      )?.toLocal(),
      _ => null,
    };
    final storedSync = json['syncMetadata'];
    return BankProfile(
      id: json['id']! as String,
      bankId: json['bankId']! as String,
      displayName: json['displayName']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
      lastOpenedAt: DateTime.parse(json['lastOpenedAt']! as String).toLocal(),
      lastKnownUrl: switch (json['lastKnownUrl']) {
        final String value when value.isNotEmpty => Uri.tryParse(value),
        _ => null,
      },
      lastSyncAt: lastSyncAt,
      syncMetadata: storedSync is Map
          ? BankSyncMetadata.fromJson(storedSync.cast<String, Object?>())
          : BankSyncMetadata(
              backgroundSyncEnabled: json['bankId'] == 'sber',
              state: BankConnectionSyncState.connected,
              lastSuccessfulSyncAt: lastSyncAt,
            ),
    );
  }
}

class BankBrowserState {
  const BankBrowserState({
    required this.lifecycle,
    required this.profile,
    required this.bank,
    required this.loadState,
    this.currentUrl,
    this.origin,
    this.canGoBack = false,
    this.canGoForward = false,
    this.lastSuccessfulLoad,
    this.errorMessage,
  });

  final BankBrowserLifecycle lifecycle;
  final BankProfile profile;
  final BankConnectorConfig bank;
  final BankBrowserLoadState loadState;
  final Uri? currentUrl;
  final String? origin;
  final bool canGoBack;
  final bool canGoForward;
  final DateTime? lastSuccessfulLoad;
  final String? errorMessage;
}

class PageObservation {
  const PageObservation({
    required this.profileId,
    required this.currentUrl,
    required this.origin,
    required this.navigationState,
    required this.loadState,
    required this.timestamp,
  });

  final String profileId;
  final Uri currentUrl;
  final String origin;
  final BankBrowserLifecycle navigationState;
  final BankBrowserLoadState loadState;
  final DateTime timestamp;
}
