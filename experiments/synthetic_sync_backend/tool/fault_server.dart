// Test executable only: fault selection is a local harness file, never HTTP.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:qesto_synthetic_sync/config.dart';
import 'package:qesto_synthetic_sync/protocol.dart';
import 'package:qesto_synthetic_sync/server.dart';

Future<void> main(List<String> args) async {
  final control = File(args[1]);
  final server = SyntheticServer(
    TestConfig.read(args[0]),
    hook: (stage, command, session) async {
      if (!control.existsSync()) return;
      final fault = object(jsonDecode(control.readAsStringSync()));
      if (fault['stage'] != stage || fault['change_id'] != command.changeId)
        return;
      File('${control.path}.hit').writeAsStringSync(stage, flush: true);
      switch (fault['action']) {
        case 'drop-response':
          throw DropResponse();
        case 'database-error':
          await session!.execute('SELECT 1/0');
        case 'gate':
          final released = File('${control.path}.release');
          final until = DateTime.now().add(const Duration(seconds: 20));
          while (!released.existsSync()) {
            if (DateTime.now().isAfter(until))
              throw StateError('Test gate timeout');
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        default:
          throw StateError('Unknown test fault');
      }
    },
  );
  final port = await server.start();
  stdout.writeln(
    jsonEncode({'listening': '127.0.0.1', 'port': port, 'pid': pid}),
  );
  await stdin.drain<void>();
  await server.close();
}
