import '../../../data/models/qesto_models.dart';
import '../../../synoball/core/models.dart';
import '../../budget/services/cash_flow_calculation_service.dart';
import '../../statistics/domain/models/statistics_models.dart';
import '../../../synoball/analytics/canonical_snapshot.dart';

enum AiExportVersion { v1, v2 }

enum AiExportDetailLevel { compact, diagnostic }

abstract interface class AiExportIdProvider {
  Future<String> id(String type, String canonicalId);
}

class AiExportSettings {
  const AiExportSettings({
    required this.period,
    this.hideTransactionNames = true,
    this.hideAccountNames = true,
    this.version = AiExportVersion.v2,
    this.detailLevel = AiExportDetailLevel.compact,
  });
  final StatisticsDateRange period;
  final bool hideTransactionNames;
  final bool hideAccountNames;
  final AiExportVersion version;
  final AiExportDetailLevel detailLevel;
  bool get privateCategories => hideTransactionNames || hideAccountNames;
}

/// Only the fields needed for export, captured synchronously on the UI isolate.
/// No payloads, evidence, credentials, receipt data or mutable controller lists.
class AiExportSnapshot {
  AiExportSnapshot({
    required this.profileScope,
    required this.capturedAt,
    required this.referenceDate,
    required Iterable<AiExportAccountSnapshot> accounts,
    required Iterable<AiExportTransactionSnapshot> transactions,
    required Map<String, String> categoryNames,
    required Map<String, String> standardCategoryNames,
    this.canonical,
    this.accountDetails = const {},
    Iterable<AiExportTransactionSnapshot>? v2Transactions,
  }) : accounts = List.unmodifiable(accounts),
       transactions = List.unmodifiable(transactions),
       categoryNames = Map.unmodifiable(categoryNames),
       standardCategoryNames = Map.unmodifiable(standardCategoryNames),
       v2Transactions = v2Transactions == null
           ? null
           : List.unmodifiable(v2Transactions);
  final String profileScope;
  final DateTime capturedAt;
  final DateTime referenceDate;
  final List<AiExportAccountSnapshot> accounts;
  final List<AiExportTransactionSnapshot> transactions;
  final Map<String, String> categoryNames;
  final Map<String, String> standardCategoryNames;
  final CanonicalSnapshot? canonical;
  final Map<String, AiExportAccountDetails> accountDetails;
  final List<AiExportTransactionSnapshot>? v2Transactions;
}

/// Optional, explicitly typed account extensions; never a storage object dump.
class AiExportAccountDetails {
  const AiExportAccountDetails({
    this.capturedAt,
    this.estimated = false,
    this.stale = false,
    this.outstandingPrincipal,
    this.nextPayment,
    this.nextPaymentDate,
    this.interestRate,
    this.portfolioValue,
    this.cashBalance,
    this.costBasis,
    this.mortgage = false,
  });
  final DateTime? capturedAt, nextPaymentDate;
  final bool estimated, stale, mortgage;
  final Money? outstandingPrincipal,
      nextPayment,
      portfolioValue,
      cashBalance,
      costBasis;
  final double? interestRate;
}

class AiExportAccountSnapshot {
  const AiExportAccountSnapshot({
    required this.id,
    required this.name,
    required this.type,
    required this.isVirtual,
    required this.balance,
  });
  final String id;
  final String name;
  final SynoballAccountType type;
  final bool isVirtual;
  final Money balance;
}

enum AiExportExclusion {
  deleted,
  cancelled,
  pending,
  nonMonetary,
  unconfirmed,
  unavailable,
  nonObserved,
}

class AiExportTransactionSnapshot {
  const AiExportTransactionSnapshot({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.occurredAt,
    required this.name,
    required this.amount,
    required this.type,
    required this.direction,
    required this.cashFlowTreatment,
    this.exclusion,
  });
  final String id;
  final String? accountId;
  final String? categoryId;
  final DateTime occurredAt;
  final String name;
  final Money amount;
  final TransactionType type;
  final FinancialDirection direction;
  final CashFlowTreatment cashFlowTreatment;
  final AiExportExclusion? exclusion;
}

/// This exact selection drives both preview and serialization.
class AiExportSelection {
  AiExportSelection(this.snapshot, this.settings) {
    if (settings.period.end.isBefore(settings.period.start)) {
      throw const FormatException('Начало периода позже его окончания');
    }
    final selected = <AiExportTransactionSnapshot>[];
    final omitted = <AiExportExclusion, int>{};
    for (final row
        in settings.version == AiExportVersion.v2
            ? snapshot.v2Transactions ?? snapshot.transactions
            : snapshot.transactions) {
      if (settings.version == AiExportVersion.v2 &&
          snapshot.canonical?.aliases[row.id] != null &&
          snapshot.canonical!.aliases[row.id] != row.id) {
        continue;
      }
      if (!settings.period.contains(row.occurredAt)) continue;
      if (row.exclusion case final reason?) {
        omitted.update(reason, (n) => n + 1, ifAbsent: () => 1);
      } else {
        selected.add(row);
      }
    }
    selected.sort((a, b) {
      final byDate = a.occurredAt.compareTo(b.occurredAt);
      return byDate == 0 ? a.id.compareTo(b.id) : byDate;
    });
    transactions = List.unmodifiable(selected);
    accounts = List.unmodifiable(
      [...snapshot.accounts]..sort((a, b) => a.id.compareTo(b.id)),
    );
    categoryIds = List.unmodifiable(
      selected
          .map((r) => r.categoryId)
          .whereType<String>()
          .where(
            (id) =>
                settings.version == AiExportVersion.v1 ||
                snapshot.categoryNames.containsKey(id),
          )
          .toSet()
          .toList()
        ..sort(),
    );
    excluded = Map.unmodifiable(omitted);
  }
  final AiExportSnapshot snapshot;
  final AiExportSettings settings;
  late final List<AiExportTransactionSnapshot> transactions;
  late final List<AiExportAccountSnapshot> accounts;
  late final List<String> categoryIds;
  late final Map<AiExportExclusion, int> excluded;

  AiExportSelection forVersion(AiExportVersion version) =>
      settings.version == version
      ? this
      : AiExportSelection(
          snapshot,
          AiExportSettings(
            period: settings.period,
            hideTransactionNames: settings.hideTransactionNames,
            hideAccountNames: settings.hideAccountNames,
            version: version,
            detailLevel: settings.detailLevel,
          ),
        );
}

String aiExportDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
