param([switch]$SkipBenchmarks)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRepo = Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskDart = 'C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$taskFlutter = 'C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
$taskBackend = Join-Path $taskRepo 'experiments/synthetic_sync_backend'
$taskStorage = Join-Path $taskRepo 'experiments/storage_feasibility'
function Invoke-Check([string]$Directory,[string[]]$Arguments,[string]$Log='') {
  Push-Location $Directory
  try {
    if($Log) { & $taskDart @Arguments > (Join-Path $taskRoot "results/$Log") }
    else { & $taskDart @Arguments }
    if($LASTEXITCODE -ne 0) { throw "Failed: $Arguments" }
  } finally {Pop-Location}
}
New-Item -ItemType Directory -Force (Join-Path $taskRoot 'results') | Out-Null
Invoke-Check $taskRoot @('pub','get')
if(!(Test-Path (Join-Path $taskRoot 'results/source_baseline.json'))) {
  Invoke-Check $taskRoot @('run','tool/source_evidence.dart','baseline')
}
Invoke-Check $taskBackend @('run','tool/cluster.dart','resume')
try {
  Invoke-Check $taskRoot @('analyze') 'analyze.txt'
  Invoke-Check $taskStorage @('analyze') 'storage-analyze.txt'
  Invoke-Check $taskRoot @('build','cli','-t','bin/client.dart','-o','build/client')
  Invoke-Check $taskRoot @('build','cli','-t','bin/benchmark.dart','-o','build/benchmark')
  Invoke-Check $taskRoot @('test','--concurrency=1','--reporter','json') 'tests.jsonl'
  if(!$SkipBenchmarks) {Invoke-Check $taskRoot @('run','tool/benchmarks.dart')}
  Invoke-Check $taskBackend @('test','--concurrency=1','--reporter','json') 'backend-regression-tests.jsonl'
  Invoke-Check "$taskRepo/packages/qesto_synoball_core" @('test','--reporter','json') 'shared-core-tests.jsonl'
  Invoke-Check $taskStorage @('build','cli','-t','bin/container_probe.dart','-o','build/container_probe')
  Invoke-Check $taskStorage @('test','test/container_contract_test.dart','test/container_process_test.dart','test/contract_test.dart','test/hardening_policy_test.dart','--concurrency=1','--reporter','json') 'storage-regression-tests.jsonl'
  Invoke-Check "$taskRepo/apps/qesto_app" @($taskFlutter,'test','test/storage_recovery_safety_test.dart','test/user_financial_data_codec_test.dart','test/synoball_core_test.dart','test/shared_synoball_core_compatibility_test.dart','test/synoball_safety_test.dart','--reporter','json') 'app-regression-tests.jsonl'
  Invoke-Check $taskRoot @('run','tool/source_evidence.dart','verify')
  Invoke-Check $taskRoot @('run','tool/collect_results.dart')
} finally {Invoke-Check $taskBackend @('run','tool/cluster.dart','stop')}
