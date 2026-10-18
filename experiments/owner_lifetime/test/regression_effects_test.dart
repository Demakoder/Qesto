import 'package:test/test.dart';
import 'evidence_redirect.dart';
import '../../durable_effects_integration/test/coverage_test.dart' as suite0;
import '../../durable_effects_integration/test/receipt_test.dart' as suite1;
import '../../durable_effects_integration/test/owner_test.dart' as suite2;
import '../../durable_effects_integration/test/process_test.dart' as suite3;
import '../../durable_effects_integration/test/native_test.dart' as suite4;
import '../../durable_effects_integration/test/lifecycle_test.dart' as suite5;
void main() {
  redirectEvidence();
  group('coverage', suite0.main);
  group('receipt', suite1.main);
  group('owner', suite2.main);
  group('process', suite3.main);
  group('native', suite4.main);
  group('lifecycle', suite5.main);
}
