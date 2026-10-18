import 'dart:convert';

import 'package:cryptography/dart.dart';

/// Adapter identity, not a financial schema ID. JSON avoids delimiter collisions.
String sourceIdentity(String namespace, List<Object?> parts) {
  final bytes = const DartSha256()
      .hashSync(utf8.encode(jsonEncode(parts)))
      .bytes;
  return '$namespace-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

String sourceIdentityText(String? value) =>
    (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
