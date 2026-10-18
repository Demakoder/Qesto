import 'dart:convert';
import 'dart:math';
import 'package:test/test.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import '../lib/streaming_digest.dart';

void main() {
  test(
    'v1 exact bytes parity including unicode escaping, numbers and nested maps',
    () {
      final random = Random(4);
      for (var i = 0; i < 200; i++) {
        final value = {
          'z': i.isEven ? null : -0.0,
          'a': [
            '₽ • 你好 😀\n\t\u0000',
            random.nextDouble(),
            random.nextInt(1 << 32),
            {'b': true, 'a': false},
          ],
          'empty': <String, Object?>{},
        };
        expect(streamingDigest(value), w.digest(value));
      }
      expect(
        streamingDigest(jsonDecode(encodeSynthetic(count: 1000))),
        w.digest(jsonDecode(encodeSynthetic(count: 1000))),
      );
      expect(() => streamingDigest(double.nan), throwsA(anything));
      expect(() => streamingDigest(DateTime.now()), throwsArgumentError);
    },
  );
}
