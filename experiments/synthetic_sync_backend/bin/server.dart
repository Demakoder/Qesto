import 'dart:convert';
import 'dart:io';
import 'package:qesto_synthetic_sync/config.dart';
import 'package:qesto_synthetic_sync/server.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1)
    throw ArgumentError('Path to synthetic config required');
  // No fault controls in this entry point; harness uses a separate binary.
  final server = SyntheticServer(TestConfig.read(args.single));
  final port = await server.start();
  stdout.writeln(
    jsonEncode({'listening': '127.0.0.1', 'port': port, 'pid': pid}),
  );
  await stdin.drain<void>();
  await server.close();
}
