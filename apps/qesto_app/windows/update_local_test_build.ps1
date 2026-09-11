[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfileDirectory,
    [Parameter(Mandatory = $true)][string]$DesktopShortcutPath
)

# Local, explicitly requested test deployments only. Public Windows releases
# still use build_signed_release.ps1 and its mandatory signing verification.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ChildPath([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $parent = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $full.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped the specified directory: $full"
    }
    # Reject junctions/symlinks in the target ancestry as well as file trees.
    $cursor = $full
    while ($cursor.Length -ge $parent.Length) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point is not an update target: $cursor"
            }
        }
        $next = [IO.Path]::GetDirectoryName($cursor)
        if ([string]::IsNullOrEmpty($next) -or $next -eq $cursor) { break }
        $cursor = $next
    }
}

function Copy-VerifiedTree([string]$Source, [string]$Destination, [string[]]$Exclude = @()) {
    $root = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
    $items = @(Get-ChildItem -LiteralPath $root -Force -Recurse)
    if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
        throw "Refusing a tree with reparse points: $root"
    }
    $files = @($items | Where-Object { -not $_.PSIsContainer -and $_.Name -notin $Exclude })
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length + 1)
        $target = Join-Path $Destination $relative
        Assert-ChildPath $target $Destination
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
        if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
            throw "Copy verification failed: $relative"
        }
    }
    Write-Output "Verified $($files.Count) files: $Destination"
}

