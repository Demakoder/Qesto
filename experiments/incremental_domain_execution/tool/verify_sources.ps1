$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskBaseline=Get-Content -LiteralPath (Join-Path $taskRoot 'results/source-baseline.json') -Raw|ConvertFrom-Json
$taskChanges=@()
$taskSourceChanges=@()
foreach($taskEntry in $taskBaseline.PSObject.Properties){
  $taskFile=Join-Path $taskRepo $taskEntry.Name
  $taskHash=if(Test-Path -LiteralPath $taskFile){(Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash}else{'MISSING'}
  if($taskHash -ne $taskEntry.Value){
    $taskChanges+=$taskEntry.Name
    if($taskEntry.Name -match '\.(dart|yaml|lock|ps1|c|h|cpp)$'){$taskSourceChanges+=$taskEntry.Name}
  }
}
$taskExpected=@('packages/qesto_synoball_core/lib/core/synoball_core.dart','experiments/incremental_sync_performance/flutter_runner/test/benchmark_test.dart')
$taskUnexpected=@($taskSourceChanges | Where-Object {$_ -notin $taskExpected})
$taskResult=[ordered]@{baseline_entries=@($taskBaseline.PSObject.Properties).Count;source_changes=$taskSourceChanges;unexpected_source_changes=$taskUnexpected;generated_evidence_changes=@($taskChanges|Where-Object {$_ -notin $taskSourceChanges});app_source_unchanged=(@($taskChanges|Where-Object {$_ -like 'apps/qesto_app/*'}).Count -eq 0);goldens_unchanged=(@($taskChanges|Where-Object {$_ -like 'packages/qesto_synoball_core/test/goldens/*'}).Count -eq 0);real_profiles_read=$false;real_profile_hash_verification='not attempted: forbidden by scope'}
$taskResult|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $taskRoot 'results/source-verification.json') -Encoding utf8
$taskArtifacts=@(Get-ChildItem -LiteralPath $taskRoot -Recurse -File -Force | Where-Object {$_.FullName -notmatch '[\\/](\.dart_tool|build|\.runtime)[\\/]' -and $_.Name -notin @('.flutter-plugins-dependencies','artifacts.json')})
$taskArtifacts+=@(foreach($taskOutside in @('packages/qesto_synoball_core/lib/core/synoball_core.dart','packages/qesto_synoball_core/test/prepared_fork_test.dart','experiments/incremental_sync_performance/flutter_runner/test/benchmark_test.dart','docs/sync/2026-10-15/Incremental_Domain_Performance_Report.md')){Get-Item -LiteralPath (Join-Path $taskRepo $taskOutside)})
@($taskArtifacts|ForEach-Object{[ordered]@{path=$_.FullName.Substring($taskRepo.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskRoot 'results/artifacts.json') -Encoding utf8
if($taskUnexpected.Count -gt 0){throw "Unexpected source changes: $taskUnexpected"}
Write-Output 'Source/golden boundary verified; no production profile reads'
