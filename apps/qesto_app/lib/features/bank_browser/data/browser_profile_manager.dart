import 'dart:io';
import 'dart:math';
import '../../../data/persistence/recoverable_json_file.dart';

import '../domain/bank_browser_models.dart';
import '../domain/bank_sync_models.dart';

class BrowserProfileManager {
  BrowserProfileManager({Directory? rootDirectory})
    : rootDirectory = rootDirectory ?? _defaultRoot();

  final Directory rootDirectory;

  Directory profileDirectory(String profileId) =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}$profileId');

  // Chrome Runtime requires an immediate child of root_cache_path. A nested
  // <id>/cef path silently becomes an OffTheRecord profile in CEF 149.
  Directory cefDataDirectory(String profileId) {
    if (!_validId(profileId)) throw ArgumentError.value(profileId, 'profileId');
    return profileDirectory(profileId);
  }

  Future<void> prepareCefProfile(String profileId) async {
    final target = cefDataDirectory(profileId);
    _assertInsideRoot(target);
    if (await FileSystemEntity.isLink(target.path)) {
      throw StateError('Linked browser profiles are not supported');
    }
    final legacy = Directory('${target.path}${Platform.pathSeparator}cef');
    // Never silently discard a nonempty legacy profile from another runtime.
    // Empty legacy folders (the affected Windows case) may remain as-is.
    if (await legacy.exists() &&
        !await legacy.list(followLinks: false).isEmpty) {
      throw StateError('Legacy browser profile requires explicit migration');
    }
    await target.create(recursive: true);
  }

  Future<BankProfile> createProfile(BankConnectorConfig bank) async {
    await rootDirectory.create(recursive: true);
    final now = DateTime.now();
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final id = '${bank.bankId}-${now.microsecondsSinceEpoch}-$random';
    final profile = BankProfile(
      id: id,
      bankId: bank.bankId,
      displayName: bank.displayName,
      createdAt: now,
      lastOpenedAt: now,
      lastKnownUrl: bank.startUrl,
      syncMetadata: BankSyncMetadata(
        backgroundSyncEnabled: bank.supportsBackgroundSync,
        state: BankConnectionSyncState.disconnected,
      ),
    );
    await cefDataDirectory(id).create(recursive: true);
    await _writeProfile(profile);
    return profile;
  }

  Future<BankProfile?> getProfile(String id) async {
    if (!_validId(id)) return null;
    final file = _metadataFile(id);
    if (!await profileDirectory(id).exists()) return null;
    try {
      final decoded = await RecoverableJsonFile(file).read();
      return decoded == null
          ? null
          : BankProfile.fromJson(decoded.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  Future<List<BankProfile>> listProfiles() async {
    if (!await rootDirectory.exists()) return const [];
    final profiles = <BankProfile>[];
    await for (final entity in rootDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final id = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      final profile = await getProfile(id);
      if (profile != null) profiles.add(profile);
    }
    profiles.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return profiles;
  }

  Future<bool> profileExists(String id) async =>
      _validId(id) && await getProfile(id) != null;

  Future<BankProfile> openProfile(BankProfile profile) async {
    // BrowserController may hold a profile captured before the sync manager
    // persisted scheduling metadata. Merge into the newest disk revision so
    // opening hidden CEF cannot roll back attempt, mode or retry state.
    return _updateProfile(
      profile.id,
      (latest) => latest.copyWith(lastOpenedAt: DateTime.now()),
    );
  }

  Future<BankProfile> updateLastKnownUrl(
    BankProfile profile,
    Uri sanitizedUrl,
  ) async {
    return _updateProfile(
      profile.id,
      (latest) => latest.copyWith(lastKnownUrl: sanitizedUrl),
    );
  }

  Future<BankProfile> updateLastSync(
    BankProfile profile,
    DateTime syncedAt,
  ) async {
    return _updateProfile(
      profile.id,
      (latest) => latest.copyWith(
        lastSyncAt: syncedAt,
        syncMetadata: latest.syncMetadata.copyWith(
          state: BankConnectionSyncState.connected,
          lastResult: BankSyncResult.success,
          lastSuccessfulSyncAt: syncedAt,
          consecutiveFailures: 0,
          clearLastFailureReason: true,
        ),
      ),
    );
  }

  Future<BankProfile> updateSyncMetadata(
    String profileId,
    BankSyncMetadata metadata,
  ) async {
    return _updateProfile(
      profileId,
      (profile) => profile.copyWith(
        lastSyncAt: metadata.lastSuccessfulSyncAt,
        syncMetadata: metadata,
      ),
    );
  }

  Future<BankProfile> _updateProfile(
    String id,
    BankProfile Function(BankProfile) transform,
  ) async {
    if (!_validId(id)) throw ArgumentError.value(id, 'id');
    late BankProfile updated;
    await RecoverableJsonFile(_metadataFile(id)).update((current) {
      if (current == null) throw StateError('Bank profile no longer exists');
      updated = transform(
        BankProfile.fromJson(current.cast<String, Object?>()),
      );
      return updated.toJson();
    });
    return updated;
  }

  Future<BankProfile> mutateSyncMetadata(
    String id,
    BankSyncMetadata Function(BankSyncMetadata) transform,
  ) => _updateProfile(id, (profile) {
    final metadata = transform(profile.syncMetadata);
    return profile.copyWith(
      lastSyncAt: metadata.lastSuccessfulSyncAt,
      syncMetadata: metadata,
    );
  });

  /// Call only after the CEF browser and its RequestContext have closed.
  Future<void> deleteProfile(String id) async {
    if (!_validId(id)) throw ArgumentError.value(id, 'id');
    final directory = profileDirectory(id);
    if (!await directory.exists()) return;
    _assertInsideRoot(directory);
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await directory.delete(recursive: true);
        return;
      } on Object catch (error) {
        lastError = error;
        await Future<void>.delayed(Duration(milliseconds: 150 << attempt));
      }
    }
    throw FileSystemException(
      'Не удалось удалить локальный профиль браузера',
      directory.path,
      lastError is OSError ? lastError : null,
    );
  }

  Future<void> clearAllProfiles() async {
    final profiles = await listProfiles();
    for (final profile in profiles) {
      await deleteProfile(profile.id);
    }
  }

  File _metadataFile(String id) =>
      File('${profileDirectory(id).path}${Platform.pathSeparator}profile.json');

  Future<void> _writeProfile(BankProfile profile) async {
    if (!_validId(profile.id)) throw ArgumentError.value(profile.id, 'id');
    final directory = profileDirectory(profile.id);
    _assertInsideRoot(directory);
    await directory.create(recursive: true);
    final target = _metadataFile(profile.id);
    await RecoverableJsonFile(target).write(profile.toJson());
  }

  void _assertInsideRoot(Directory directory) {
    final root = rootDirectory.absolute.path.toLowerCase();
    final candidate = directory.absolute.path.toLowerCase();
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (!candidate.startsWith(prefix) || candidate == root) {
      throw StateError('Browser profile path escaped its local root');
    }
  }

  bool _validId(String value) =>
      RegExp(r'^[a-z0-9][a-z0-9_-]{2,127}$').hasMatch(value);

  static Directory _defaultRoot() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.trim().isEmpty) {
      return Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}Qesto${Platform.pathSeparator}BankBrowser',
      );
    }
    return Directory(
      '$localAppData${Platform.pathSeparator}Qesto${Platform.pathSeparator}BankBrowser',
    );
  }
}