$profileRoot = [IO.Path]::GetFullPath($ProfileDirectory).TrimEnd('\')
$currentProfile = [Environment]::GetFolderPath('UserProfile').TrimEnd('\')
if (-not $profileRoot.Equals($currentProfile, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Run the local updater as the actual Qesto user, not a sandbox or another Windows account.'
}
$appRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $appRoot 'build\windows\x64\runner\Release'
$programsRoot = Join-Path $profileRoot 'AppData\Local\Programs'
$installation = Join-Path $programsRoot 'Qesto'
$backupRoot = Join-Path $profileRoot 'AppData\Local\Qesto\Backups'
Assert-ChildPath $source $appRoot
Assert-ChildPath $installation $profileRoot
Assert-ChildPath $DesktopShortcutPath $profileRoot
Assert-ChildPath $backupRoot $profileRoot
if (-not (Test-Path -LiteralPath (Join-Path $installation 'qesto.exe'))) {
    throw "Existing installation was not found: $installation"
}
if (Get-Process -Name qesto -ErrorAction SilentlyContinue) {
    throw 'Close Qesto before updating. No process will be forcibly terminated.'
}
$newExe = Get-Item -LiteralPath (Join-Path $source 'qesto.exe')
$oldExe = Get-Item -LiteralPath (Join-Path $installation 'qesto.exe')
$version = $newExe.VersionInfo.FileVersion
if ($version -notmatch '^\d+\.\d+\.\d+\+\d+$' -or
    $newExe.VersionInfo.ProductName -ne 'Qesto' -or
    $newExe.VersionInfo.CompanyName -ne 'ru.qesto') {
    throw 'Invalid Qesto version/identity; the secure-storage location must not change.'
}
foreach ($required in @('qesto.dll','flutter_windows.dll','libcef.dll','webview_cef_plugin.dll','data\app.so','data\icudtl.dat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $required))) {
        throw "Incomplete runtime: $required"
    }
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backup = Join-Path $backupRoot "$version-$stamp"
$staging = Join-Path $programsRoot "Qesto.staging-$version-$stamp"
$oldBuild = Join-Path $backup 'previous-app'
$failedBuild = Join-Path $backup 'failed-new-app'
Assert-ChildPath $backup $backupRoot
Assert-ChildPath $staging $programsRoot
Assert-ChildPath $oldBuild $backup
Assert-ChildPath $failedBuild $backup
if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $staging)) {
    throw 'Backup/staging path is already occupied; no files were replaced.'
}
New-Item -ItemType Directory -Path $backup -Force | Out-Null

$dataSources = @(
    @{ Source = (Join-Path $profileRoot 'AppData\Roaming\Qesto'); Name = 'financial-store' },
    @{ Source = (Join-Path $profileRoot 'AppData\Roaming\ru.qesto\Qesto'); Name = 'encrypted-key-store' },
    @{ Source = (Join-Path $profileRoot 'AppData\Local\Qesto\BankBrowser'); Name = 'bank-browser' }
)
foreach ($data in $dataSources) {
    Assert-ChildPath $data.Source $profileRoot
    if (Test-Path -LiteralPath $data.Source) {
        Copy-VerifiedTree $data.Source (Join-Path $backup $data.Name)
    }
}
$shell = New-Object -ComObject WScript.Shell
$shortcutPaths = @($DesktopShortcutPath,
    (Join-Path $profileRoot 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Qesto\Qesto.lnk'))
$shortcuts = @()
foreach ($linkPath in $shortcutPaths) {
    if (-not (Test-Path -LiteralPath $linkPath)) { continue }
    Assert-ChildPath $linkPath $profileRoot
    $link = $shell.CreateShortcut($linkPath)
    if ([IO.Path]::GetFileName($link.TargetPath) -ine 'qesto.exe') {
        throw "Shortcut is not a Qesto launcher: $linkPath"
    }
    $saved = Join-Path $backup "shortcut-$($shortcuts.Count).lnk"
    Copy-Item -LiteralPath $linkPath -Destination $saved
    $shortcuts += @{ Path = $linkPath; Backup = $saved; Arguments = $link.Arguments }
}
if ($shortcuts.Count -eq 0) { throw 'No existing Qesto shortcut was found.' }

$excluded = @('qesto.exp','qesto.lib','debug.log','native_assets.json',
    'flutter_inappwebview_windows_plugin.dll','WebView2Loader.dll')
Copy-VerifiedTree $source $staging $excluded
if (Get-Process -Name qesto -ErrorAction SilentlyContinue) {
    throw 'Qesto was opened during staging; update stopped before replacing the application.'
}

$oldMoved = $false
$newMoved = $false
try {
    # All absolute move targets were bounded and reparse-checked above.
    Move-Item -LiteralPath $installation -Destination $oldBuild
    $oldMoved = $true
    Move-Item -LiteralPath $staging -Destination $installation
    $newMoved = $true
    foreach ($shortcut in $shortcuts) {
        $link = $shell.CreateShortcut($shortcut.Path)
        $link.TargetPath = Join-Path $installation 'qesto.exe'
        $link.WorkingDirectory = $installation
        $link.IconLocation = (Join-Path $installation 'qesto.dll') + ',0'
        $link.Arguments = $shortcut.Arguments
        $link.Save()
        $verified = $shell.CreateShortcut($shortcut.Path)
        if ($verified.TargetPath -ine (Join-Path $installation 'qesto.exe')) {
            throw 'Shortcut verification failed.'
        }
    }
    $manifest = @{
        Version = $version; PreviousVersion = $oldExe.VersionInfo.FileVersion
        CreatedAt = (Get-Date).ToString('o'); Installation = $installation
        PreviousBuild = $oldBuild; Shortcuts = $shortcuts
        ExeSha256 = (Get-FileHash -LiteralPath (Join-Path $installation 'qesto.exe') -Algorithm SHA256).Hash
        Note = 'Local test deployment; not an Authenticode-signed public release. User data left in place.'
    }
    [IO.File]::WriteAllText((Join-Path $backup 'update-manifest.json'), ($manifest | ConvertTo-Json -Depth 5))
    Write-Output "Updated Qesto $version. Backup: $backup"
} catch {
    if ($newMoved) { Move-Item -LiteralPath $installation -Destination $failedBuild }
    if ($oldMoved) { Move-Item -LiteralPath $oldBuild -Destination $installation }
    foreach ($shortcut in $shortcuts) {
        Copy-Item -LiteralPath $shortcut.Backup -Destination $shortcut.Path -Force
    }
    throw
}
