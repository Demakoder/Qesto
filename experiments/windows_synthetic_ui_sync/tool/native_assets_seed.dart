// Invoke with `dart run` from the current native test package. This materializes
// the JIT native_assets.yaml used by test_core before adding the app mapping.
import 'package:qesto_storage_spike/storage_spike.dart';

void main() {
  final directory = createSpikeDirectory();
  final db = openNative(
    '${directory.path}/seed.db',
    Candidate.directMc,
    randomKey(),
  );
  try {
    db.select('SELECT 1');
    print('Synthetic encrypted native assets ready');
  } finally {
    db.close();
  }
}
