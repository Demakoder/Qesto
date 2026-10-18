param([switch]$IncludeRegressions)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskDart='C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$taskFlutter='C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
$taskTest=Join-Path $env:LOCALAPPDATA 'Pub/Cache/hosted/pub.dev/test-1.31.0/bin/test.dart'
$taskBackend=Join-Path $taskRepo 'experiments/synthetic_sync_backend'
function Invoke-Check([string]$Directory,[string[]]$Arguments,[string]$Log='') {
  Push-Location $Directory
  try {
    if($Log){& $taskDart @Arguments > (Join-Path $taskRoot "results/$Log")}
    else {& $taskDart @Arguments}
    if($LASTEXITCODE -ne 0){throw "Check failed: $Arguments"}
  } finally {Pop-Location}
}
Invoke-Check $taskRoot @('pub','get')
Invoke-Check "$taskRoot/flutter_runner" @($taskFlutter,'pub','get')
Invoke-Check $taskRoot @('run','tool/native_assets_seed.dart')
Invoke-Check $taskRoot @('tool/configure_app_seam.dart')
# No UI networking until BOTH complete semantic parity gates succeed.
# Direct test entry preserves the read-only package mapping after native hooks.
Invoke-Check $taskRoot @('--packages=.dart_tool/package_config.json',$taskTest,'test/semantic_parity_test.dart','--reporter=json') 'semantic-tests.jsonl'
Invoke-Check "$taskRoot/flutter_runner" @($taskFlutter,'test','test/semantic_gate_test.dart','--no-pub','--reporter=json') 'controller-semantic-tests.jsonl'
Invoke-Check $taskRoot @('build','cli','-t','bin/server.dart','-o','build/server')
Invoke-Check $taskRoot @('tool/configure_app_seam.dart')
Invoke-Check $taskRoot @('build','cli','-t','bin/client_probe.dart','-o','build/client_probe')
Invoke-Check $taskRoot @('tool/configure_app_seam.dart')
Invoke-Check $taskBackend @('tool/cluster.dart','resume')
try {
  Invoke-Check $taskRoot @('--packages=.dart_tool/package_config.json',$taskTest,'--concurrency=1','--reporter=json') 'native-tests.jsonl'
  # Sequential Flutter runs: do not replace a DLL while flutter_tester owns it.
  Invoke-Check "$taskRoot/flutter_runner" @($taskFlutter,'test','--no-pub','--concurrency=1','--reporter=json') 'flutter-tests.jsonl'
  Invoke-Check "$taskRoot/flutter_runner" @($taskFlutter,'test','test/two_ui_hosts_test.dart','--no-pub','--reporter=json') 'two-ui-tests.jsonl'
  Invoke-Check $taskRoot @('analyze') 'analyze.txt'
  Invoke-Check "$taskRoot/flutter_runner" @('analyze') 'flutter-runner-analyze.txt'
  if($IncludeRegressions) {
    Invoke-Check $taskBackend @('compile','exe','bin/server.dart','-o','build/server.exe')
    Invoke-Check $taskBackend @('compile','exe','tool/fault_server.dart','-o','build/fault_server.exe')
    Invoke-Check $taskBackend @('compile','exe','tool/client_worker.dart','-o','build/client_worker.exe')
    Invoke-Check $taskBackend @('test','--concurrency=1','--reporter=json') 'backend-regressions.jsonl'
    $taskClient=Join-Path $taskRepo 'experiments/encrypted_client_sync'
    Invoke-Check $taskClient @('build','cli','-t','bin/client.dart','-o','build/client')
    Invoke-Check $taskClient @('test','--concurrency=1','--reporter=json') 'client3b-regressions.jsonl'
    $taskBoundary=Join-Path $taskRepo 'experiments/windows_integration_boundary'
    Invoke-Check $taskBoundary @('pub','get')
    Invoke-Check $taskBoundary @('run',"$taskRoot/tool/native_assets_seed.dart")
    Invoke-Check $taskBoundary @('tool/configure_app_seam.dart')
    Invoke-Check $taskBoundary @('build','cli','-t','bin/probe.dart','-o','build/probe')
    Invoke-Check $taskBoundary @('tool/configure_app_seam.dart')
    Invoke-Check $taskBoundary @('--packages=.dart_tool/package_config.json',$taskTest,'--concurrency=1','--reporter=json') 'boundary4a-regressions.jsonl'
    Invoke-Check "$taskBoundary/flutter_runner" @($taskFlutter,'pub','get')
    Invoke-Check "$taskBoundary/flutter_runner" @($taskFlutter,'test','test/controller_boundary_test.dart','--no-pub','--reporter=json') 'controller4a-regressions.jsonl'
    Invoke-Check "$taskRepo/packages/qesto_synoball_core" @('test','--reporter=json') 'shared-parity.jsonl'
    Invoke-Check "$taskRepo/experiments/storage_feasibility" @('test','test/container_contract_test.dart','test/container_process_test.dart','test/contract_test.dart','test/hardening_policy_test.dart','--concurrency=1','--reporter=json') 'storage-regressions.jsonl'
    Invoke-Check "$taskRepo/apps/qesto_app" @($taskFlutter,'test','test/desktop_shell_test.dart','test/classification_test.dart','test/classification_ui_test.dart','test/mobile_transaction_editor_test.dart','test/pending_notification_editor_safety_test.dart','test/financial_write_safety_test.dart','test/transaction_trash_test.dart','test/sber_financial_integrity_test.dart','test/sber_savings_transfer_test.dart','test/sber_import_flow_test.dart','test/user_financial_data_codec_test.dart','test/storage_recovery_safety_test.dart','test/shared_synoball_core_compatibility_test.dart','test/synoball_safety_test.dart','--no-pub','--reporter=json') 'app-regressions.jsonl'
    foreach($taskAnalysis in @(
      @('apps/qesto_app','app-analyze'),@('packages/qesto_synoball_core','shared-analyze'),
      @('experiments/synthetic_sync_backend','backend-analyze'),@('experiments/encrypted_client_sync','client3b-analyze'),
      @('experiments/windows_integration_boundary','boundary4a-analyze'),@('experiments/storage_feasibility','storage-analyze'))) {
      Invoke-Check (Join-Path $taskRepo $taskAnalysis[0]) @('analyze') "$($taskAnalysis[1]).txt"
    }
    Invoke-Check $taskRoot @('tool/collect_results.dart')
  }
} finally {Invoke-Check $taskBackend @('tool/cluster.dart','stop')}
