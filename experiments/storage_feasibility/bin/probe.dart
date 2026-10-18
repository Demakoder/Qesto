import 'dart:io';
import 'package:qesto_storage_spike/probe_harness.dart' as harness;
import 'package:qesto_storage_spike/storage_spike.dart';

Future<void> main(List<String> args) async {
  try {
    await harness.probeMain(args, [Candidate.driftMc, Candidate.directMc]);
  } catch (e) {
    stderr.writeln(
      'Probe failed (${e.runtimeType}); no SQL/key/payload logged',
    );
    exitCode = 1;
  }
}
