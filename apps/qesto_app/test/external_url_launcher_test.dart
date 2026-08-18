import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/platform/external_url_launcher.dart';

void main() {
  test('external URL policy accepts ordinary public web addresses', () {
    expect(isSafeExternalWebUrl('https://example.com/deal?id=1'), isTrue);
    expect(isSafeExternalWebUrl('http://8.8.8.8/'), isTrue);
  });

  test('external URL policy blocks credentials and non-web schemes', () {
    expect(isSafeExternalWebUrl('https://user:secret@example.com'), isFalse);
    expect(isSafeExternalWebUrl('javascript:alert(1)'), isFalse);
    expect(isSafeExternalWebUrl('file:///etc/passwd'), isFalse);
  });

  test('external URL policy blocks local and private network targets', () {
    for (final value in [
      'http://localhost:8080',
      'http://127.0.0.1',
      'http://0177.0.0.1',
      'http://0x7f.0.0.1',
      'http://2130706433',
      'http://10.0.0.1',
      'http://172.16.0.1',
      'http://192.168.1.1',
      'http://[::1]',
      'http://[fec0::1]',
      'http://[::ffff:127.0.0.1]',
      'http://service.internal',
    ]) {
      expect(isSafeExternalWebUrl(value), isFalse, reason: value);
    }
  });
}
