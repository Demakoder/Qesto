$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskOut = Join-Path $taskRoot 'build\hardening'
New-Item -ItemType Directory -Force -Path $taskOut | Out-Null
$taskVs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products '*' -property installationPath
if (-not $taskVs) { throw 'MSVC BuildTools required; no automatic installation' }
$taskHeader = Join-Path $env:LOCALAPPDATA 'Pub\Cache\hosted\pub.dev\sqlite3-3.5.2\assets'
# Only compilation, no filesystem mutations delegated across shells.
$taskSetup = Join-Path $taskVs 'VC\Auxiliary\Build\vcvars64.bat'
$taskSource = Join-Path $PSScriptRoot 'fault_shim.c'
Push-Location $taskOut
try {
  & cmd.exe /d /c "call `"$taskSetup`" >nul && cl /nologo /W4 /WX /LD /O2 /I`"$taskHeader`" `"$taskSource`" /link /OUT:qesto_fault_shim.dll"
  if ($LASTEXITCODE -ne 0) { throw 'Fault shim compilation failed' }
} finally { Pop-Location }
