import '../../../data/models/qesto_models.dart';

class TransactionAccountResolution {
  const TransactionAccountResolution({
    required this.accountId,
    required this.confidence,
    required this.reason,
  });

  final String accountId;
  final double confidence;
  final String reason;
}

/// Shared, intentionally conservative account cascade for passive sources.
/// It never invents an account: ambiguous matches remain unresolved so the
/// preview UI can ask once for the whole batch.
class TransactionAccountResolver {
  const TransactionAccountResolver();

  TransactionAccountResolution? resolve({
    required Iterable<QestoAccount> accounts,
    String? accountHint,
    String? bankHint,
    String? currency,
  }) {
    final bank = _normalize(bankHint ?? '');
    final eligible = accounts
        .where(
          (account) =>
              account.type != AccountType.liability &&
              (currency == null || account.currency == currency) &&
              !_contradictsBank(_normalize(account.title), bank),
        )
        .toList(growable: false);
    if (eligible.isEmpty) return null;

    final suffix = _lastFour(accountHint ?? '');
    if (suffix != null) {
      final matches = eligible
          .where((account) => _suffixes(account.title).contains(suffix))
          .toList(growable: false);
      if (matches.length == 1) {
        return TransactionAccountResolution(
          accountId: matches.single.id,
          confidence: 0.99,
          reason: 'card_suffix',
        );
      }
      // An explicit unknown suffix contradicts a bank-name/default guess.
      return null;
    }

    if (bank.isNotEmpty) {
      final matches = eligible
          .where((account) => _bankMatches(_normalize(account.title), bank))
          .toList(growable: false);
      if (matches.length == 1) {
        return TransactionAccountResolution(
          accountId: matches.single.id,
          confidence: 0.65,
          reason: 'single_bank_account',
        );
      }
    }

    if (eligible.length == 1) {
      return TransactionAccountResolution(
        accountId: eligible.single.id,
        confidence: 0.60,
        reason: 'single_eligible_account',
      );
    }
    return null;
  }

  bool _contradictsBank(String account, String bank) {
    if (bank.isEmpty || _bankMatches(account, bank)) return false;
    return [
      'sber',
      'tbank',
      'alfa',
      'vtb',
      'gazprombank',
    ].any((known) => _bankMatches(account, known));
  }

  String? _lastFour(String value) {
    final matches = _suffixes(value);
    return matches.length == 1 ? matches.single : null;
  }

  Set<String> _suffixes(String value) => RegExp(
    r'(?<!\d)(\d{4})(?!\d)',
  ).allMatches(value).map((m) => m.group(1)!).toSet();

  bool _bankMatches(String account, String bank) {
    final aliases = <String, List<String>>{
      'sber': const ['sber', 'сбер'],
      'tbank': const ['tbank', 't bank', 'тинькофф', 'т банк'],
      'alfa': const ['alfa', 'alpha', 'альфа'],
      'vtb': const ['vtb', 'втб'],
      'gazprombank': const ['gazprom', 'газпром'],
    };
    final keys = aliases.entries
        .where((entry) => entry.value.any(bank.contains))
        .expand((entry) => entry.value);
    return keys.any(account.contains) || account.contains(bank);
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
