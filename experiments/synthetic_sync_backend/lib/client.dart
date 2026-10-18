// Deliberately small synthetic adapter. Not the production transaction container.
import 'dart:convert';
import 'dart:io';
import 'protocol.dart';

class SyntheticClient {
  SyntheticClient(this.base, this.principal, this.file);
  final Uri base;
  final Principal principal;
  final File file;

  Map<String, dynamic> get local {
    // Missing/corrupt state is an error, never a fresh profile fallback.
    final m = object(jsonDecode(file.readAsStringSync()));
    if (m['marker'] != experimentMarker ||
        m['workspace_id'] != principal.workspace ||
        m['device_id'] != principal.device)
      throw StateError('Client partition mismatch');
    return m;
  }

  void _save(Map<String, dynamic> state) {
    final next = File('${file.path}.next')
      ..writeAsStringSync(jsonEncode(state), flush: true);
    next.renameSync(file.path);
  }

  String get _path => '/sync/v1/workspaces/${principal.workspace}';
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    if (base.host != '127.0.0.1' || base.scheme != 'http')
      throw StateError('Loopback only');
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await http.openUrl(
        method,
        base.replace(path: path, queryParameters: query),
      );
      req.headers.set('authorization', 'Bearer ${principal.token}');
      req.headers.set('x-device-id', principal.device);
      req.headers.set('x-protocol-version', '$protocolVersion');
      req.headers.set('x-domain-version', '$domainVersion');
      headers?.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final response = await req.close().timeout(const Duration(seconds: 20));
      final result = object(jsonDecode(await utf8.decodeStream(response)));
      if (response.statusCode != 200)
        throw ApiError(response.statusCode, result['error'] as String);
      return result;
    } finally {
      http.close(force: true);
    }
  }

  Future<void> bootstrap() async {
    if (file.existsSync()) throw StateError('Never overwrite a client profile');
    final s = await request('GET', '$_path/snapshot');
    _save({
      'marker': experimentMarker,
      'workspace_id': principal.workspace,
      'device_id': principal.device,
      'epoch': s['workspace_epoch'],
      'seq': s['head'],
      'cursor': s['cursor'],
      'entities': {
        for (final v in s['entities'] as List)
          (v['transaction'] as Map)['id']: v,
      },
      'pending': <String, dynamic>{},
      'receipts': <String, dynamic>{},
      'pages': <String, dynamic>{},
    });
  }

  Map<String, dynamic> prepare(
    String id,
    String note, {
    String target = 'synthetic-tx-0',
  }) {
    final s = local;
    final command = {
      'protocol_version': protocolVersion,
      'domain_version': domainVersion,
      'workspace_id': principal.workspace,
      'device_id': principal.device,
      'workspace_epoch': s['epoch'],
      'change_id': id,
      'kind': 'transaction.set_note',
      'transaction_id': target,
      'base_revision': s['entities'][target]['revision'],
      'note': note,
    };
    final pending = object(s['pending']);
    if (pending.containsKey(id) &&
        canonicalJson(pending[id]) != canonicalJson(command))
      throw StateError('Immutable command collision');
    pending[id] = command;
    _save(s);
    return command;
  }

  Future<Map<String, dynamic>> push(String id) async {
    final s = local;
    final command = s['pending'][id];
    if (command == null) throw StateError('Unknown durable command');
    final receipt = await request('POST', '$_path/push', body: command);
    // Receipt does NOT advance cursor. Commands remain as immutable history.
    final latest = local;
    latest['receipts'][id] = receipt;
    _save(latest);
    return receipt;
  }

  Future<Map<String, dynamic>> page({int limit = 100}) => request(
    'GET',
    '$_path/changes',
    query: {'cursor': local['cursor'] as String, 'limit': '$limit'},
  );
  void applyPage(Map<String, dynamic> page, {void Function()? beforeSave}) {
    versions(page['protocol_version'], page['domain_version']);
    final s = local;
    if (page['workspace_id'] != principal.workspace ||
        page['workspace_epoch'] != s['epoch'])
      throw StateError('Page partition mismatch');
    final pageHash = digest(page);
    if (s['pages'][pageHash] == true) return;
    var seq = decimal(s['seq']);
    if (decimal(page['from_seq']) != seq) throw StateError('Out of order page');
    for (final bundle in page['bundles'] as List) {
      if (decimal(bundle['seq']) != seq + 1) throw StateError('Gap in changes');
      for (final e in bundle['entities'] as List) {
        final tx = object(e['transaction']);
        final id = identifier(tx['id']);
        final old = s['entities'][id];
        if (old == null ||
            decimal(e['revision']) != decimal(old['revision']) + 1)
          throw StateError('Entity revision gap');
        s['entities'][id] = e;
      }
      final receipt = bundle['receipt'];
      s['receipts'][receipt['change_id']] = receipt;
      seq++;
    }
    if (seq > decimal(page['high']) ||
        (page['has_more'] == false && seq != decimal(page['high'])))
      throw StateError('Incomplete page');
    s['seq'] = '$seq';
    s['cursor'] = page['next_cursor'];
    s['pages'][pageHash] = true;
    beforeSave?.call();
    _save(s); // projection + receipts + checkpoint in one replacement
  }

  Future<void> pullAll({int limit = 100}) async {
    for (var i = 0; i < 1000; i++) {
      final p = await page(limit: limit);
      applyPage(p);
      if (p['has_more'] == false) return;
    }
    throw StateError('Page limit');
  }
}
