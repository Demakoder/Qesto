import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/persistence/android_store_location.dart';
import 'package:qesto/data/persistence/recoverable_json_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ru.qesto.qesto/storage');
  late Directory sandbox;
  late Directory files;
  late File legacy;
  late File destination;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'qesto-android-storage-test-',
    );
    files = await Directory('${sandbox.path}/files').create();
    legacy = File('${sandbox.path}/.local/share/Qesto/store.json');
    destination = File('${files.path}/Qesto/store.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'privatePaths');
          return {'filesDir': files.path, 'dataDir': sandbox.path};
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await sandbox.delete(recursive: true);
  });

  Future<File> resolve() => resolveAndroidStore(legacyRoot: sandbox.path);

  test('fresh installation uses private files directory', () async {
    final resolved = await resolve();
    expect(resolved.absolute.uri, destination.absolute.uri);
    expect(await RecoverableJsonFile(resolved).read(), isNull);
  });

  test(
    'migration preserves legacy encrypted values and original bytes',
    () async {
      await RecoverableJsonFile(
        legacy,
      ).write({'financial': 'opaque ciphertext'});
      final original = await legacy.readAsBytes();
      final resolved = await resolve();
      expect(await RecoverableJsonFile(resolved).read(), {
        'financial': 'opaque ciphertext',
      });
      expect(await legacy.readAsBytes(), original);
    },
  );

  test('legacy backup recovers without deleting malformed primary', () async {
    final source = RecoverableJsonFile(legacy);
    await source.write({'generation': 1});
    await source.write({'generation': 2});
    await legacy.writeAsString('{broken');
    expect(await RecoverableJsonFile(await resolve()).read(), {
      'generation': 1,
    });
    expect(await legacy.readAsString(), '{broken');
  });

  test('corrupt legacy snapshot fails closed and is not overwritten', () async {
    await legacy.parent.create(recursive: true);
    await legacy.writeAsString('{broken');
    await expectLater(resolve(), throwsFormatException);
    expect(await destination.exists(), isFalse);
    expect(await legacy.readAsString(), '{broken');
  });

  test('wiped destination never resurrects old data', () async {
    await RecoverableJsonFile(legacy).write({'financial': 'old data'});
    await RecoverableJsonFile(destination).write({});
    expect(await RecoverableJsonFile(await resolve()).read(), isEmpty);
  });

  test('corrupt destination does not silently fall back to legacy', () async {
    await RecoverableJsonFile(legacy).write({'financial': 'old data'});
    await destination.parent.create(recursive: true);
    await destination.writeAsString('{broken');
    await expectLater(resolve(), throwsFormatException);
    expect(await destination.readAsString(), '{broken');
  });

  test(
    'concurrent migration preserves subsequently committed values',
    () async {
      await RecoverableJsonFile(legacy).write({'generation': 1});
      await Future.wait(List.generate(4, (_) => resolve()));
      await RecoverableJsonFile(destination).write({'generation': 2});
      expect(await RecoverableJsonFile(await resolve()).read(), {
        'generation': 2,
      });
    },
  );

  test('unavailable native path is an error, never cwd fallback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(resolve(), throwsStateError);
  });

  test('native files directory must belong to the app sandbox', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'filesDir': sandbox.parent.path,
            'dataDir': sandbox.path,
          },
        );
    await expectLater(resolve(), throwsStateError);
  });
}
