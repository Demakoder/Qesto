part of 'budget_controller.dart';

/// Commands over the existing canonical ledger, not another assignment store.
extension BudgetClassification on BudgetController {
  void _validateClassificationName(String name, Iterable<String> existing) {
    final cleaned = name.trim();
    if (cleaned.isEmpty || cleaned.length > 60) {
      throw ArgumentError('Введите название от 1 до 60 символов');
    }
    if (existing.any((s) => s.toLowerCase() == cleaned.toLowerCase())) {
      throw ArgumentError('Такое название уже есть');
    }
  }

  void _rebuildClassification() {
    categories
      ..clear()
      ..addAll(
        BudgetController._resolvedCategories(
          [
            ..._baseCategories,
            ..._classification.customCategories,
          ].where((c) => !_classification.redirects.containsKey(c.id)).toList(),
          _categoryCustomizations,
        ),
      );
    _synoball.setCategoryPolicy(_classification.policy);
    _syncFromSynoball();
  }

  bool isSystemCategory(String id) => _baseCategories.any((c) => c.id == id);
  List<BudgetCategory> get hiddenSystemCategories => _baseCategories
      .where((c) => _classification.redirects.containsKey(c.id))
      .toList();

  Future<BudgetCategory> createCategory({
    required String name,
    required String iconKey,
    required int colorValue,
  }) async {
    _checkWrite();
    _validateClassificationName(name, categories.map((c) => c.name));
    final category = BudgetCategory(
      id: _classificationIds.next('user-category'),
      name: name.trim(),
      iconKey: iconKey,
      colorValue: colorValue,
    );
    _classification = _classification.copyWith(
      customCategories: [..._classification.customCategories, category],
    );
    _rebuildClassification();
    await _changed();
    return category;
  }

  Future<void> restoreSystemCategory(String id) async {
    _checkWrite();
    if (!isSystemCategory(id)) throw ArgumentError('Не системная категория');
    _classification = _classification.copyWith(
      redirects: {..._classification.redirects}..remove(id),
    );
    _categoryCustomizations.removeWhere((c) => c.categoryId == id);
    _rebuildClassification();
    await _changed();
  }

  List<CanonicalTransaction> similarTransactions(String id) {
    final t = _synoball.transactionById(id);
    if (t == null) return [];
    const enrichment = EnrichmentEngine();
    final identity = enrichment.merchantIdentity(t);
    if (identity == null) return [t];
    return _synoball.state.transactions
        .where(
          (item) =>
              item.status != CanonicalTransactionStatus.deleted &&
              item.entityId == t.entityId &&
              item.direction == t.direction &&
              enrichment.merchantIdentity(item) == identity,
        )
        .toList();
  }

  bool canCreateMerchantRule(String id) {
    final t = _synoball.transactionById(id);
    return t != null && const EnrichmentEngine().merchantIdentity(t) != null;
  }

  MerchantCategoryRule? ruleForTransaction(String id) {
    final t = _synoball.transactionById(id);
    return t == null
        ? null
        : _classification.policy.ruleFor(
            t,
            const EnrichmentEngine().merchantIdentity(t),
          );
  }

  Future<int> changeTransactionCategory(
    String transactionId,
    String categoryId, {
    CategoryChangeScope scope = CategoryChangeScope.transaction,
  }) async {
    _checkWrite();
    final category = categoryById(categoryId);
    final transaction = _synoball.transactionById(transactionId);
    if (transaction == null ||
        transaction.status == CanonicalTransactionStatus.deleted) {
      throw StateError('Операция недоступна');
    }
    final identity = const EnrichmentEngine().merchantIdentity(transaction);
    if (scope != CategoryChangeScope.transaction && identity == null) {
      throw StateError('Для массового изменения нужен определённый продавец');
    }
    final matching = scope == CategoryChangeScope.transaction
        ? [transaction]
        : similarTransactions(transactionId);
    for (final t in matching) {
      _synoball.updateTransaction(
        t.copyWith(
          userCategoryOverride: category.id,
          clearSubcategoryId: t.effectiveCategory != category.id,
          tags: {
            ...t.tags,
            'user-field:category',
            qestoManualCategoryTag,
          }.where((s) => s != qestoAutoCategoryTag).toList(),
        ),
        actorId: _userId,
        purpose: 'User category change: ${scope.name}',
      );
    }
    if (scope == CategoryChangeScope.always) {
      final previous = ruleForTransaction(transactionId);
      final rule = MerchantCategoryRule(
        id: previous?.id ?? _classificationIds.next('category-rule'),
        entityId: transaction.entityId,
        merchantKey: identity!,
        merchantLabel: transaction.merchantName!,
        categoryId: category.id,
        direction: transaction.direction,
      );
      _classification = _classification.copyWith(
        rules: [
          ..._classification.rules.where((r) => r.id != previous?.id),
          rule,
        ],
      );
      _synoball.setCategoryPolicy(_classification.policy);
    }
    _syncFromSynoball();
    await _changed();
    return matching.length;
  }

  Future<void> updateCategoryRule(String id, {String? categoryId}) async {
    _checkWrite();
    if (categoryId != null) categoryById(categoryId);
    _classification = _classification.copyWith(
      rules: [
        for (final r in _classification.rules)
          if (r.id != id)
            r
          else if (categoryId != null)
            r.withCategory(categoryId),
      ],
    );
    _rebuildClassification();
    await _changed();
  }

