$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo=Split-Path (Split-Path $taskRoot -Parent) -Parent
$taskDart='C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$taskFlutter='C:\Users\ARM\development\flutter\bin\cache\flutter_tools.snapshot'
$taskTest='C:\Users\ARM\AppData\Local\Pub\Cache\hosted\pub.dev\test-1.31.0\bin\test.dart'
function Check([string]$Directory,[string[]]$Arguments,[string]$Log) {
  Push-Location $Directory
  try {
    Write-Output "Running $Log"
    & $taskDart @Arguments > "$taskRoot/results/$Log"
    if($LASTEXITCODE -ne 0){throw "Failed $Log"}
  } finally {Pop-Location}
}
Check $taskRoot @('tool/configure_app_seam.dart') 'configure.txt'
Check $taskRoot @('--packages=.dart_tool/package_config.json',$taskTest,'test','--reporter=json') 'journal-after.jsonl'
Check "$taskRepo/packages/qesto_synoball_core" @('test','--reporter=json') 'shared-after.jsonl'
Check "$taskRepo/experiments/incremental_domain_execution" @('tool/configure_app_seam.dart') 'configure-4d.txt'
Check "$taskRepo/experiments/incremental_domain_execution" @('--packages=.dart_tool/package_config.json',$taskTest,'test/domain_owner_test.dart','test/bounded_executor_test.dart','test/streaming_digest_test.dart','--reporter=json') '4d-regression.jsonl'
Check "$taskRepo/apps/qesto_app" @($taskFlutter,'test','--no-pub',
  'test/synoball_core_test.dart','test/synoball_safety_test.dart',
  'test/shared_synoball_core_compatibility_test.dart','test/classification_test.dart',
  'test/financial_write_safety_test.dart','test/transaction_trash_test.dart',
  'test/user_financial_data_codec_test.dart','test/storage_recovery_safety_test.dart',
  'test/recurring_detection_test.dart','test/recurring_pipeline_test.dart',
  'test/desktop_shell_test.dart','--reporter=json') 'app-regression.jsonl'
Check "$taskRepo/packages/qesto_synoball_core" @('analyze') 'analyze-shared.txt'
Check $taskRoot @('analyze') 'analyze-experiment.txt'
Check "$taskRepo/experiments/incremental_domain_execution" @('analyze') 'analyze-4d.txt'
