import 'bank_statement_file_models.dart';
import 'bank_statement_file_service_stub.dart'
    if (dart.library.io) 'bank_statement_file_service_native.dart'
    if (dart.library.js_interop) 'bank_statement_file_service_web.dart'
    as platform;

export 'bank_statement_file_models.dart';

class BankStatementFileService {
  const BankStatementFileService();

  Future<ExtractedStatementFile?> pickStatement({
    StatementPickerMode mode = StatementPickerMode.all,
  }) => platform.pickStatementFile(mode);

  Future<ExtractedStatementFile?> pickPdf() =>
      pickStatement(mode: StatementPickerMode.statement);
}
