import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/probe_harness.dart'
    show releaseSafety, nativeInfo;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: ProbeScreen()));
}

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});
  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  String result =
      'Synthetic data only. No Qesto profile, bank access or internet permission.\n'
      'Run, restart this separate app, then run again to check key retention.';
  bool busy = false;

  Future<void> run() async {
    setState(() => busy = true);
    try {
      const vault = FlutterSecureStorage(
        aOptions: AndroidOptions(storageNamespace: 'qesto-storage-spike-v1'),
      );
      const keyName = 'qesto.synthetic.spike.key.v1';
      final root = await getApplicationSupportDirectory();
      final dir = Directory('${root.path}/qesto-storage-spike-android')
        ..createSync(recursive: true);
      File(
        '${dir.path}/.qesto-storage-spike',
      ).writeAsStringSync('synthetic-only');
      final encoded = await vault.read(key: keyName);
      final hadDatabase = dir.listSync().whereType<File>().any(
        (f) => f.path.endsWith('.db'),
      );
      if (encoded == null && hadDatabase) {
        throw StateError(
          'Key missing with existing database: recovery required; no key regeneration',
        );
      }
      final key = encoded == null ? randomKey() : base64Decode(encoded);
      if (encoded == null) {
        await vault.write(key: keyName, value: base64Encode(key));
      }
      if (await vault.read(key: keyName) != base64Encode(key)) {
        throw StateError('Vault round trip failed');
      }
      final results = <String, Object?>{
        'platform': Platform.operatingSystem,
        'hadDatabase': hadDatabase,
        'reusedVaultKey': encoded != null,
        'syntheticOnly': true,
        'separateApplicationId': 'ru.qesto.storage.qesto_storage_probe',
      };
      for (final candidate in [Candidate.driftMc, Candidate.directMc]) {
        final store = await SpikeStore.open(
          '${dir.path}/${candidate.name}.db',
          candidate,
          key,
        );
        try {
          await store.verify();
          final before = await store.revision();
          await store.apply(
            id: 'synthetic-${before + 1}',
            expected: before,
            snapshot: syntheticSnapshot(10),
          );
          await store.verify();
          final backup =
              '${dir.path}/backup-${candidate.name}-${DateTime.now().microsecondsSinceEpoch}.db';
          await store.backup(backup);
          results[candidate.name] = {
            'native': nativeInfo(store),
            'before': before,
            'after': await store.revision(),
            'releaseSafety': await releaseSafety(candidate),
          };
        } finally {
          await store.close();
        }
      }
      final json = const JsonEncoder.withIndent('  ').convert(results);
      File(
        '${dir.path}/probe-results.json',
      ).writeAsStringSync(json, flush: true);
      if (mounted) setState(() => result = json);
    } catch (e) {
      if (mounted) {
        setState(
          () => result =
              'FAILED: ${e.runtimeType}\nNo SQL, key or financial payload logged.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Storage spike 2a — NOT Qesto')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            'Only synthetic data. This APK does not replace Qesto. '
            'Release runtime results are not established until it runs on a real device.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : run,
            child: Text(busy ? 'Checking…' : 'Run native/key/atomicity checks'),
          ),
          const SizedBox(height: 16),
          Expanded(child: SingleChildScrollView(child: SelectableText(result))),
        ],
      ),
    ),
  );
}
