import '../data/notification_capture_service.dart';
import '../domain/parsed_bank_transaction.dart';
import 'merchant_category_classifier.dart';

abstract interface class BankNotificationParser {
  ParsedBankTransaction? parse(CapturedNotification notification);
}

const supportedBankNotificationPackages = <String>{
  'ru.sberbankmobile',
  'com.idamob.tinkoff.android',
  'ru.alfabank.mobile.android',
  'ru.vtb24.mobilebanking.android',
};

const supportedSmsNotificationPackages = <String>{
  'com.google.android.apps.messaging',
  'com.samsung.android.messaging',
  'com.android.messaging',
  'com.android.mms',
  'com.miui.mms',
  'com.huawei.message',
};

/// Shared deterministic parser for direct bank pushes and banking SMS exposed
/// by Android's NotificationListener. Both an operation marker and an explicit
/// currency amount are required, keeping OTP, ads and balance-only notices out.
class FinancialNotificationParser implements BankNotificationParser {
  const FinancialNotificationParser({
    this.classifier = const MerchantCategoryClassifier(),
  });

  final MerchantCategoryClassifier classifier;

  @override
  ParsedBankTransaction? parse(CapturedNotification notification) {
    final packageName = notification.packageName.toLowerCase();
    final isSms = supportedSmsNotificationPackages.contains(packageName);
    if (!isSms && !supportedBankNotificationPackages.contains(packageName)) {
      return null;
    }

    final content = notification.fullText;
    final normalized = _normalize(content);
    if (content.isEmpty || _negativeNotice.hasMatch(normalized)) return null;

    final operation = _operation(normalized);
    if (operation == null) return null;
    final amount = _transactionAmount(content);
    if (amount == null || amount.minor <= 0) return null;

    final merchant = _merchant(
      notification: notification,
      content: content,
      operation: operation,
      amountMatch: amount.match,
    );
    if (merchant == null || merchant.isEmpty) return null;
    final suggestion = classifier.classify(merchant);
    final accountHint = _accountHint(content);

    return ParsedBankTransaction(
      notificationKey: notification.notificationKey,
      sourcePackage: notification.packageName,
      date: notification.postedAt,
      amountMinor: amount.minor,
      currency: amount.currency,
      merchant: merchant,
      categoryId: suggestion.categoryId,
      subcategoryId: suggestion.subcategoryId,
      accountHint: accountHint,
      confidence: _confidence(
        isSms: isSms,
        categoryId: suggestion.categoryId,
        accountHint: accountHint,
        merchant: merchant,
      ),
      kind: operation,
      isSmsNotification: isSms,
      bankHint: _bankHint(notification, isSms: isSms),
    );
  }

  ParsedBankTransactionKind? _operation(String value) {
    if (_refundMarker.hasMatch(value)) {
      return ParsedBankTransactionKind.refund;
    }
    if (_incomeMarker.hasMatch(value)) {
      return ParsedBankTransactionKind.income;
    }
    if (_transferMarker.hasMatch(value)) {
      return ParsedBankTransactionKind.transfer;
    }
    if (_expenseMarker.hasMatch(value)) {
      return ParsedBankTransactionKind.expense;
    }
    return null;
  }

  _ParsedAmount? _transactionAmount(String content) {
    final cutoff = RegExp(
      r'(баланс|остаток|доступно)\s*[:—-]?',
      caseSensitive: false,
    ).firstMatch(content);
    final operationPart = cutoff == null
        ? content
        : content.substring(0, cutoff.start);
    final matches = _money.allMatches(operationPart).toList(growable: false);
    if (matches.isEmpty) return null;
    final match = matches.first;
    final whole = int.tryParse(
      match.group(2)!.replaceAll(RegExp(r'[\s\u00A0\u202F]'), ''),
    );
    if (whole == null) return null;
    final fractionText = match.group(3);
    final fraction = switch (fractionText?.length) {
      null || 0 => 0,
      1 => int.parse(fractionText!) * 10,
      _ => int.parse(fractionText!),
    };
    final currencyText = match.group(4)!.toLowerCase();
    final currency = currencyText.contains(r'$') || currencyText.contains('usd')
        ? 'USD'
        : currencyText.contains('€') || currencyText.contains('eur')
        ? 'EUR'
        : 'RUB';
    return _ParsedAmount(whole * 100 + fraction, currency, match);
  }

  String? _merchant({
    required CapturedNotification notification,
    required String content,
    required ParsedBankTransactionKind operation,
    required RegExpMatch amountMatch,
  }) {
    final title = notification.title.trim();
    final titleMerchant = title.replaceFirst(_leadingOperation, '').trim();
    if (_validMerchant(titleMerchant)) return titleMerchant;

    final amountLine = _lineContaining(content, amountMatch.start);
    final inline = amountLine
        .replaceFirst(_leadingOperation, '')
        .replaceFirst(_money, ' ')
        .split(
          RegExp(
            r'(?:карта|сч[её]т|баланс|остаток|доступно)',
            caseSensitive: false,
          ),
        )
        .first
        .trim();
    if (_validMerchant(inline)) return inline;

    final lines = content
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final amountLineIndex = lines.indexWhere(_money.hasMatch);
    for (var index = amountLineIndex + 1; index < lines.length; index++) {
      final candidate = lines[index]
          .split(
            RegExp(
              r'(?:карта|сч[её]т|баланс|остаток|доступно)',
              caseSensitive: false,
            ),
          )
          .first
          .trim();
      if (_validMerchant(candidate)) return candidate;
    }

    return switch (operation) {
      ParsedBankTransactionKind.income => 'Зачисление',
      ParsedBankTransactionKind.transfer => 'Перевод',
      ParsedBankTransactionKind.refund => 'Возврат',
      ParsedBankTransactionKind.expense => null,
    };
  }

