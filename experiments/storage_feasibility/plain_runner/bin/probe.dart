import 'package:qesto_storage_spike/probe_harness.dart' as common;
import 'dart:io';
import 'package:qesto_storage_spike/storage_spike.dart';

Future<void> main(List<String> args) async {
  try {
    await common.probeMain(args, [Candidate.payloadGcm]);
  } catch (e) {
    stderr.writeln(
      'Probe failed (${e.runtimeType}); no SQL/key/payload logged',
    );
    exitCode = 1;
  }
}
