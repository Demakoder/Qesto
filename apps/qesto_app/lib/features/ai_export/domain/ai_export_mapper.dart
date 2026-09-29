import 'ai_export_document.dart';
import 'ai_export_models.dart';

class AiExportMapper {
  const AiExportMapper();
  Future<AiExportDocument> build(
    AiExportSelection selection,
    AiExportIdProvider ids, {
    DateTime? generatedAt,
  }) async {
    selection = selection.forVersion(AiExportVersion.v1);
    final accounts = <AiExportAccountDto>[];
    final accountIds = <String, String>{};
    final virtualIds = <String>{};
    for (final a in selection.accounts) {
      final id = await ids.id('account', a.id);
      accountIds[a.id] = id;
      if (a.isVirtual) virtualIds.add(a.id);
      accounts.add(
        AiExportAccountDto(
          id: id,
          name: selection.settings.hideAccountNames
              ? 'Счёт ${accounts.length + 1}'
              : a.name,
          type: a.type.name,
          isVirtual: a.isVirtual,
          balance: a.balance,
        ),
      );
    }
    final categories = <AiExportCategoryDto>[];
    final categoryIds = <String, String>{};
    for (final key in selection.categoryIds) {
      final id = await ids.id('category', key);
      categoryIds[key] = id;
      final names = selection.settings.privateCategories
          ? selection.snapshot.standardCategoryNames
          : selection.snapshot.categoryNames;
      categories.add(
        AiExportCategoryDto(
          id,
          names[key] ?? 'Категория ${categories.length + 1}',
        ),
      );
    }
    final transactions = <AiExportTransactionDto>[];
    for (final row in selection.transactions) {
      // Yield to painting/input for large histories, including web.
      if (transactions.length % 128 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final accountId = accountIds[row.accountId];
      transactions.add(
        AiExportTransactionDto(
          id: await ids.id('transaction', row.id),
          accountId: accountId,
          categoryId: categoryIds[row.categoryId],
          accountResolution: accountId == null
              ? 'unresolved'
              : virtualIds.contains(row.accountId)
              ? 'virtual'
              : 'resolved',
          occurredAt: row.occurredAt,
          name: selection.settings.hideTransactionNames
              ? 'Операция ${transactions.length + 1}'
              : row.name,
          amount: row.amount,
          type: row.type.name,
          direction: row.direction.name,
          cashFlowTreatment: row.cashFlowTreatment.name,
        ),
      );
    }
    return AiExportDocument(
      generatedAt: generatedAt ?? DateTime.now(),
      selection: selection,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
    );
  }
}

/// Compatibility builder: its public v1 contract is deliberately unchanged.
class AIExportV1Builder extends AiExportMapper {
  const AIExportV1Builder();
}
