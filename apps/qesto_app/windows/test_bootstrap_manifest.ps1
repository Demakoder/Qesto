param(
    [Parameter(Mandatory=$true)][string]$BootstrapPath,
    [Parameter(Mandatory=$true)][string]$ResourceSourcePath,
    [Parameter(Mandatory=$true)][string]$ManifestToolPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Only a copy is patched. No app launch, browser profile or user settings access.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('qesto-manifest-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$exe = Join-Path $temp 'qesto.exe'
Copy-Item -LiteralPath (Resolve-Path -LiteralPath $BootstrapPath).Path -Destination $exe
function Read-Manifest([string]$Name) {
    $output = Join-Path $temp $Name
    & $ManifestToolPath '-nologo' "-inputresource:$exe;#1" "-out:$output"
    if ($LASTEXITCODE -ne 0) { throw 'Manifest extraction failed' }
    return [xml](Get-Content -LiteralPath $output -Raw)
}
$before = Read-Manifest 'before.xml'
& (Join-Path $PSScriptRoot 'patch_cef_bootstrap_resources.ps1') -BootstrapPath $exe -ResourceSourcePath $ResourceSourcePath
$after = Read-Manifest 'after.xml'
$dpi = @($after.SelectNodes("//*[local-name()='dpiAwareness']"))
if ($dpi.Count -ne 1 -or $dpi[0].InnerText -ne 'PerMonitorV2') {
    throw 'Executable must declare exactly one PerMonitorV2 setting'
}
foreach ($name in @('trustInfo', 'dependency', 'compatibility', 'assemblyIdentity')) {
    $old = @($before.SelectNodes("/*/*[local-name()='$name']") | ForEach-Object OuterXml) -join ''
    $new = @($after.SelectNodes("/*/*[local-name()='$name']") | ForEach-Object OuterXml) -join ''
    if ($old -cne $new) { throw "Bootstrap $name was modified" }
}
[QestoVersionResourcePatch]::MergeDpiManifest([IO.Path]::GetFullPath($ResourceSourcePath), $exe)
$twice = Read-Manifest 'twice.xml'
if ($after.OuterXml -cne $twice.OuterXml) { throw 'Manifest merge is not idempotent' }
Write-Output "PASS: executable DPI, preserved bootstrap declarations, idempotent merge. Fixtures: $temp"
