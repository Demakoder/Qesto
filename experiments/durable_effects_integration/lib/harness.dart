import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'windows_driver.dart';

/// Matched full financial server/remote validation in both modes. Only local
/// format-2 effects commit/publication differs; no protocol or server shortcuts.
UiSyncHarness effectsHarness({bool effects = true}) => UiSyncHarness(
  root: '../../windows_synthetic_ui_sync',
  evidence: '../../windows_synthetic_ui_sync/results',
  incremental: effects,
  serverExecutable: '../build/server/bundle/bin/server.exe',
  effectsDriver: effects ? const EffectsDriverFactory() : null,
);
