param([switch]$IncludeBenchmarks)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskDart='C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$taskFlutter='C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
function Invoke-ContainerCheck([string]$Directory,[string[]]$Arguments,[string]$Log='') {
  Push-Location $Directory
  try {
    if($Log) { & $taskDart @Arguments > $Log } else { & $taskDart @Arguments }
    if($LASTEXITCODE -ne 0) {throw "Dart check failed: $Arguments"}
  } finally {Pop-Location}
}
& "$PSScriptRoot/build_fault_shim.ps1"
foreach($taskTarget in @('hardening','key_hardening')) {
  $taskOutput=if($taskTarget -eq 'hardening') {'native_hardening'} else {$taskTarget}
  $taskLog=if($taskTarget -eq 'hardening') {'native'} else {'key'}
  Invoke-ContainerCheck $taskRoot @('build','cli','-t',"bin/$taskTarget.dart",'-o',"build/$taskOutput")
  Push-Location $taskRoot
  try {
    & "./build/$taskOutput/bundle/bin/$taskTarget.exe" > "results/container_${taskLog}_regression.txt"
    if($LASTEXITCODE -ne 0) {throw "$taskTarget failed"}
  } finally {Pop-Location}
}
Invoke-ContainerCheck $taskRoot @('build','cli','-t','bin/container_probe.dart','-o','build/container_probe')
Invoke-ContainerCheck $taskRoot @('test','test/container_contract_test.dart','test/container_process_test.dart','--concurrency=1','--reporter','json') 'results/container_tests.jsonl'
Invoke-ContainerCheck $taskRoot @('test','test/contract_test.dart','test/hardening_policy_test.dart','--reporter','json') 'results/container_legacy_contracts.jsonl'
Invoke-ContainerCheck "$taskRoot/plain_runner" @('test','--reporter','json') '../results/container_plain_contracts.jsonl'
Invoke-ContainerCheck "$taskRepo/packages/qesto_synoball_core" @('test','--reporter','json') '../../experiments/storage_feasibility/results/container_shared_parity.jsonl'
Invoke-ContainerCheck "$taskRepo/apps/qesto_app" @($taskFlutter,'test','test/storage_recovery_safety_test.dart','test/user_financial_data_codec_test.dart','test/synoball_core_test.dart','test/shared_synoball_core_compatibility_test.dart','test/synoball_safety_test.dart','--reporter','json') '../../experiments/storage_feasibility/results/container_app_regression.jsonl'
Invoke-ContainerCheck $taskRoot @('analyze') 'results/container_analyze.txt'
Invoke-ContainerCheck $taskRoot @('run','tool/container_evidence.dart','verify')
if($IncludeBenchmarks) {Invoke-ContainerCheck $taskRoot @('run','tool/container_benchmarks.dart')}
Invoke-ContainerCheck $taskRoot @('run','tool/collect_container_results.dart')
