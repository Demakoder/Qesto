import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/persistence/recoverable_json_file.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/repositories/local_qesto_repository.dart';
import 'package:qesto/data/models/qesto_models.dart';

void main() {
  test(
    'malformed or future financial data cannot turn into an empty autosave',
    () async {
      for (final source in ['{broken', '{"schemaVersion":999}']) {
        final memory = MemoryKeyValueStore({
          'qesto.user-financial-data.v1': source,
        });
        final repo = LocalQestoRepository(store: memory);
        await expectLater(
          repo.getUserFinancialData(),
          throwsA(isA<FormatException>()),
        );
        await expectLater(
          repo.saveUserFinancialData(
            UserFinancialData(
              user: const QestoUser(
                id: 'test',
                name: 'Test',
                defaultCurrency: 'RUB',
              ),
              referenceDate: DateTime(2026, 9, 6),
            ),
          ),
          throwsStateError,
        );
        expect(await memory.readString('qesto.user-financial-data.v1'), source);
      }
    },
  );
  for (final step in [
    'staged',
    'backup_staged',
    'backup_committed',
    'committed',
  ]) {
    test(
      'snapshot recovers after $step, including a second failure during recovery',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'qesto-synthetic-recovery-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/store.json');
        final store = RecoverableJsonFile(file);
        await store.write({'generation': 1});
        await store.write({'generation': 2});
        await file.writeAsString('{broken');
        expect((await store.read())!['generation'], 1);
        final failing = RecoverableJsonFile(
          file,
          checkpoint: (value) async {
            if (value == step) throw StateError('Synthetic interruption');
          },
        );
        await expectLater(failing.write({'generation': 3}), throwsStateError);
        expect(
          (await store.read())!['generation'],
          step == 'committed' ? 3 : 1,
        );
        await expectLater(failing.write({'generation': 4}), throwsStateError);
        expect(
          (await store.read())!['generation'],
          step == 'committed' ? 4 : 1,
        );
        await store.write({'generation': 5});
        expect((await store.read())!['generation'], 5);
      },
    );
  }
  test(
    'parallel updates preserve fields and removal cannot recover deleted content',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qesto-synthetic-update-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/store.json');
      final store = RecoverableJsonFile(file);
      await Future.wait([
        store.update((value) => {...?value, 'a': 1}),
        RecoverableJsonFile(file).update((value) => {...?value, 'b': 2}),
      ]);
      expect(await store.read(), {'a': 1, 'b': 2});
      await store.update(
        (value) => {...?value}..remove('a'),
        retainPrevious: false,
      );
      await file.writeAsString('');
      expect(await store.read(), {'b': 2});
    },
  );
}
