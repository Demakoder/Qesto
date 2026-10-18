$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskResults=Join-Path $taskRoot 'results'
New-Item -ItemType Directory -Path $taskResults -Force | Out-Null
$taskBaseline=Join-Path $taskResults 'source-baseline.json'
if(Test-Path -LiteralPath $taskBaseline){throw 'Never overwrite existing source baseline'}
$taskHashes=[ordered]@{}
foreach($taskSub in @('apps/qesto_app/lib','apps/qesto_app/test','packages/qesto_synoball_core','experiments/storage_feasibility/lib','experiments/encrypted_client_sync/lib','experiments/windows_integration_boundary/lib','experiments/windows_synthetic_ui_sync/lib','experiments/synthetic_sync_backend/lib','experiments/incremental_sync_performance')) {
  Get-ChildItem -LiteralPath (Join-Path $taskRepo $taskSub) -Recurse -File | Where-Object {$_.FullName -notmatch '[\\/](\.dart_tool|build|\.runtime|\.git)[\\/]'} | ForEach-Object {
    $taskRelative=$_.FullName.Substring($taskRepo.Length+1).Replace('\','/')
    $taskHashes[$taskRelative]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
}
$taskHashes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskBaseline -Encoding utf8
foreach($taskEvidence in @('summary.json','flutter-baseline-1000-10000.json','flutter-incremental-1000-10000.json','flutter-50k.jsonl')) {
  Copy-Item -LiteralPath (Join-Path $taskRepo "experiments/incremental_sync_performance/results/$taskEvidence") -Destination (Join-Path $taskResults "baseline-4c-$taskEvidence")
}
Write-Output "Captured $($taskHashes.Count) hashes and Stage 4c benchmarks"
