$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskBaseline=Get-Content -LiteralPath "$taskRoot/results/source-baseline.json" -Raw | ConvertFrom-Json
$taskAllowed=@('packages/qesto_synoball_core/lib/core/synoball_core.dart','packages/qesto_synoball_core/test/runtime_contract_test.dart')
$taskChanged=@(); $taskMissing=@(); $taskUnexpected=@()
foreach($taskProperty in $taskBaseline.PSObject.Properties) {
  $taskFile=Join-Path $taskRepo $taskProperty.Name
  if(!(Test-Path -LiteralPath $taskFile)) {$taskMissing += $taskProperty.Name; continue}
  $taskHash=(Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash
  if($taskHash -ne $taskProperty.Value) {
    $taskChanged += [ordered]@{path=$taskProperty.Name;before=$taskProperty.Value;after=$taskHash}
    if($taskAllowed -notcontains $taskProperty.Name){$taskUnexpected += $taskProperty.Name}
  }
}
$taskResult=[ordered]@{
  checked_at_utc=[DateTime]::UtcNow.ToString('o')
  baseline_files=@($taskBaseline.PSObject.Properties).Count
  changed=$taskChanged;missing=$taskMissing;unexpected=$taskUnexpected
  scope='Source and golden files only. No user profiles read, fingerprinted or written.'
  passed=($taskMissing.Count -eq 0 -and $taskUnexpected.Count -eq 0)
}
$taskResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$taskRoot/results/source-verification.json" -Encoding utf8
$taskResult | ConvertTo-Json -Depth 12
if(!$taskResult.passed){throw 'Unexpected source changes: inspect before continuing'}
