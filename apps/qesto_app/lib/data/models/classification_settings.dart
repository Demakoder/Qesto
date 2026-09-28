import 'budget_models.dart';
import '../../synoball/enrichment/category_policy.dart';

class UserTransactionTag {
  const UserTransactionTag({
    required this.id,
    required this.name,
    required this.colorValue,
  });
  final String id, name;
  final int colorValue;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
  };
  factory UserTransactionTag.fromJson(Map<String, dynamic> j) =>
      UserTransactionTag(
        id: j['id'] as String,
        name: j['name'] as String,
        colorValue: j['colorValue'] as int,
      );
}

/// Extends the existing user profile; category IDs in canonical transactions
/// remain the only assignment. Redirects are durable tombstones after a merge.
class ClassificationSettings {
  const ClassificationSettings({
    this.customCategories = const [],
    this.rules = const [],
    this.tags = const [],
    this.redirects = const {},
  });
  final List<BudgetCategory> customCategories;
  final List<MerchantCategoryRule> rules;
  final List<UserTransactionTag> tags;
  final Map<String, String> redirects;
  CategoryPolicy get policy => CategoryPolicy(
    rules: rules,
    redirects: redirects,
    validTagIds: tags.map((t) => t.id).toSet(),
  );
  ClassificationSettings copyWith({
    List<BudgetCategory>? customCategories,
    List<MerchantCategoryRule>? rules,
    List<UserTransactionTag>? tags,
    Map<String, String>? redirects,
  }) => ClassificationSettings(
    customCategories: customCategories ?? this.customCategories,
    rules: rules ?? this.rules,
    tags: tags ?? this.tags,
    redirects: redirects ?? this.redirects,
  );
  Map<String, dynamic> toJson() => {
    'customCategories': [
      for (final c in customCategories)
        {
          'id': c.id,
          'name': c.name,
          'iconKey': c.iconKey,
          'colorValue': c.colorValue,
        },
    ],
    'rules': rules.map((r) => r.toJson()).toList(),
    'tags': tags.map((t) => t.toJson()).toList(),
    'redirects': redirects,
  };
  factory ClassificationSettings.fromJson(Map<String, dynamic> j) =>
      ClassificationSettings(
        customCategories: [
          for (final c in (j['customCategories'] as List? ?? []))
            BudgetCategory(
              id: c['id'] as String,
              name: c['name'] as String,
              iconKey: c['iconKey'] as String,
              colorValue: c['colorValue'] as int,
            ),
        ],
        rules: [
          for (final r in (j['rules'] as List? ?? []))
            MerchantCategoryRule.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
        tags: [
          for (final t in (j['tags'] as List? ?? []))
            UserTransactionTag.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
        redirects: Map<String, String>.from(j['redirects'] as Map? ?? {}),
      );
}
