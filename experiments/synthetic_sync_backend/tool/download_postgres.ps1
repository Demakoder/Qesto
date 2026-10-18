# Public binaries only. No financial data or credentials are transmitted.
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRuntime = Join-Path $taskRoot '.runtime'
New-Item -ItemType Directory -Force -Path $taskRuntime | Out-Null
$taskZip = Join-Path $taskRuntime 'postgres.zip'
if (!(Test-Path -LiteralPath $taskZip)) {
  Invoke-WebRequest 'https://sbp.enterprisedb.com/getfile.jsp?fileid=1260616' -OutFile $taskZip
}
# Observed download digest, reproducibility pin; not a vendor signature claim.
$taskExpected = '80379B2C04D51C30225532E0AE04509899141E9957ED096FE749D7FD9DF8F82F'
if ((Get-FileHash -LiteralPath $taskZip -Algorithm SHA256).Hash -ne $taskExpected) {
  throw 'PostgreSQL archive digest differs. Inspect vendor release; do not silently replace the pin.'
}
$taskTarget = Join-Path $taskRuntime 'postgres'
if (!(Test-Path -LiteralPath $taskTarget)) { Expand-Archive -LiteralPath $taskZip -DestinationPath $taskTarget }
& (Join-Path $taskTarget 'pgsql/bin/postgres.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL runtime unavailable' }
