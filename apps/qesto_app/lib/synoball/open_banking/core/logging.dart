import 'secrets.dart';

class OpenBankingLogSanitizer {
  const OpenBankingLogSanitizer();

  static final RegExp _secretKey = RegExp(
    r'(token|secret|assertion|authorization|cookie|nonce|state|code_verifier|certificate|private.?key)',
    caseSensitive: false,
  );
  static final RegExp _bankPayloadKey = RegExp(
    r'^(data|payload|raw|body|accounts?|balances?|statements?|transactions?)$',
    caseSensitive: false,
  );

  Object? sanitize(Object? value, {String? key}) {
    if (value is SecretValue || (key != null && _secretKey.hasMatch(key))) {
      return SecretValue.redacted;
    }
    if (key != null && _bankPayloadKey.hasMatch(key)) {
      return '[REDACTED BANK PAYLOAD]';
    }
    if (value is Map) {
      return value.map<String, Object?>((rawKey, rawValue) {
        final childKey = rawKey.toString();
        return MapEntry(childKey, sanitize(rawValue, key: childKey));
      });
    }
    if (value is Iterable) {
      return value.map((item) => sanitize(item)).toList(growable: false);
    }
    return value;
  }
}
