$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskFiles=@(Get-ChildItem -LiteralPath $taskRoot -Recurse -File | Where-Object {
  $_.FullName -notmatch '[\\/](\.dart_tool|build|\.runtime)[\\/]' -and $_.Name -ne 'artifact-manifest.json'
})
foreach($taskRelative in @(
  'packages/qesto_synoball_core/lib/core/synoball_core.dart',
  'packages/qesto_synoball_core/lib/core/effects_journal.dart',
  'packages/qesto_synoball_core/lib/core/owned_records.dart',
  'packages/qesto_synoball_core/test/runtime_contract_test.dart',
  'docs/sync/2026-10-16/Core_Owned_Effects_Journal_Report.md')) {
  $taskFiles += Get-Item -LiteralPath (Join-Path $taskRepo $taskRelative)
}
$taskEntries=@($taskFiles | Sort-Object FullName | ForEach-Object {
  [ordered]@{path=$_.FullName.Substring($taskRepo.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
[ordered]@{created_at_utc=[DateTime]::UtcNow.ToString('o');scope='Stage 4e code, docs and synthetic results; no profiles';files=$taskEntries} |
  ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$taskRoot/results/artifact-manifest.json" -Encoding utf8
Write-Output "Recorded $($taskEntries.Count) Stage 4e artifact hashes"
