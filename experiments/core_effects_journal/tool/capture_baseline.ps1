$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
New-Item -ItemType Directory -Path "$taskRoot/results" -Force | Out-Null
$taskPath="$taskRoot/results/source-baseline.json"
if(Test-Path -LiteralPath $taskPath){throw 'Baseline already exists'}
$taskHashes=[ordered]@{}
foreach($taskSub in @('apps/qesto_app/lib','apps/qesto_app/test','packages/qesto_synoball_core','experiments/incremental_domain_execution/lib','experiments/incremental_sync_performance/lib','experiments/synthetic_sync_backend/lib')) {
  Get-ChildItem -LiteralPath "$taskRepo/$taskSub" -File -Recurse | Where-Object {$_.FullName -notmatch '[\\/](\.dart_tool|build|\.runtime)[\\/]'} | ForEach-Object {
    $taskHashes[$_.FullName.Substring($taskRepo.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
}
$taskHashes | ConvertTo-Json | Set-Content -LiteralPath $taskPath -Encoding utf8
Write-Output "Captured $($taskHashes.Count) source/golden hashes, no profile reads"
