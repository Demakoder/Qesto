// Independent process for client crash/checkpoint and offline replay tests.
import 'dart:async';
import 'dart:io';
import 'package:qesto_synthetic_sync/client.dart';
import 'package:qesto_synthetic_sync/config.dart';

Future<void> main(List<String> args) async {
  final config = TestConfig.read(args[0]);
  final p = config.principals[int.parse(args[1])];
  final client = SyntheticClient(Uri.parse(args[2]), p, File(args[3]));
  switch (args[4]) {
    case 'bootstrap':
      await client.bootstrap();
    case 'prepare':
      client.prepare(
        args[5],
        args[6],
        target: args.length > 7 ? args[7] : 'synthetic-tx-0',
      );
    case 'push':
      await client.push(args[5]);
    case 'pull':
      await client.pullAll(limit: 1);
    case 'crash-before-checkpoint':
      final page = await client.page();
      client.applyPage(
        page,
        beforeSave: () {
          exit(87);
        },
      );
    default:
      throw ArgumentError('Unknown client action');
  }
}
