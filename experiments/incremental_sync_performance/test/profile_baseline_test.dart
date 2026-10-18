import 'package:test/test.dart';
import '../bin/profile_baseline.dart' as profile;

void main() {
  test(
    'profile baseline native Windows',
    () => profile.main([]),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
