import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'config.dart';
import 'database.dart';
import 'domain_executor.dart';
import 'protocol.dart';

class DropResponse implements Exception {}

class SyntheticServer {
  SyntheticServer(
    this.config, {
    FaultHook? hook,
    SyncDomainExecutor executor = const LegacySyncDomainExecutor(),
  }) : db = SyncDatabase(config, hook: hook, executor: executor);
  final TestConfig config;
  final SyncDatabase db;
  late final HttpServer http;
  int _active = 0;
  Future<int> start({int port = 0}) async {
    await db.verifyEnvironment();
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    http.idleTimeout = const Duration(seconds: 10);
    http.listen(_handle);
    return http.port;
  }

  Future<void> close() => http.close(force: true);
  Future<void> _handle(HttpRequest request) async {
    if (_active >= 16) {
      request.response.statusCode = 503;
      await request.response.close();
      return;
    }
    _active++;
    try {
      // No browser CORS flow, cookies or arbitrary proxy-host handling.
      if (request.headers.value('origin') != null ||
          request.connectionInfo?.remoteAddress.isLoopback != true)
        throw const ApiError(403, 'LOCAL_TEST_ONLY');
      final token = request.headers.value('authorization');
      final matches = config.principals.where(
        (p) => token == 'Bearer ${p.token}',
      );
      if (matches.length != 1) throw const ApiError(401, 'UNAUTHENTICATED');
      final principal = matches.single;
      final segments = request.uri.pathSegments;
      final device = request.headers.value('x-device-id');
      principal.authorize(principal.workspace, device ?? '');
      if (request.headers.value('x-protocol-version') != '$protocolVersion' ||
          request.headers.value('x-domain-version') != '$domainVersion')
        throw const ApiError(409, 'VERSION_MISMATCH');
      Object? result;
      if (request.method == 'GET' &&
          request.uri.path == '/sync/v1/capabilities') {
        result = {
          'protocol_version': protocolVersion,
          'domain_version': domainVersion,
          'synthetic_only': true,
          'commands': ['transaction.set_note'],
          'max_body_bytes': maxBodyBytes,
        };
      } else {
        if (segments.length != 5 ||
            segments.take(3).join('/') != 'sync/v1/workspaces')
          throw const ApiError(404, 'NOT_FOUND');
        principal.authorize(identifier(segments[3]), device!);
        switch ((request.method, segments[4])) {
          case ('GET', 'snapshot'):
            result = await db.snapshot(principal);
          case ('GET', 'changes'):
            if (!request.uri.queryParameters.keys.every(
              {'cursor', 'limit'}.contains,
            ))
              throw const ApiError(400, 'UNKNOWN_QUERY');
            final limit = int.tryParse(
              request.uri.queryParameters['limit'] ?? '100',
            );
            if (limit == null) throw const ApiError(400, 'INVALID_PAGE_SIZE');
            result = await db.pull(
              principal,
              request.uri.queryParameters['cursor'],
              limit,
            );
          case ('POST', 'push'):
            if (request.headers.contentType?.mimeType != 'application/json')
              throw const ApiError(415, 'JSON_REQUIRED');
            final bytes = await _boundedBody(request);
            final command = NoteCommand.parse(jsonDecode(utf8.decode(bytes)));
            result = await db.push(principal, command);
          default:
            throw const ApiError(404, 'NOT_FOUND');
        }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('cache-control', 'no-store');
      request.response.write(jsonEncode(result));
    } on DropResponse {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
    } on ApiError catch (e) {
      request.response.statusCode = e.status;
      request.response.write(jsonEncode({'error': e.code}));
    } on FormatException {
      request.response.statusCode = 400;
      request.response.write('{"error":"INVALID_JSON"}');
    } on TimeoutException {
      request.response.statusCode = 408;
      request.response.write('{"error":"TIMEOUT"}');
    } on ServerException {
      request.response.statusCode = 503;
      request.response.write('{"error":"DATABASE_UNAVAILABLE_RETRY_SAME_ID"}');
    } catch (e) {
      // No credentials, SQL, commands or financial state in logs/responses.
      stderr.writeln('request failed: ${e.runtimeType}');
      request.response.statusCode = 503;
      request.response.write('{"error":"OUTCOME_UNKNOWN_RETRY_SAME_ID"}');
    } finally {
      _active--;
      try {
        await request.response.close();
      } on SocketException {
        /* disconnected test client */
      }
    }
  }

  Future<List<int>> _boundedBody(HttpRequest request) async {
    final stream = StreamIterator<List<int>>(request);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    final bytes = <int>[];
    var size = 0;
    try {
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) throw TimeoutException('Body deadline');
        if (!await stream.moveNext().timeout(remaining)) break;
        size += stream.current.length;
        if (size <= maxBodyBytes) bytes.addAll(stream.current);
        // Discard overflow without allocating it. Finish a finite request so
        // 413 reaches the client instead of cancelling the socket mid-upload.
      }
    } finally {
      await stream.cancel();
    }
    if (size > maxBodyBytes) throw const ApiError(413, 'BODY_TOO_LARGE');
    return bytes;
  }
}
