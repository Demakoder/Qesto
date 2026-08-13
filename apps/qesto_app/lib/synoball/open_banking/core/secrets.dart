import 'dart:convert';

class SecretValue {
  const SecretValue(this._value);

  static const redacted = '[REDACTED]';

  final String _value;

  int get byteLength => utf8.encode(_value).length;

  bool matches(String candidate) {
    final expected = utf8.encode(_value);
    final actual = utf8.encode(candidate);
    var difference = expected.length ^ actual.length;
    final length = expected.length > actual.length
        ? expected.length
        : actual.length;
    for (var index = 0; index < length; index++) {
      final left = index < expected.length ? expected[index] : 0;
      final right = index < actual.length ? actual[index] : 0;
      difference |= left ^ right;
    }
    return difference == 0;
  }

  @override
  String toString() => redacted;

  String toJson() => redacted;
}

class SecretReference {
  const SecretReference(this.id) : assert(id != '');

  final String id;

  @override
  String toString() => 'SecretReference($id)';
}
