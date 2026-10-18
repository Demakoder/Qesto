import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:qesto_synthetic_sync/protocol.dart';

typedef Request =
    Future<Map<String, dynamic>> Function(
      String method,
      String endpoint, {
      Object? body,
      Map<String, String>? query,
    });

/// The 3a HTTP protocol, without its unencrypted file client. Loopback only.
class LoopbackTransport {
  LoopbackTransport(this.base, this.principal);
  final Uri base;
  final Principal principal;
  final Map<String, int> metrics = {
    'sent_body_bytes': 0,
    'received_body_bytes': 0,
  };
  Future<Map<String, dynamic>> request(
    String method,
    String endpoint, {
    Object? body,
    Map<String, String>? query,
  }) async {
    if (base.scheme != 'http' ||
        base.host != '127.0.0.1' ||
        base.userInfo.isNotEmpty)
      throw StateError('Loopback only');
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      return await (() async {
        final r = await http.openUrl(
          method,
          base.replace(
            path: '/sync/v1/workspaces/${principal.workspace}/$endpoint',
            queryParameters: query,
          ),
        );
        r.followRedirects = false;
        r.headers.set('authorization', 'Bearer ${principal.token}');
        r.headers.set('x-device-id', principal.device);
        r.headers.set('x-protocol-version', '$protocolVersion');
        r.headers.set('x-domain-version', '$domainVersion');
        if (body != null) {
          r.headers.contentType = ContentType.json;
          final encoded = utf8.encode(jsonEncode(body));
          metrics['sent_body_bytes'] =
              metrics['sent_body_bytes']! + encoded.length;
          r.add(encoded);
        }
        final response = await r.close();
        final bytes = <int>[];
        await for (final part in response) {
          if (bytes.length + part.length > 64 * 1024 * 1024)
            throw const FormatException('Response bound');
          bytes.addAll(part);
        }
        final value = object(jsonDecode(utf8.decode(bytes)));
        metrics['received_body_bytes'] =
            metrics['received_body_bytes']! + bytes.length;
        if (response.statusCode != 200)
          throw ApiError(
            response.statusCode,
            value['error'] as String? ?? 'HTTP_ERROR',
          );
        return value;
      })().timeout(const Duration(seconds: 20));
    } finally {
      http.close(force: true);
    }
  }
}
