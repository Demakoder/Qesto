[CmdletBinding()]
param(
    [string]$CertificateThumbprint = $env:QESTO_WINDOWS_CERT_SHA1,
    [string]$TimestampUrl = 'http://timestamp.digicert.com',
    [string]$FlutterCommand = 'flutter',
    [string]$InnoCompiler
)

$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $Command"
    }
}

function Find-SignTool {
    $fromPath = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) {
        return $fromPath.Source
    }

    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $sdkRoot) {
        $candidate = Get-ChildItem -LiteralPath $sdkRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate
        }
    }
    throw 'signtool.exe was not found. Install the Windows SDK signing tools.'
}

function Find-InnoCompiler {
    if (-not [string]::IsNullOrWhiteSpace($InnoCompiler)) {
        if (-not (Test-Path -LiteralPath $InnoCompiler)) {
            throw "Inno Setup compiler was not found: $InnoCompiler"
        }
        return (Resolve-Path -LiteralPath $InnoCompiler).Path
    }

    $fromPath = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) {
        return $fromPath.Source
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw 'ISCC.exe was not found. Install Inno Setup 6 or pass -InnoCompiler.'
}

$normalizedThumbprint = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
if ($normalizedThumbprint -notmatch '^[0-9A-F]{40}$') {
    throw 'Set QESTO_WINDOWS_CERT_SHA1 to the 40-character SHA-1 thumbprint of the Authenticode certificate.'
}
if ($TimestampUrl -notmatch '^https?://') {
    throw 'TimestampUrl must use HTTP or HTTPS.'
}

$certificate = Get-ChildItem -Path "Cert:\CurrentUser\My\$normalizedThumbprint" -ErrorAction SilentlyContinue
if ($null -eq $certificate) {
    $certificate = Get-ChildItem -Path "Cert:\LocalMachine\My\$normalizedThumbprint" -ErrorAction SilentlyContinue
}
if ($null -eq $certificate -or -not $certificate.HasPrivateKey) {
    throw 'The Authenticode certificate was not found or has no accessible private key.'
}
$now = Get-Date
if ($certificate.NotBefore -gt $now -or $certificate.NotAfter -le $now) {
    throw 'The Authenticode certificate is not currently valid.'
}

$appRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $appRoot 'pubspec.yaml'
$versionMatch = Select-String -LiteralPath $pubspecPath -Pattern '^version:\s*([^+\s]+)' |
    Select-Object -First 1
if ($null -eq $versionMatch) {
    throw 'Unable to read the application version from pubspec.yaml.'
}
$appVersion = $versionMatch.Matches[0].Groups[1].Value
$signTool = Find-SignTool
$iscc = Find-InnoCompiler

Push-Location $appRoot
try {
    Invoke-Checked -Command $FlutterCommand -Arguments @('build', 'windows', '--release')

    $releaseDirectory = Join-Path $appRoot 'build\windows\x64\runner\Release'
    $applicationPath = Join-Path $releaseDirectory 'qesto.exe'
    if (-not (Test-Path -LiteralPath $applicationPath)) {
        throw "Release executable was not produced: $applicationPath"
    }

    $signArguments = @(
        'sign', '/sha1', $normalizedThumbprint,
        '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256'
    )
    $portableExecutables = Get-ChildItem -LiteralPath $releaseDirectory -Recurse -File |
        Where-Object { $_.Extension -in @('.exe', '.dll') }
    if ($portableExecutables.Count -eq 0) {
        throw "No Windows executables were produced in: $releaseDirectory"
    }
    foreach ($portableExecutable in $portableExecutables) {
        Invoke-Checked -Command $signTool -Arguments ($signArguments + $portableExecutable.FullName)
        Invoke-Checked -Command $signTool -Arguments @(
            'verify', '/pa', '/all', $portableExecutable.FullName
        )
    }

    $escapedSignTool = '"' + $signTool + '"'
    $innoSignCommand = "$escapedSignTool sign /sha1 $normalizedThumbprint /fd SHA256 /tr `"$TimestampUrl`" /td SHA256 `$f"
    $installerScript = Join-Path $PSScriptRoot 'installer\qesto.iss'
    Invoke-Checked -Command $iscc -Arguments @(
        "/DAppVersion=$appVersion",
        "/Sqesto=$innoSignCommand",
        $installerScript
    )

    $installerPath = Join-Path $appRoot "build\installer\Qesto-Setup-$appVersion.exe"
    if (-not (Test-Path -LiteralPath $installerPath)) {
        throw "Signed installer was not produced: $installerPath"
    }
    Invoke-Checked -Command $signTool -Arguments @('verify', '/pa', '/all', $installerPath)
    Write-Output "Signed Qesto release is ready: $installerPath"
}
finally {
    Pop-Location
}