  bool _validMerchant(String value) {
    final normalized = _normalize(value);
    if (normalized.length < 2 || _money.hasMatch(value)) return false;
    if (_metadataLine.hasMatch(normalized) ||
        _onlySender.hasMatch(normalized)) {
      return false;
    }
    return RegExp(r'[a-zа-я]', caseSensitive: false).hasMatch(value);
  }

  String _lineContaining(String content, int offset) {
    final start = content.lastIndexOf('\n', offset - 1) + 1;
    final next = content.indexOf('\n', offset);
    return content.substring(start, next < 0 ? content.length : next);
  }

  String? _accountHint(String content) {
    final suffix = _cardSuffix.firstMatch(content)?.group(1);
    if (suffix != null) return '*$suffix';
    final explicit = _account.firstMatch(content)?.group(1)?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return null;
  }

  String? _bankHint(CapturedNotification notification, {required bool isSms}) {
    final packageName = notification.packageName.toLowerCase();
    if (packageName.contains('sber')) return 'sber';
    if (packageName.contains('tinkoff')) return 'tbank';
    if (packageName.contains('alfa')) return 'alfa';
    if (packageName.contains('vtb')) return 'vtb';
    if (!isSms) return null;
    final sender = _normalize(notification.title);
    if (sender == '900' || sender.contains('сбер')) return 'sber';
    if (sender.contains('тинькофф') || sender.contains('т банк')) {
      return 'tbank';
    }
    if (sender.contains('альфа')) return 'alfa';
    if (sender.contains('втб')) return 'vtb';
    return null;
  }

  double _confidence({
    required bool isSms,
    required String categoryId,
    required String? accountHint,
    required String merchant,
  }) {
    var value = isSms ? 0.88 : 0.93;
    if (categoryId != 'other') value += 0.04;
    if (accountHint != null) value += 0.02;
    if (merchant == 'Перевод' ||
        merchant == 'Зачисление' ||
        merchant == 'Возврат') {
      value -= 0.08;
    }
    return value.clamp(0, 0.99).toDouble();
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static final _money = RegExp(
    r'([+−–—-]?\s*)(\d[\d\s\u00A0\u202F]*)(?:[,.](\d{1,2}))?\s*'
    r'(₽|р(?:уб)?\.?|rub|\$|usd|€|eur)',
    caseSensitive: false,
  );
  static final _account = RegExp(
    r'(?:сч[её]т\s+карты|карта|сч[её]т)\s*[:№]?\s*([^\r\n,;]+)',
    caseSensitive: false,
  );
  static final _cardSuffix = RegExp(r'[*•·]{1,4}\s*(\d{4})(?!\d)');
  static final _leadingOperation = RegExp(
    r'^\s*(?:покупка|оплата|списание|зачисление|поступление|пополнение|'
    r'перевод(?:\s+от)?|возврат|отмена\s+операции)\s*[:—-]?\s*',
    caseSensitive: false,
  );
  static final _expenseMarker = RegExp(r'(покупка|оплата|списание|снятие)');
  static final _incomeMarker = RegExp(
    r'(зачисление|поступление|пополнение|зарплата|перевод\s+от)',
  );
  static final _transferMarker = RegExp(r'(перевод|сбп)');
  static final _refundMarker = RegExp(
    r'(возврат|отмена\s+операци|reversal|refund)',
  );
  static final _negativeNotice = RegExp(
    r'(код\s+(?:подтверждения|для|доступа)|одноразов(?:ый|ого)\s+код|otp|'
    r'никому\s+не\s+сообщ|вход\s+в|карта\s+готова|изменен(?:ие|ы)\s+лимит|'
    r'предложение|оформите|кредит\s+до|напоминание|кешб[эе]к\s+(?:начислен|будет))',
  );
  static final _metadataLine = RegExp(
    r'^(?:баланс|остаток|доступно|карта|сч[её]т|плат[её]жный\s+сч[её]т)',
  );
  static final _onlySender = RegExp(
    r'^(?:900|sberbank|сбербанк|t bank|т банк)$',
  );
}

/// Backwards-compatible public name used by existing screens and tests.
class SberbankNotificationParser extends FinancialNotificationParser {
  const SberbankNotificationParser({super.classifier});
}

class _ParsedAmount {
  const _ParsedAmount(this.minor, this.currency, this.match);
  final int minor;
  final String currency;
  final RegExpMatch match;
}
