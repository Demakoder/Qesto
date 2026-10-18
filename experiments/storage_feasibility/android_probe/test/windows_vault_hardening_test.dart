// Tests the exact pinned transitive Windows plugin, without changing its source.
// No Android runtime, method-channel platform vault or real support path is used.
// ignore_for_file: depend_on_referenced_packages, implementation_imports
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_windows/src/flutter_secure_storage_windows_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/windows_key_probe.dart';

class SyntheticSupportPath extends PathProviderPlatform {
  SyntheticSupportPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = PathProviderPlatform.instance;
  late Directory directory;
  setUp(() {
    directory = createSpikeDirectory();
    PathProviderPlatform.instance = SyntheticSupportPath(directory.path);
  });
  tearDown(() {
    PathProviderPlatform.instance = original;
  });
  test(
    'native Windows plugin DPAPI save/reopen in isolated support directory',
    () async {
      final plugin = DpapiJsonFileMapStorage();
      await plugin.save({'synthetic-key': base64Encode(randomKey())}, {});
      final loaded = await DpapiJsonFileMapStorage().load({});
      expect(loaded.keys, contains('synthetic-key'));
    },
    skip: !Platform.isWindows,
  );
  for (final damage in ['cipher-corrupt', 'truncated', 'invalid-json']) {
    test(
      'existing plugin deletes isolated vault on $damage (risk reproduced)',
      () async {
        final plugin = DpapiJsonFileMapStorage();
        await plugin.save({'synthetic-key': base64Encode(randomKey())}, {});
        final file = File('${directory.path}/$encryptedJsonFileName');
        requireOwnedPath(file.path);
        final bytes = file.readAsBytesSync();
        if (damage == 'cipher-corrupt') {
          bytes[bytes.length ~/ 2] ^= 0x45;
          file.writeAsBytesSync(bytes);
        }
        if (damage == 'truncated') {
          file.writeAsBytesSync(bytes.take(19).toList());
        }
        if (damage == 'invalid-json') {
          file.writeAsBytesSync(WindowsKeyProbe.protect(utf8.encode('{bad')));
        }
        await expectLater(plugin.load({}), throwsA(anything));
        expect(
          file.existsSync(),
          isFalse,
          reason:
              'Observed destructive upstream behavior, NOT desired recovery semantics',
        );
      },
      skip: !Platform.isWindows,
    );
  }
  test(
    'existing plugin missing vault returns empty map (requires external database guard)',
    () async {
      expect(await DpapiJsonFileMapStorage().load({}), isEmpty);
    },
    skip: !Platform.isWindows,
  );
}
