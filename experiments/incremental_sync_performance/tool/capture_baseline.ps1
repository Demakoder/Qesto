$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskResults=Join-Path $taskRoot 'results'
New-Item -ItemType Directory -Path $taskResults -Force | Out-Null
$taskBaseline=Join-Path $taskResults 'source-baseline.json'
if(Test-Path -LiteralPath $taskBaseline){throw 'Baseline exists; never overwrite it'}
$taskHashes=[ordered]@{}
foreach($taskSub in @('apps/qesto_app/lib','apps/qesto_app/test','packages/qesto_synoball_core','experiments/storage_feasibility/lib','experiments/encrypted_client_sync/lib','experiments/windows_integration_boundary/lib','experiments/windows_synthetic_ui_sync/lib','experiments/synthetic_sync_backend/lib')) {
  Get-ChildItem -LiteralPath (Join-Path $taskRepo $taskSub) -Recurse -File | Where-Object {$_.FullName -notmatch '[\\/](\.dart_tool|build|\.git)[\\/]'} | ForEach-Object {
    $taskRelative=$_.FullName.Substring($taskRepo.Length+1).Replace('\','/')
    $taskHashes[$taskRelative]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
}
$taskHashes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskBaseline -Encoding utf8
foreach($taskEvidence in @('summary.json','ui-sync-benchmarks.json','semantic-parity.json','controller-semantic-gate.json')) {
  Copy-Item -LiteralPath (Join-Path $taskRepo "experiments/windows_synthetic_ui_sync/results/$taskEvidence") -Destination (Join-Path $taskResults "baseline-4b-$taskEvidence")
}
Write-Output "Preserved $($taskHashes.Count) source hashes and original Stage 4b evidence"
