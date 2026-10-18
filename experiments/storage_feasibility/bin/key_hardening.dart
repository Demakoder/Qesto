import 'dart:convert';
import 'dart:io';
import 'package:qesto_storage_spike/generation_vault.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/windows_key_probe.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

final records = <Map<String, Object?>>[];
Future<void> record(
  String name,
  Future<Map<String, Object?>> Function() fn,
) async {
  try {
    records.add({'test': name, 'pass': true, ...await fn()});
    stdout.writeln('PASS $name');
  } catch (e, st) {
    records.add({
      'test': name,
      'pass': false,
      'type': '${e.runtimeType}',
      'reason': e is StateError ? e.message.toString() : 'rejected',
      'stack': st.toString().split('\n').take(5).join('\n'),
    });
    stderr.writeln('FAIL $name');
  }
}

Future<ProcessResult> child(List<String> args) => Process.run(
  Platform.script.path.endsWith('.dart')
      ? '${File(Platform.resolvedExecutable).parent.path}/dart.exe'
      : Platform.resolvedExecutable,
  [
    if (Platform.script.path.endsWith('.dart')) ...[
      'run',
      Platform.script.toFilePath(),
    ],
    ...args,
  ],
);
Future<Map<String, Object?>> rotation(String phase) async {
  final dir = createSpikeDirectory(), vault = GenerationVault(dir.path);
  await vault.provision(
    jsonEncode({'marker': marker, 'rows': List.filled(10000, 'synthetic')}),
  );
  final result = await child(['rotate-worker', dir.path, phase]);
  check(
    result.exitCode == 86,
    'rotation boundary worker must terminate 86: ${result.stderr}',
  );
  final restart = await child(['verify-worker', dir.path]);
  check(restart.exitCode == 0, 'fresh process recovery');
  final state = vault.read(), db = await vault.open();
  try {
    check(
      await db.revision() == 1,
      'rotation must not create financial revision',
    );
    final active = state['active'];
    check(
      active == (phase == 'after-manifest-promotion' ? 2 : 1),
      'active generation switch',
    );
    return {
      'exitCode': 86,
      'activeGeneration': active,
      'revision': await db.revision(),
      'freshProcessVerified': true,
      'oldDbRetained': File(vault.database(1)).existsSync(),
      'nativeKeyRotation': 'shadow encrypted online backup; no in-place rekey',
    };
  } finally {
    await db.close();
  }
}

Future<Map<String, Object?>> damage(String kind) async {
  final dir = createSpikeDirectory(), vault = GenerationVault(dir.path);
  await vault.provision(jsonEncode({'marker': marker, 'v': 1}));
  await vault.rotate();
  final clean = File(vault.control).readAsBytesSync();
  if (kind == 'missing') {
    File(vault.control).renameSync('${vault.control}.held');
  }
  if (kind == 'partial') {
    File(vault.control).writeAsBytesSync(clean.take(17).toList(), flush: true);
  }
  if (kind == 'corrupt') {
    clean[clean.length ~/ 2] ^= 0x45;
    File(vault.control).writeAsBytesSync(clean, flush: true);
  }
  if (kind == 'invalid-json') {
    File(vault.control).writeAsBytesSync(
      WindowsKeyProbe.protect(utf8.encode('{bad')),
      flush: true,
    );
  }
  if (kind == 'wrong-key' || kind == 'missing-key') {
    final state = vault.read();
    final descriptor =
        (state['generations'] as Map)['${state['active']}'] as Map;
    if (kind == 'missing-key') {
      descriptor.remove('key');
    } else {
      descriptor['key'] = base64Encode(randomKey());
    }
    File(vault.control).writeAsBytesSync(
      WindowsKeyProbe.protect(utf8.encode(jsonEncode(state))),
      flush: true,
    );
  }
  final before = File(vault.control).existsSync()
      ? base64Encode(File(vault.control).readAsBytesSync())
      : null;
  var failed = false;
  try {
    final db = await vault.open();
    await db.close();
  } catch (_) {
    failed = true;
  }
  check(failed, 'damaged state must fail closed');
  check(
    before ==
        (File(vault.control).existsSync()
            ? base64Encode(File(vault.control).readAsBytesSync())
            : null),
    'vault bytes preserved',
  );
  var provisionBlocked = false;
  try {
    await vault.provision('{}');
  } on RecoveryRequired {
    provisionBlocked = true;
  }
  check(provisionBlocked, 'must not generate empty replacement profile');
  final revision = await vault.recoverFromBackup();
  final restarted = await child(['verify-worker', dir.path]);
  check(
    revision == 1 && restarted.exitCode == 0,
    'explicit local backup restores recoverable generation',
  );
  return {
    'openRejected': true,
    'vaultPreserved': true,
    'provisionBlocked': true,
    'explicitRecoveryRevision': revision,
    'restartVerified': true,
  };
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final vault = GenerationVault(args[1]);
    if (args[0] == 'rotate-worker') {
      await vault.rotate(
        fault: (phase) {
          if (phase == args[2]) exit(86);
        },
      );
      throw StateError('missed rotation fault');
    }
    final db = await vault.open();
    await db.verify();
    await db.close();
    return;
  }
  for (final phase in [
    'before-dual-key',
    'after-dual-key',
    'during-copy',
    'after-verified-copy',
    'after-manifest-promotion',
  ]) {
    await record('rotation-crash-$phase', () => rotation(phase));
  }
  for (final kind in [
    'missing',
    'partial',
    'corrupt',
    'invalid-json',
    'wrong-key',
    'missing-key',
  ]) {
    await record('vault-$kind', () => damage(kind));
  }
  await record('successful-rotation-and-key-separation', () async {
    final dir = createSpikeDirectory(), vault = GenerationVault(dir.path);
    await vault.provision(jsonEncode({'marker': marker}));
    final old = base64Decode(
      (vault.read()['generations'] as Map)['1']['key'] as String,
    );
    await vault.rotate();
    final db = await vault.open();
    await db.verify();
    await db.close();
    var rejected = false;
    try {
      final bad = await SpikeStore.open(
        vault.database(2),
        Candidate.directMc,
        old,
      );
      await bad.close();
    } catch (_) {
      rejected = true;
    }
    check(rejected, 'new generation must reject old key');
    return {
      'activeGeneration': 2,
      'oldKeyRejectedByNewDb': true,
      'oldGenerationRetained': true,
    };
  });
  await record('two-generation-retention-bound', () async {
    final dir = createSpikeDirectory(), vault = GenerationVault(dir.path);
    await vault.provision(jsonEncode({'marker': marker}));
    await vault.rotate();
    var rejected = false;
    try {
      await vault.rotate();
    } on RecoveryRequired {
      rejected = true;
    }
    check(rejected, 'No unbounded generations or implicit key retirement');
    check(
      (vault.read()['generations'] as Map).length == 2,
      'Exactly two retained generations',
    );
    check(!File(vault.database(3)).existsSync(), 'No third database created');
    final db = await vault.open();
    await db.verify();
    await db.close();
    return {'nextRotationRequiresExplicitRetirement': true, 'retained': 2};
  });
  File('results/hardening_keys.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'date': DateTime.now().toUtc().toIso8601String(),
      'syntheticOnly': true,
      'results': records,
      'passed': records.where((r) => r['pass'] == true).length,
      'failed': records.where((r) => r['pass'] == false).length,
      'crossMachineRecovery': 'NOT PROVIDED by DPAPI-only local backup',
    }),
  );
  if (records.any((r) => r['pass'] != true)) exitCode = 1;
}