  int categoryReferenceCount(String id) =>
      _synoball.state.transactions
          .where((t) => t.effectiveCategory == id)
          .length +
      categoryBudgets.where((b) => b.categoryId == id).length +
      _upcomingExpenses.where((e) => e.categoryId == id).length +
      _classification.rules.where((r) => r.categoryId == id).length;

  Future<void> deleteCategory(String id, {String? replacementId}) async {
    _checkWrite();
    categoryById(id);
    if (isSystemCategory(id)) {
      throw StateError('Системную категорию можно объединить или сбросить');
    }
    if (replacementId == null && categoryReferenceCount(id) > 0) {
      throw StateError('Выберите категорию для переноса связанных данных');
    }
    // Keep a redirect even for an empty category: old import evidence and undo
    // snapshots can still refer to its ID later.
    final target =
        replacementId ??
        categories
            .where((c) => c.id != id && c.id == 'other')
            .firstOrNull
            ?.id ??
        categories.firstWhere((c) => c.id != id).id;
    await mergeCategories(id, target);
  }

  Future<void> mergeCategories(String sourceId, String targetId) async {
    _checkWrite();
    categoryById(sourceId);
    final target = categoryById(targetId).id;
    if (sourceId == target || _classification.redirects.containsKey(sourceId)) {
      throw ArgumentError('Выберите другую действующую категорию');
    }
    // The older Sber read-model can still repair an automatic category for
    // legacy records. Merge what the user actually sees as well as canonical
    // category references, so exports and later restores agree with the UI.
    for (final visible in _transactions.where(
      (t) => t.categoryId == sourceId,
    )) {
      final canonical = _synoball.transactionById(visible.id);
      if (canonical != null && canonical.effectiveCategory != sourceId) {
        _synoball.updateTransaction(
          canonical.copyWith(
            userCategoryOverride: target,
            clearSubcategoryId: true,
            tags: {
              ...canonical.tags,
              'user-field:category',
              qestoManualCategoryTag,
            }.toList(),
          ),
          actorId: _userId,
          purpose: 'User merged a legacy display category',
        );
      }
    }
    final moved = categoryBudgets
        .where((b) => b.categoryId == sourceId || b.categoryId == target)
        .toList();
    final combined = <String, int>{};
    for (final b in moved) {
      combined.update(
        b.budgetPeriodId,
        (v) => v + b.plannedAmount,
        ifAbsent: () => b.plannedAmount,
      );
    }
    categoryBudgets.removeWhere(
      (b) => b.categoryId == sourceId || b.categoryId == target,
    );
    categoryBudgets.addAll([
      for (final e in combined.entries)
        CategoryBudget(
          id: 'category-budget-${e.key}-$target',
          budgetPeriodId: e.key,
          categoryId: target,
          plannedAmount: e.value,
        ),
    ]);
    for (var i = 0; i < _upcomingExpenses.length; i++) {
      if (_upcomingExpenses[i].categoryId == sourceId) {
        _upcomingExpenses[i] = _upcomingExpenses[i].copyWith(
          categoryId: target,
        );
      }
    }
    _classification = _classification.copyWith(
      customCategories: _classification.customCategories
          .where((c) => c.id != sourceId)
          .toList(),
      rules: [
        for (final r in _classification.rules)
          r.categoryId == sourceId ? r.withCategory(target) : r,
      ],
      redirects: {..._classification.redirects, sourceId: target},
    );
    _categoryCustomizations.removeWhere((c) => c.categoryId == sourceId);
    _rebuildClassification();
    await _changed();
  }

  List<UserTransactionTag> tagsForTransaction(BudgetTransaction t) =>
      _classification.tags
          .where((tag) => t.tags.contains('$userLabelPrefix${tag.id}'))
          .toList();

  Future<UserTransactionTag> saveUserTag({
    String? id,
    required String name,
    required int colorValue,
  }) async {
    _checkWrite();
    _validateClassificationName(
      name,
      _classification.tags.where((t) => t.id != id).map((t) => t.name),
    );
    if (id != null && !_classification.tags.any((t) => t.id == id)) {
      throw StateError('Тег удалён');
    }
    final tag = UserTransactionTag(
      id: id ?? _classificationIds.next('tag'),
      name: name.trim(),
      colorValue: colorValue,
    );
    _classification = _classification.copyWith(
      tags: [..._classification.tags.where((t) => t.id != tag.id), tag],
    );
    _synoball.setCategoryPolicy(_classification.policy);
    await _changed();
    return tag;
  }

  Future<void> setTransactionTags(String id, Set<String> tagIds) async {
    _checkWrite();
    if (!tagIds.every((id) => _classification.tags.any((t) => t.id == id))) {
      throw ArgumentError('Неизвестный тег');
    }
    final t = _synoball.transactionById(id);
    if (t == null || t.status == CanonicalTransactionStatus.deleted) {
      throw StateError('Операция недоступна');
    }
    _synoball.updateTransaction(
      t.copyWith(
        tags: [
          ...t.tags.where((s) => !s.startsWith(userLabelPrefix)),
          ...tagIds.map((id) => '$userLabelPrefix$id'),
        ],
      ),
      actorId: _userId,
      purpose: 'User labels',
    );
    _syncFromSynoball();
    await _changed();
  }

  Future<void> deleteUserTag(String id) async {
    _checkWrite();
    _classification = _classification.copyWith(
      tags: _classification.tags.where((t) => t.id != id).toList(),
    );
    _synoball.removeUserTag(id, actorId: _userId);
    _rebuildClassification();
    await _changed();
  }
}
