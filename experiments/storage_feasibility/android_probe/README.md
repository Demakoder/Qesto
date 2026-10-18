# Android storage probe — synthetic only

Separate app ID: `ru.qesto.storage.qesto_storage_probe`, version `0.1.0+1`.
Label: Qesto Storage Spike (synthetic). Not Qesto; never accesses its profile.
Release uses the local debug signing key: test artifact, not distribution.
The release manifest has no INTERNET permission and disables auto-backup.

## Build

```powershell
$spikeDart = 'C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$spikeFlutter = 'C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
& $spikeDart $spikeFlutter pub get
& $spikeDart $spikeFlutter analyze
& $spikeDart $spikeFlutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.
MC assets: arm64-v8a, armeabi-v7a, x86_64. Runtime results intentionally absent
until a physical device is supplied and installation is agreed. Do not treat
successful build/static inspection as native-runtime acceptance.

## Later physical-device checklist

1. Install only the separate APK after agreement; leave real Qesto untouched.
2. Run synthetic checks, retain nonsecret JSON: native SQLite/source/MC versions,
   cipher/HMAC configuration, journal mode and negative scenarios.
3. Force-stop/relaunch, run again: `reusedVaultKey` true, revision advances.
   Reboot and repeat.
4. Inspect Android KeyInfo security level separately; plugin presence does not
   prove hardware backing. The unwrapped DB key still lives in process memory.
5. Exercise missing/corrupt key and interrupted rotation only in the synthetic
   app, retaining original key and backup. Missing key with existing DB must
   remain a recovery error, never reset data.
6. Add Android process-fault/performance tests and agreed portable-key recovery
   before approving production.

The button runs A/B, plugin key round trip, persistent reopen, keyed online
backup and in-process release safety. Windows subprocess executables cannot be
claimed as Android crash tests. C, Android subprocess faults, hardware KeyInfo,
uninstall/device-transfer recovery and atomic DB+vault cutover are not implemented.

Dedicated key namespace: `qesto-storage-spike-v1`. Synthetic DBs/results reside
only in the probe's own marked application-support directory.
