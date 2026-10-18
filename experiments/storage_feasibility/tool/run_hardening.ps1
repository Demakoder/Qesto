param([switch]$IncludeBenchmarks)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskDart='C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$taskFlutter='C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
function Invoke-CheckedDart([string]$Directory,[string[]]$Arguments,[string]$Log='') {
  Push-Location $Directory
  try {
    if($Log) { & $taskDart @Arguments > $Log } else { & $taskDart @Arguments }
    if($LASTEXITCODE -ne 0) {throw "Dart check failed: $Arguments"}
  } finally {Pop-Location}
}
& "$PSScriptRoot/build_fault_shim.ps1"
foreach($taskTarget in @('hardening','key_hardening')) {
  $taskOutput=if($taskTarget -eq 'hardening') {'native_hardening'} else {$taskTarget}
  Invoke-CheckedDart $taskRoot @('build','cli','-t',"bin/$taskTarget.dart",'-o',"build/$taskOutput")
  Push-Location $taskRoot
  try {
    & "./build/$taskOutput/bundle/bin/$taskTarget.exe"
    if($LASTEXITCODE -ne 0) {throw "$taskTarget failed"}
  } finally {Pop-Location}
}
Invoke-CheckedDart $taskRoot @('test','test/contract_test.dart','test/hardening_policy_test.dart','--reporter','json') 'results/hardening_contracts_ab.jsonl'
Invoke-CheckedDart "$taskRoot/plain_runner" @('test','--reporter','json') '../results/hardening_contracts_c.jsonl'
Invoke-CheckedDart "$taskRepo/packages/qesto_synoball_core" @('test','--reporter','json') '../../experiments/storage_feasibility/results/hardening_shared_parity.jsonl'
Invoke-CheckedDart "$taskRepo/apps/qesto_app" @($taskFlutter,'test','test/storage_recovery_safety_test.dart','test/user_financial_data_codec_test.dart','test/synoball_core_test.dart','test/shared_synoball_core_compatibility_test.dart','test/synoball_safety_test.dart','--reporter','json') '../../experiments/storage_feasibility/results/hardening_app_regression.jsonl'
Invoke-CheckedDart "$taskRoot/android_probe" @($taskFlutter,'test','test/windows_vault_hardening_test.dart','--reporter','json') '../results/hardening_plugin_tests.jsonl'
Invoke-CheckedDart $taskRoot @('analyze') 'results/hardening_analyze.txt'
Invoke-CheckedDart "$taskRoot/android_probe" @($taskFlutter,'analyze') '../results/hardening_plugin_analyze.txt'
if($IncludeBenchmarks) {
  Invoke-CheckedDart $taskRoot @('build','cli','-t','bin/ownership_benchmark.dart','-o','build/ownership_benchmark')
  Push-Location $taskRoot
  try {
    & './build/ownership_benchmark/bundle/bin/ownership_benchmark.exe'
    if($LASTEXITCODE -ne 0) {throw 'Benchmark failed'}
  } finally {Pop-Location}
}
Invoke-CheckedDart $taskRoot @('run','tool/collect_hardening_results.dart')
