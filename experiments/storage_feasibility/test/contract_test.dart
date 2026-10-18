import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:test/test.dart';

void contractTests(List<Candidate> candidates) {
  for (final candidate in candidates) {
    for (final journal in ['WAL', 'DELETE']) {
      group('${candidate.name}/$journal', () {
        late Directory dir;
        late List<int> key;
        late String path;
        late SpikeStore store;
        setUp(() async {
          dir = createSpikeDirectory();
          key = randomKey();
          path = '${dir.path}/contract.db';
          store = await SpikeStore.open(path, candidate, key, journal: journal);
        });
        tearDown(() async {
          await store.close();
          requireOwnedPath(path);
          dir.deleteSync(recursive: true);
        });

        test(
          'commit persists snapshot + immutable outbox + revision + metadata',
          () async {
            final input = syntheticSnapshot(3);
            expect(
              await store.apply(id: 'one', expected: 0, snapshot: input),
              1,
            );
            await store.verify();
            expect(await store.snapshot(), input);
            final decoded = SynoballState.fromJson(
              jsonDecode(input) as Map<String, dynamic>,
            );
            expect(decoded.transactions[0].amount.minorUnits, 1);
            expect(decoded.transactions[0].amount.currency, 'USD');
            expect(decoded.transactions[1].amount.currency, 'RUB');
            expect(
              decoded.transactions[1].direction,
              FinancialDirection.outflow,
            );
            expect(
              await store.engine.select('SELECT kind FROM sync_meta'),
              hasLength(3),
            );
            await expectLater(
              store.engine.execute(
                "UPDATE outbox SET revision=2 WHERE id='one'",
              ),
              throwsA(anything),
            );
            await expectLater(
              store.engine.execute("DELETE FROM outbox WHERE id='one'"),
              throwsA(anything),
            );
          },
        );

        test('idempotent retry and immutable id collision', () async {
          final input = syntheticSnapshot(2);
          await store.apply(id: 'same', expected: 0, snapshot: input);
          expect(
            await store.apply(id: 'same', expected: 0, snapshot: input),
            1,
          );
          await expectLater(
            store.apply(
              id: 'same',
              expected: 0,
              snapshot: syntheticSnapshot(4),
            ),
            throwsA(isA<CommandCollision>()),
          );
          await store.verify();
          expect(await store.revision(), 1);
        });

        test(
          'existing app codec v7 snapshot survives opaque encrypted storage',
          () async {
            var fixture = File('test/fixtures/financial_snapshot_v7.json');
            if (!fixture.existsSync())
              fixture = File('../test/fixtures/financial_snapshot_v7.json');
            final value = fixture.readAsStringSync();
            expect(jsonDecode(value)['schemaVersion'], 7);
            await store.apply(id: 'codec7', expected: 0, snapshot: value);
            await store.close();
            store = await SpikeStore.open(
              path,
              candidate,
              key,
              journal: journal,
            );
            await store.verify();
            expect(await store.snapshot(), value);
            final restored = SynoballState.fromJson(
              jsonDecode((await store.snapshot())!)['synoball']
                  as Map<String, dynamic>,
            );
            expect(restored.transactions[0].id, 'spike-v7-0');
            expect(restored.transactions[0].amount.minorUnits, 486122);
            expect(restored.transactions[1].amount.currency, 'USD');
            expect(restored.transactions[0].userCategoryOverride, 'sport');
            expect(
              restored.transactions[2].status,
              CanonicalTransactionStatus.deleted,
            );
            expect(restored.transactions[0].tags, contains('user-field:note'));
          },
        );

        for (final fault in [
          Fault.beforeTransaction,
          Fault.afterSnapshot,
          Fault.afterOutbox,
        ]) {
          test('full rollback at ${fault.name}', () async {
            await expectLater(
              store.apply(
                id: 'fail',
                expected: 0,
                snapshot: syntheticSnapshot(2),
                fault: (stage) {
                  if (stage == fault) throw StateError('injected');
                },
              ),
              throwsStateError,
            );
            await store.verify();
            expect(await store.revision(), 0);
            expect(await store.snapshot(), isNull);
            expect(
              await store.engine.select('SELECT * FROM sync_meta'),
              isEmpty,
            );
          });
        }

        test('lost ACK is recovered from durable state', () async {
          final value = syntheticSnapshot(2);
          await expectLater(
            store.apply(
              id: 'ack',
              expected: 0,
              snapshot: value,
              fault: (stage) {
                if (stage == Fault.afterCommit) throw StateError('lost ack');
              },
            ),
            throwsStateError,
          );
          await store.verify();
          expect(await store.revision(), 1);
          expect(await store.apply(id: 'ack', expected: 0, snapshot: value), 1);
        });

        test(
          'stale second connection cannot overwrite accepted data',
          () async {
            final second = await SpikeStore.open(
              path,
              candidate,
              key,
              journal: journal,
            );
            try {
              expect(await second.revision(), 0);
              await store.apply(
                id: 'first',
                expected: 0,
                snapshot: syntheticSnapshot(2),
              );
              expect(await second.revision(), 1);
              await expectLater(
                second.apply(
                  id: 'stale',
                  expected: 0,
                  snapshot: syntheticSnapshot(3),
                ),
                throwsA(isA<StaleRevision>()),
              );
              await second.verify();
              expect(await store.revision(), 1);
            } finally {
              await second.close();
            }
          },
        );

        test(
          'wrong/missing key fails closed without replacing snapshot',
          () async {
            await store.apply(
              id: 'first',
              expected: 0,
              snapshot: syntheticSnapshot(2),
            );
            await expectLater(
              SpikeStore.open(path, candidate, null),
              throwsStateError,
            );
            await expectLater(
              SpikeStore.open(path, candidate, randomKey()),
              throwsA(anything),
            );
            await store.verify();
            expect(await store.revision(), 1);
          },
        );

        test('DB/WAL/journal/backup contain no synthetic secret', () async {
          await store.apply(
            id: 'first',
            expected: 0,
            snapshot: syntheticSnapshot(40),
          );
          final backup = '${dir.path}/backup.db';
          await store.backup(backup);
          for (final file in dir.listSync().whereType<File>()) {
            final bytes = file.readAsBytesSync();
            expect(
              latin1.decode(bytes).contains(marker),
              isFalse,
              reason: file.path,
            );
            if (candidate != Candidate.payloadGcm &&
                file.path.endsWith('.db')) {
              expect(
                latin1.decode(bytes.take(16).toList()),
                isNot('SQLite format 3\u0000'),
              );
            }
          }
          final restored = await SpikeStore.open(backup, candidate, key);
          try {
            await restored.verify();
            expect(await restored.snapshot(), await store.snapshot());
          } finally {
            await restored.close();
          }
          await expectLater(
            SpikeStore.open(backup, candidate, null),
            throwsStateError,
          );
        });

        test(
          'active WAL / rollback journal contains no sensitive plaintext',
          () async {
            await store.apply(
              id: 'seed',
              expected: 0,
              snapshot: syntheticSnapshot(3),
            );
            var inspected = false;
            await expectLater(
              store.apply(
                id: 'active',
                expected: 1,
                snapshot: syntheticSnapshot(5000),
                fault: (stage) {
                  if (stage != Fault.afterOutbox) return;
                  for (final file in dir.listSync().whereType<File>()) {
                    // Windows locks SHM byte ranges during a write transaction.
                    // Unlocked SHM is scanned in the separate committed-state test.
                    if (file.path.endsWith('.db-shm')) continue;
                    expect(
                      latin1.decode(file.readAsBytesSync()).contains(marker),
                      isFalse,
                    );
                    if (file.path.endsWith(
                      journal == 'DELETE' ? '.db-journal' : '.db-wal',
                    ))
                      inspected = true;
                  }
                  throw StateError(
                    'roll back after active auxiliary-file scan',
                  );
                },
              ),
              throwsStateError,
            );
            expect(
              inspected,
              isTrue,
              reason: 'Must actually observe an auxiliary file',
            );
            await store.verify();
            expect(await store.revision(), 1);
          },
        );

        test(
          'empty/corrupt existing database does not silently initialize',
          () async {
            final bad = '${dir.path}/incomplete.db';
            File(bad).writeAsBytesSync([]);
            await expectLater(
              SpikeStore.open(bad, candidate, key),
              throwsA(anything),
            );
          },
        );

        test('checkpoint + reopen retain complete accepted state', () async {
          await store.apply(
            id: 'one',
            expected: 0,
            snapshot: syntheticSnapshot(5),
          );
          await store.checkpoint();
          await store.close();
          store = await SpikeStore.open(path, candidate, key, journal: journal);
          await store.verify();
          expect(await store.revision(), 1);
        });

        if (candidate == Candidate.payloadGcm) {
          test(
            'GCM rejects altered payload and row substitution via AAD',
            () async {
              final encoded = await store.encode('row-A', marker);
              final tampered = Uint8List.fromList(encoded)..[16] ^= 1;
              await expectLater(
                store.decode('row-A', tampered),
                throwsA(anything),
              );
              await expectLater(
                store.decode('row-B', encoded),
                throwsA(anything),
              );
            },
          );
        }
      });
    }
  }
  test('WAL patched version gate rejects vulnerable versions', () {
    expect(walResetFixed(3051002), isFalse);
    expect(walResetFixed(3051003), isTrue);
    expect(walResetFixed(3050007), isTrue);
    expect(walResetFixed(3044006), isTrue);
  });
  test('guard prevents accidental production database access', () {
    expect(
      () => openNative('store.json', candidates.first, randomKey()),
      throwsStateError,
    );
  });
  test('no silent fallback to the wrong native build', () {
    final dir = createSpikeDirectory();
    final path = '${dir.path}/wrong-build.db';
    final wrong = candidates.first == Candidate.payloadGcm
        ? Candidate.directMc
        : Candidate.payloadGcm;
    expect(() => openNative(path, wrong, randomKey()), throwsStateError);
    requireOwnedPath(path);
    dir.deleteSync(recursive: true);
  });
}

void main() => contractTests([Candidate.driftMc, Candidate.directMc]);
