import '../../adapters/transaction_inputs.dart';
import '../../core/models.dart';
import '../api/cbr_2025_12_v2/accounts.dart';
import '../core/errors.dart';
import '../core/types.dart';

class CbrMappingContext {
  const CbrMappingContext({required this.entityId, required this.provenance});

  final String entityId;
  final DataProvenance provenance;
}

abstract interface class CbrAccountMapper {
  SynoballAccount mapAccount(CbrRawAccount raw, CbrMappingContext context);
}

abstract interface class CbrEntryMapper {
  TransactionSeed mapEntry(CbrRawEntry raw, CbrMappingContext context);
}

class DisabledCbrAccountMapper implements CbrAccountMapper {
  const DisabledCbrAccountMapper();

  @override
  SynoballAccount mapAccount(CbrRawAccount raw, CbrMappingContext context) =>
      throw const OpenBankingNotImplementedError(
        'CBR generated raw account schema mapper',
      );
}

class DisabledCbrEntryMapper implements CbrEntryMapper {
  const DisabledCbrEntryMapper();

  @override
  TransactionSeed mapEntry(CbrRawEntry raw, CbrMappingContext context) =>
      throw const OpenBankingNotImplementedError(
        'CBR generated raw statement entry mapper',
      );
}
