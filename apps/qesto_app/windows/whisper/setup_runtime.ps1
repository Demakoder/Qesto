$ErrorActionPreference = 'Stop'

$whisperVersion = 'v1.9.2'
$modelName = 'ggml-small-q5_1.bin'
$modelSha256 = 'AE85E4A935D7A567BD102FE55AFC16BB595BDB618E11B2FC7591BC08120411BB'
$runtimeDirectory = Join-Path $PSScriptRoot 'runtime'
$archivePath = Join-Path $env:TEMP "qesto-whisper-$whisperVersion-x64.zip"
$extractDirectory = Join-Path $env:TEMP ("qesto-whisper-" + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null

if (-not (Test-Path $archivePath)) {
    Invoke-WebRequest `
        -Uri "https://github.com/ggml-org/whisper.cpp/releases/download/$whisperVersion/whisper-bin-x64.zip" `
        -OutFile $archivePath
}

Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDirectory
$releaseDirectory = Join-Path $extractDirectory 'Release'
$requiredNames = @(
    'whisper-stream.exe',
    'whisper-cli.exe',
    'whisper.dll',
    'ggml.dll',
    'ggml-base.dll',
    'SDL2.dll'
)

Get-ChildItem -LiteralPath $releaseDirectory |
    Where-Object {
        $_.Name -in $requiredNames -or $_.Name -like 'ggml-cpu-*.dll'
    } |
    Copy-Item -Destination $runtimeDirectory -Force

$modelPath = Join-Path $runtimeDirectory $modelName
if (-not (Test-Path $modelPath) -or
    (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash -ne $modelSha256) {
    Invoke-WebRequest `
        -Uri "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$modelName?download=true" `
        -OutFile $modelPath
}

$actualHash = (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash
if ($actualHash -ne $modelSha256) {
    throw "Unexpected SHA256 for $modelName`: $actualHash"
}

Invoke-WebRequest `
    -Uri "https://raw.githubusercontent.com/ggml-org/whisper.cpp/$whisperVersion/LICENSE" `
    -OutFile (Join-Path $runtimeDirectory 'LICENSE-whisper.cpp.txt')

Write-Output "whisper.cpp $whisperVersion runtime is ready: $runtimeDirectory"
