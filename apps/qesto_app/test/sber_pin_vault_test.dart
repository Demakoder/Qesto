import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/sber/sber_auth_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late BrowserProfileManager profiles;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('qesto-pin-test-');
    profiles = BrowserProfileManager(rootDirectory: root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('PINs are isolated and deleting one does not affect another', () async {
    const a = SberPinVault(profileId: 'fixture-a');
    const b = SberPinVault(profileId: 'fixture-b');
    await a.write('1234');
    await b.write('5678');
    expect(await a.read(), '1234');
    expect(await b.read(), '5678');
    await a.delete();
    expect(await a.read(), isNull);
    expect(await b.read(), '5678');
  });
  test(
    'legacy PIN migrates once to the only profile, not to a future profile',
    () async {
      final profile = await profiles.createProfile(BankConnectorRegistry.sber);
      const legacy = SberPinVault();
      await legacy.write('1234');
      final vault = SberPinVault(profileId: profile.id);
      await vault.migrateLegacy(profiles);
      expect(await vault.read(), '1234');
      expect(await legacy.read(), isNull);
      await profiles.deleteProfile(profile.id);
      final other = await profiles.createProfile(BankConnectorRegistry.sber);
      final otherVault = SberPinVault(profileId: other.id);
      await otherVault.migrateLegacy(profiles);
      expect(await otherVault.read(), isNull);
    },
  );
  test('ambiguous legacy PIN is never tried in either profile', () async {
    final a = await profiles.createProfile(BankConnectorRegistry.sber);
    final b = await profiles.createProfile(BankConnectorRegistry.sber);
    await const SberPinVault().write('1234');
    for (final p in [a, b]) {
      final vault = SberPinVault(profileId: p.id);
      await vault.migrateLegacy(profiles);
      expect(await vault.read(), isNull);
    }
  });
}
