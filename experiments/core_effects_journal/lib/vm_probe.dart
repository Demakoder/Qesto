import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

/// Optional measurement process only, never used by core/executor/storage.
class VmProbe {
  VmProbe._(this.socket);
  final WebSocket socket;
  final pending = <int, Completer<dynamic>>{};
  int _id = 0;
  static Future<VmProbe> connect() async {
    final info = await Service.getInfo();
    if (info.serverUri == null) throw StateError('Use --enable-vm-service=0');
    final socket = await WebSocket.connect(
      info.serverUri!
          .replace(scheme: 'ws', path: '${info.serverUri!.path}ws')
          .toString(),
    );
    final probe = VmProbe._(socket);
    socket.listen((event) {
      final value = jsonDecode(event as String);
      final c = probe.pending.remove(value['id']);
      if (c == null) return;
      if (value['error'] != null) {
        c.completeError(StateError('${value['error']}'));
      } else {
        c.complete(value['result']);
      }
    });
    return probe;
  }

  Future<dynamic> allocation({bool gc = false, bool reset = false}) async {
    final id = ++_id, c = Completer<dynamic>();
    pending[id] = c;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': 'getAllocationProfile',
        'params': {
          'isolateId': Service.getIsolateId(Isolate.current),
          if (gc) 'gc': true,
          if (reset) 'reset': true,
        },
      }),
    );
    return c.future.timeout(const Duration(seconds: 30));
  }

  Future<void> close() async => socket.close();
}
