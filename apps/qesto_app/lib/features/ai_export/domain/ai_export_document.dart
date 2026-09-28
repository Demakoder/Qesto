import '../../../synoball/core/models.dart';
import 'ai_export_models.dart';

/// Explicit allowlist DTOs. Never serialize a financial storage object here.
class AiExportAccountDto {
  const AiExportAccountDto({
    required this.id,
    required this.name,
    required this.type,
    required this.isVirtual,
    required this.balance,
  });
  final String id, name, type;
  final bool isVirtual;
  final Money balance;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'isVirtual': isVirtual,
    'latestStoredBalance': {
      'value': balance.value,
      'currency': balance.currency,
    },
  };
}

class AiExportCategoryDto {
  const AiExportCategoryDto(this.id, this.name);
  final String id, name;
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

class AiExportTransactionDto {
  const AiExportTransactionDto({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.accountResolution,
    required this.occurredAt,
    required this.name,
    required this.amount,
    required this.type,
    required this.direction,
    required this.cashFlowTreatment,
  });
  final String id, name, type, direction, cashFlowTreatment, accountResolution;
  final String? accountId, categoryId;
  final DateTime occurredAt;
  final Money amount;
  Map<String, Object?> toJson() => {
    'id': id,
    'accountId': accountId,
    'categoryId': categoryId,
    'accountResolution': accountResolution,
    'occurredAt': occurredAt.toIso8601String(),
    'name': name,
    'amount': {'value': amount.value, 'currency': amount.currency},
    'status': 'posted',
    'type': type,
    'direction': direction,
    'cashFlowTreatment': cashFlowTreatment,
  };
}

class AiExportDocument {
  AiExportDocument({
    required this.generatedAt,
    required this.selection,
    required Iterable<AiExportAccountDto> accounts,
    required Iterable<AiExportCategoryDto> categories,
    required Iterable<AiExportTransactionDto> transactions,
  }) : accounts = List.unmodifiable(accounts),
       categories = List.unmodifiable(categories),
       transactions = List.unmodifiable(transactions);
  static const schemaVersion = 'qesto.ai-export.v1';
  final DateTime generatedAt;
  final AiExportSelection selection;
  final List<AiExportAccountDto> accounts;
  final List<AiExportCategoryDto> categories;
  final List<AiExportTransactionDto> transactions;
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'period': {
      'startDate': aiExportDate(selection.settings.period.start),
      'endDateInclusive': aiExportDate(selection.settings.period.end),
      'dateBasis': 'stored_calendar_date',
    },
    'privacy': {
      'transactionNamesHidden': selection.settings.hideTransactionNames,
      'accountNamesHidden': selection.settings.hideAccountNames,
      'categoryNamesProtected': selection.settings.privateCategories,
      'idScope': 'persistent_pseudonymous',
    },
    'selection': {
      'transactionPolicy': 'posted_monetary',
      'balances': 'latest_stored',
      'historyCompleteness': 'not_verified',
      'snapshotCapturedAt': selection.snapshot.capturedAt
          .toUtc()
          .toIso8601String(),
      'excluded': {
        for (final entry in selection.excluded.entries)
          entry.key.name: entry.value,
      },
    },
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'categories': categories.map((c) => c.toJson()).toList(),
    'transactions': transactions.map((t) => t.toJson()).toList(),
  };
}
