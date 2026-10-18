import 'package:test/test.dart';
import 'evidence_redirect.dart';
import '../../incremental_domain_execution/test/domain_owner_test.dart' as suite0;
import '../../incremental_domain_execution/test/bounded_executor_test.dart' as suite1;
import '../../incremental_domain_execution/test/streaming_digest_test.dart' as suite2;
void main() {
  redirectEvidence();
  group('domain_owner', suite0.main);
  group('bounded_executor', suite1.main);
  group('streaming_digest', suite2.main);
}
