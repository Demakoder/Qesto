import 'package:test/test.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/wal_policy.dart';

void main() {
  test('checkpoint result distinguishes BUSY and uncheckpointed frames', () {
    expect(const CheckpointResult(1, 100, 20).pending, 80);
    expect(const CheckpointResult(0, -1, -1).pending, 0);
  });
  test('oversized snapshot is rejected before mutation', () async {
    final dir = createSpikeDirectory(), key = randomKey();
    final store = await SpikeStore.open(
      '${dir.path}/bound.db',
      Candidate.directMc,
      key,
    );
    try {
      final policy = WalPolicy(
        store,
        hardBytes: mib,
        available: () => 1024 * mib,
      );
      await expectLater(
        policy.apply('large', 0, syntheticSnapshot(10)),
        throwsA(isA<StoragePressure>()),
      );
      expect(await store.revision(), 0);
      await store.verify();
    } finally {
      await store.close();
    }
  });
  test('key rotation refuses active reader without changing key', () async {
    final dir = createSpikeDirectory(),
        key = randomKey(),
        path = '${dir.path}/rotation.db';
    final store = await SpikeStore.open(path, Candidate.directMc, key);
    try {
      await store.apply(
        id: 'seed',
        expected: 0,
        snapshot: syntheticSnapshot(10),
      );
      final reader = openNative(path, Candidate.directMc, key);
      try {
        reader.execute('BEGIN');
        reader.select('SELECT revision FROM state');
        await store.apply(
          id: 'new',
          expected: 1,
          snapshot: syntheticSnapshot(11),
        );
        store.raw.execute('PRAGMA busy_timeout=10');
        await expectLater(store.rotateKey(randomKey()), throwsStateError);
        expect(store.key, key);
        reader.execute('ROLLBACK');
      } finally {
        reader.close();
      }
      await store.verify();
    } finally {
      await store.close();
    }
  });
}
