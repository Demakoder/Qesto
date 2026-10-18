import 'package:test/test.dart';
import 'evidence_redirect.dart';
import '../../storage_feasibility/test/container_contract_test.dart' as suite0;
import '../../storage_feasibility/test/container_process_test.dart' as suite1;
import '../../storage_feasibility/test/contract_test.dart' as suite2;
import '../../storage_feasibility/test/hardening_policy_test.dart' as suite3;
void main() {
  redirectEvidence();
  group('container_contract', suite0.main);
  group('container_process', suite1.main);
  group('contract', suite2.main);
  group('hardening_policy', suite3.main);
}
