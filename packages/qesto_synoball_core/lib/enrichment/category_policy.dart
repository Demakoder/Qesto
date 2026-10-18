import '../core/models.dart';

const userLabelPrefix = 'user-label:';
const userCategoryRulePrefix = 'user-category-rule:';

/// User-owned policy, passed to the existing enrichment pipeline. Not an
/// alternate transaction/category store. Rules match exact normalized identity.
class MerchantCategoryRule {
  const MerchantCategoryRule({
    required this.id,
    required this.entityId,
    required this.merchantKey,
    required this.merchantLabel,
    required this.categoryId,
    required this.direction,
  });
  final String id, entityId, merchantKey, merchantLabel, categoryId;
  final FinancialDirection direction;
  MerchantCategoryRule withCategory(String id) => MerchantCategoryRule(
    id: this.id,
    entityId: entityId,
    merchantKey: merchantKey,
    merchantLabel: merchantLabel,
    categoryId: id,
    direction: direction,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'merchantKey': merchantKey,
    'merchantLabel': merchantLabel,
    'categoryId': categoryId,
    'direction': direction.name,
  };
  factory MerchantCategoryRule.fromJson(Map<String, dynamic> j) =>
      MerchantCategoryRule(
        id: j['id'] as String,
        entityId: j['entityId'] as String,
        merchantKey: j['merchantKey'] as String,
        merchantLabel: j['merchantLabel'] as String,
        categoryId: j['categoryId'] as String,
        direction: FinancialDirection.values.byName(j['direction'] as String),
      );
}

class CategoryPolicy {
  const CategoryPolicy({
    this.rules = const [],
    this.redirects = const {},
    this.validTagIds,
  });
  final Set<String>? validTagIds;
  final List<MerchantCategoryRule> rules;
  final Map<String, String> redirects;
  String? resolve(String? id) {
    final seen = <String>{};
    while (id != null && redirects.containsKey(id) && seen.add(id)) {
      id = redirects[id];
    }
    return id;
  }

  MerchantCategoryRule? ruleFor(CanonicalTransaction t, String? identity) {
    if (identity == null) return null;
    return rules
        .where(
          (r) =>
              r.entityId == t.entityId &&
              r.merchantKey == identity &&
              r.direction == t.direction,
        )
        .firstOrNull;
  }

  CanonicalTransaction apply(
    CanonicalTransaction t, {
    required String? identity,
  }) {
    final rule = ruleFor(t, identity);
    final tags = t.tags
        .where(
          (s) =>
              !s.startsWith(userCategoryRulePrefix) &&
              (!s.startsWith(userLabelPrefix) ||
                  validTagIds == null ||
                  validTagIds!.contains(s.substring(userLabelPrefix.length))),
        )
        .toSet();
    final manual = t.userCategoryOverride != null;
    if (!manual && rule != null) tags.add('$userCategoryRulePrefix${rule.id}');
    final before = t.effectiveCategory;
    final automatic = resolve(
      !manual && rule != null
          ? rule.categoryId
          : t.synoballCategory ??
                (redirects.containsKey(t.providerCategory)
                    ? t.providerCategory
                    : null),
    );
    final override = resolve(t.userCategoryOverride);
    final after = override ?? automatic ?? resolve(t.providerCategory);
    return t.copyWith(
      synoballCategory: automatic,
      userCategoryOverride: override,
      // Preserve original bank category. A redirect supplies the display target.
      tags: tags.toList(),
      clearSubcategoryId: before != after,
      categoryConfidence: !manual && rule != null ? 1 : t.categoryConfidence,
    );
  }
}
