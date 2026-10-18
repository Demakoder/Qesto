import 'dart:convert';
import 'package:crypto/crypto.dart';

/// POC only: same canonical JSON v1 bytes, no new protocol or persisted digest.
/// Accepts decoded JSON, not arbitrary model objects. NOT enabled in transport.
String streamingDigest(Object? value) {
  final output = _DigestSink();
  final sink = utf8.encoder.startChunkedConversion(
    sha256.startChunkedConversion(output),
  );
  void write(Object? v) {
    if (v is Map<String, dynamic>) {
      final keys = v.keys.toList()..sort();
      sink.add('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) sink.add(',');
        sink.add(jsonEncode(keys[i]));
        sink.add(':');
        write(v[keys[i]]);
      }
      sink.add('}');
    } else if (v is List) {
      sink.add('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) sink.add(',');
        write(v[i]);
      }
      sink.add(']');
    } else if (v == null || v is String || v is num || v is bool) {
      sink.add(jsonEncode(v));
    } else {
      throw ArgumentError('decoded JSON only');
    }
  }

  write(value);
  sink.close();
  return output.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
