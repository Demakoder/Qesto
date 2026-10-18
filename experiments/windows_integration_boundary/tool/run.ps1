$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskDart='C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$taskFlutter='C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
function Invoke-Check([string]$Directory,[string[]]$Arguments,[string]$Log='') {
  Push-Location $Directory
  try {
    if($Log) { & $taskDart @Arguments > (Join-Path $taskRoot "results/$Log") }
    else { & $taskDart @Arguments }
    if($LASTEXITCODE -ne 0) {throw "Check failed: $Arguments"}
  } finally {Pop-Location}
}
New-Item -ItemType Directory -Force (Join-Path $taskRoot 'results') | Out-Null
Invoke-Check $taskRoot @('pub','get')
Invoke-Check $taskRoot @('tool/configure_app_seam.dart')
Invoke-Check $taskRoot @('analyze') 'analyze.txt'
Invoke-Check $taskRoot @('build','cli','-t','bin/probe.dart','-o','build/probe')
Invoke-Check $taskRoot @('test','--concurrency=1','--reporter=json') 'boundary-tests.jsonl'
Invoke-Check "$taskRoot/flutter_runner" @($taskFlutter,'pub','get')
Invoke-Check "$taskRoot/flutter_runner" @('analyze') 'flutter-runner-analyze.txt'
Invoke-Check "$taskRoot/flutter_runner" @($taskFlutter,'test','test/controller_boundary_test.dart','--no-pub','--reporter=json') 'controller-tests.jsonl'
Invoke-Check "$taskRoot/flutter_runner" @($taskFlutter,'test','test/benchmark_test.dart','--no-pub','--reporter=json') 'benchmark-tests.jsonl'
Invoke-Check "$taskRepo/apps/qesto_app" @('analyze') 'app-analyze.txt'
Invoke-Check "$taskRepo/apps/qesto_app" @($taskFlutter,'test',
  'test/desktop_shell_test.dart','test/classification_test.dart','test/classification_ui_test.dart',
  'test/mobile_transaction_editor_test.dart','test/pending_notification_editor_safety_test.dart',
  'test/financial_write_safety_test.dart','test/transaction_trash_test.dart',
  'test/sber_financial_integrity_test.dart','test/sber_savings_transfer_test.dart',
  'test/sber_import_flow_test.dart','test/user_financial_data_codec_test.dart',
  'test/storage_recovery_safety_test.dart','test/shared_synoball_core_compatibility_test.dart',
  'test/synoball_safety_test.dart','--no-pub','--reporter=json') 'app-regressions.jsonl'
Invoke-Check "$taskRepo/packages/qesto_synoball_core" @('test','--reporter=json') 'shared-parity.jsonl'
Invoke-Check "$taskRepo/experiments/storage_feasibility" @('test',
  'test/container_contract_test.dart','test/container_process_test.dart',
  'test/contract_test.dart','test/hardening_policy_test.dart','--concurrency=1','--reporter=json') 'storage-regressions.jsonl'
Invoke-Check $taskRoot @('run','tool/check_sources.dart')
Invoke-Check $taskRoot @('tool/mutation_inventory.dart')
Invoke-Check $taskRoot @('run','tool/collect_results.dart')
