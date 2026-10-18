param([switch]$IncludeRegressions)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRepo = Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskDart = 'C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$taskFlutter = 'C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
function Invoke-SyncCheck([string]$Directory, [string[]]$Arguments, [string]$Log = '') {
  Push-Location $Directory
  try {
    if ($Log) { & $taskDart @Arguments > $Log } else { & $taskDart @Arguments }
    if ($LASTEXITCODE -ne 0) { throw "Check failed: $Arguments" }
  } finally { Pop-Location }
}
Push-Location $taskRoot
try {
  New-Item -ItemType Directory -Force build, results | Out-Null
  Invoke-SyncCheck $taskRoot @('pub','get')
  if (!(Test-Path 'results/source_baseline.json')) { Invoke-SyncCheck $taskRoot @('run','tool/source_evidence.dart','baseline') }
  if (Test-Path '.runtime/cluster.json') { Invoke-SyncCheck $taskRoot @('run','tool/cluster.dart','resume') }
  else { Invoke-SyncCheck $taskRoot @('run','tool/cluster.dart','start') }
  try {
    Invoke-SyncCheck $taskRoot @('compile','exe','bin/server.dart','-o','build/server.exe')
    Invoke-SyncCheck $taskRoot @('compile','exe','tool/fault_server.dart','-o','build/fault_server.exe')
    Invoke-SyncCheck $taskRoot @('compile','exe','tool/client_worker.dart','-o','build/client_worker.exe')
    Invoke-SyncCheck $taskRoot @('analyze') 'results/analyze.txt'
    Invoke-SyncCheck $taskRoot @('test','--concurrency=1','--reporter','json') 'results/tests.jsonl'
    if ($IncludeRegressions) {
      Invoke-SyncCheck "$taskRepo/packages/qesto_synoball_core" @('test','--reporter','json') '../../experiments/synthetic_sync_backend/results/shared-core-tests.jsonl'
      # Existing AOT container probe must be built; no production binary involved.
      Invoke-SyncCheck "$taskRepo/experiments/storage_feasibility" @('build','cli','-t','bin/container_probe.dart','-o','build/container_probe')
      Invoke-SyncCheck "$taskRepo/experiments/storage_feasibility" @('test','test/container_contract_test.dart','test/container_process_test.dart','test/contract_test.dart','test/hardening_policy_test.dart','--concurrency=1','--reporter','json') '../synthetic_sync_backend/results/storage-regression-tests.jsonl'
      Invoke-SyncCheck "$taskRepo/apps/qesto_app" @($taskFlutter,'test','test/storage_recovery_safety_test.dart','test/user_financial_data_codec_test.dart','test/synoball_core_test.dart','test/shared_synoball_core_compatibility_test.dart','test/synoball_safety_test.dart','--reporter','json') '../../experiments/synthetic_sync_backend/results/app-regression-tests.jsonl'
    }
    Invoke-SyncCheck $taskRoot @('run','tool/source_evidence.dart','verify')
    if ($IncludeRegressions) { Invoke-SyncCheck $taskRoot @('run','tool/collect_results.dart') }
  } finally { Invoke-SyncCheck $taskRoot @('run','tool/cluster.dart','stop') }
} finally { Pop-Location }
