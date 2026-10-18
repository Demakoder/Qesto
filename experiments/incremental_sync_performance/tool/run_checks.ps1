param([switch]$Benchmarks,[switch]$Regressions)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskDart='C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$taskFlutter='C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
$taskTest=Join-Path $env:LOCALAPPDATA 'Pub/Cache/hosted/pub.dev/test-1.31.0/bin/test.dart'
function Check([string]$Directory,[string[]]$Arguments,[string]$Log='') {
  Push-Location $Directory
  try {
    if($Log){& $taskDart @Arguments > (Join-Path $taskRoot "results/$Log")}else{& $taskDart @Arguments}
    if($LASTEXITCODE -ne 0){throw "Failed: $Arguments"}
  } finally {Pop-Location}
}
Check $taskRoot @('pub','get')
Check $taskRoot @('run','../windows_synthetic_ui_sync/tool/native_assets_seed.dart')
Check $taskRoot @('tool/configure_app_seam.dart')
Check "$taskRoot/flutter_runner" @($taskFlutter,'pub','get')
Check $taskRoot @('build','cli','-t','bin/server.dart','-o','build/server')
Check $taskRoot @('tool/configure_app_seam.dart')
Check $taskRoot @('build','cli','-t','bin/client_probe.dart','-o','build/client_probe')
Check $taskRoot @('tool/configure_app_seam.dart')
Check "$taskRepo/experiments/storage_feasibility" @('build','cli','-t','bin/container_probe.dart','-o','build/container_probe')
Check "$taskRepo/experiments/windows_synthetic_ui_sync" @('tool/configure_app_seam.dart')
Check "$taskRepo/experiments/windows_synthetic_ui_sync" @('build','cli','-t','bin/client_probe.dart','-o','build/client_probe')
Check "$taskRepo/experiments/windows_synthetic_ui_sync" @('tool/configure_app_seam.dart')
Check "$taskRepo/experiments/synthetic_sync_backend" @('tool/cluster.dart','resume')
try {
  Check $taskRoot @('--packages=.dart_tool/package_config.json',$taskTest,'test/chunk_storage_test.dart','test/native_chunk_fault_test.dart','test/sync_integration_test.dart','test/handoff_profile_test.dart','--concurrency=1','--reporter=json') 'native-final.jsonl'
  Check "$taskRoot/flutter_runner" @($taskFlutter,'test','test/two_ui_hosts_test.dart','--no-pub','--reporter=json') 'ui-final.jsonl'
  if($Benchmarks) {
    foreach($taskMode in @('baseline','incremental')) {
      $env:QESTO_4C_BENCH_MODE=$taskMode
      Check "$taskRoot/flutter_runner" @($taskFlutter,'test','test/benchmark_test.dart','--no-pub','--concurrency=1','--reporter=json') "flutter-matched-$taskMode.jsonl"
    }
    Remove-Item Env:QESTO_4C_BENCH_MODE
  }
  if($Regressions) {
    Check "$taskRepo/experiments/synthetic_sync_backend" @('test','--concurrency=1','--reporter=json') 'backend-regression.jsonl'
    Check "$taskRepo/experiments/encrypted_client_sync" @('build','cli','-t','bin/client.dart','-o','build/client')
    Check "$taskRepo/experiments/encrypted_client_sync" @('test','--concurrency=1','--reporter=json') 'client-regression.jsonl'
    Check "$taskRepo/experiments/storage_feasibility" @('test','test/container_contract_test.dart','test/container_process_test.dart','test/contract_test.dart','test/hardening_policy_test.dart','--concurrency=1','--reporter=json') 'storage-regression.jsonl'
    Check "$taskRepo/packages/qesto_synoball_core" @('test','--reporter=json') 'shared-parity.jsonl'
    Check "$taskRepo/experiments/windows_synthetic_ui_sync" @('tool/configure_app_seam.dart')
    Check "$taskRepo/experiments/windows_synthetic_ui_sync" @('--packages=.dart_tool/package_config.json',$taskTest,'test/semantic_parity_test.dart','test/integration_test.dart','--concurrency=1','--reporter=json') 'old4b-regression.jsonl'
    Check "$taskRepo/apps/qesto_app" @($taskFlutter,'test','test/desktop_shell_test.dart','test/classification_test.dart','test/financial_write_safety_test.dart','test/transaction_trash_test.dart','test/user_financial_data_codec_test.dart','test/storage_recovery_safety_test.dart','test/shared_synoball_core_compatibility_test.dart','test/synoball_safety_test.dart','--no-pub','--reporter=json') 'app-regression.jsonl'
  }
  foreach($taskPkg in @('incremental_sync_performance','storage_feasibility','encrypted_client_sync','windows_integration_boundary','windows_synthetic_ui_sync','synthetic_sync_backend')) {
    Check "$taskRepo/experiments/$taskPkg" @('analyze') "analyze-$taskPkg.txt"
  }
  Check "$taskRoot/flutter_runner" @('analyze') 'analyze-flutter-runner.txt'
} finally {Check "$taskRepo/experiments/synthetic_sync_backend" @('tool/cluster.dart','stop')}
