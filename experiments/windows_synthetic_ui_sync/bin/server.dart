import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:qesto_synthetic_sync/config.dart';
import 'package:qesto_synthetic_sync/protocol.dart';
import 'package:qesto_synthetic_sync/server.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';
import 'package:qesto_synthetic_sync/domain_executor.dart';

/// Existing server/PG engine, with the common Qesto executor injected.
/// Fault selection is a local marked harness config, never an HTTP endpoint.
Future<void> main(List<String> args) => run(args);
Future<void> run(
  List<String> args, {
  SyncDomainExecutor executor = const QestoNoteExecutor(),
  void Function()? afterCommit,
}) async {
  final control = File(args[1]);
  final server = SyntheticServer(
    TestConfig.read(args[0]),
    executor: executor,
    hook: (stage, command, session) async {
      if (stage == 'after-commit') afterCommit?.call();
      if (!control.existsSync()) return;
      final f = object(jsonDecode(control.readAsStringSync()));
      if (f['stage'] != stage || f['change_id'] != command.changeId) return;
      File('${control.path}.hit').writeAsStringSync(stage, flush: true);
      if (f['action'] == 'drop-response') throw DropResponse();
      if (f['action'] == 'gate') {
        final until = DateTime.now().add(const Duration(seconds: 20));
        while (!File('${control.path}.release').existsSync()) {
          if (DateTime.now().isAfter(until))
            throw StateError('Synthetic gate timeout');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      } else if (f['action'] == 'database-error') {
        await session!.execute('SELECT 1/0');
      } else {
        throw StateError('Unknown synthetic fault');
      }
    },
  );
  final port = await server.start(port: int.parse(args[2]));
  stdout.writeln(
    jsonEncode({'listening': '127.0.0.1', 'port': port, 'pid': pid}),
  );
  await stdin.drain<void>();
  await server.close();
}
