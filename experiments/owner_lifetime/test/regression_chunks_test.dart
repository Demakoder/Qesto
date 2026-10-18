import 'package:test/test.dart';
import 'evidence_redirect.dart';
import '../../incremental_sync_performance/test/chunk_storage_test.dart' as suite0;
import '../../incremental_sync_performance/test/native_chunk_fault_test.dart' as suite1;
void main() {
  redirectEvidence();
  group('chunk_storage', suite0.main);
  group('native_chunk_fault', suite1.main);
}
