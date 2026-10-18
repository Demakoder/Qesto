$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskDart='C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
Push-Location $taskRoot
try {
  foreach($taskCount in @(1000,10000,50000)) {
    foreach($taskMode in @('domain-only','journal','full-diff')) {
      & $taskDart --packages=.dart_tool/package_config.json bin/benchmark.dart $taskMode $taskCount
      if($LASTEXITCODE -ne 0){throw "Benchmark failed: $taskMode $taskCount"}
    }
  }
  foreach($taskMode in @('domain-only','journal','full-diff')) {
    & $taskDart --enable-vm-service=0 --packages=.dart_tool/package_config.json bin/benchmark.dart $taskMode 10000 --allocation
    if($LASTEXITCODE -ne 0){throw "Allocation failed: $taskMode"}
  }
} finally {Pop-Location}
