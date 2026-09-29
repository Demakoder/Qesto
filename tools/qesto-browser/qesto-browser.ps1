param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $CommandArgs
)

$ErrorActionPreference = 'Stop'
$descriptorPath = Join-Path $env:LOCALAPPDATA 'Qesto\dev\session.json'
if (-not (Test-Path -LiteralPath $descriptorPath)) {
  [Console]::Error.WriteLine('No active Qesto Bank Browser DEV session.')
  exit 2
}

$descriptor = Get-Content -LiteralPath $descriptorPath -Raw | ConvertFrom-Json
if (-not $descriptor.bridgePort -or -not $descriptor.token) {
  [Console]::Error.WriteLine('Invalid Qesto DEV session descriptor.')
  exit 2
}

if ($descriptor.pid) {
  try { Get-Process -Id ([int]$descriptor.pid) -ErrorAction Stop | Out-Null }
  catch {
    Remove-Item -LiteralPath $descriptorPath -Force -ErrorAction SilentlyContinue
    [Console]::Error.WriteLine('No active Qesto Bank Browser DEV session.')
    exit 2
  }
}

if (-not $CommandArgs -or $CommandArgs.Count -eq 0) {
  Write-Host 'Usage: qesto-browser <command> [arguments]'
  Write-Host 'Commands: status, snapshot, dom, text, query, query-all, attributes, links, buttons, elements, find, routes, navigate, back, forward, reload, click, scroll, scroll-to, wait, wait-url, wait-text, wait-stable-dom, mutations, storage, run-extractor, detect-page, current-url, title, pages'
  exit 1
}

$command = $CommandArgs[0]
$argsMap = @{}
$positionals = New-Object System.Collections.Generic.List[string]
for ($i = 1; $i -lt $CommandArgs.Count; $i++) {
  $arg = $CommandArgs[$i]
  if ($arg -like '--*') {
    $key = $arg.Substring(2)
    if ($i + 1 -lt $CommandArgs.Count -and $CommandArgs[$i + 1] -notlike '--*') {
      $argsMap[$key] = $CommandArgs[++$i]
    } else {
      $argsMap[$key] = $true
    }
  } else {
    $positionals.Add($arg)
  }
}

switch ($command) {
  'dom' { if (-not $argsMap.ContainsKey('selector') -and $positionals.Count -gt 0) { $argsMap.selector = $positionals[0] } }
  'text' { if (-not $argsMap.ContainsKey('selector') -and $positionals.Count -gt 0) { $argsMap.selector = $positionals[0] } }
  'query' { if (-not $argsMap.ContainsKey('selector') -and $positionals.Count -gt 0) { $argsMap.selector = $positionals[0] } }
  'query-all' { if (-not $argsMap.ContainsKey('selector') -and $positionals.Count -gt 0) { $argsMap.selector = $positionals[0] } }
  'attributes' { if (-not $argsMap.ContainsKey('selector') -and $positionals.Count -gt 0) { $argsMap.selector = $positionals[0] } }
  'click' { if (-not $argsMap.ContainsKey('selector') -and $positionals.Count -gt 0) { $argsMap.selector = $positionals[0] } }
  'scroll-to' { if (-not $argsMap.ContainsKey('selector') -and $positionals.Count -gt 0) { $argsMap.selector = $positionals[0] } }
  'find' { if (-not $argsMap.ContainsKey('text') -and $positionals.Count -gt 0) { $argsMap.text = $positionals[0] } }
  'navigate' { if (-not $argsMap.ContainsKey('url') -and $positionals.Count -gt 0) { $argsMap.url = $positionals[0] } }
  'scroll' { if (-not $argsMap.ContainsKey('direction') -and $positionals.Count -gt 0) { $argsMap.direction = $positionals[0] } }
  'wait' {
    if (-not $argsMap.ContainsKey('selector') -and $positionals.Count -gt 0) { $argsMap.selector = $positionals[0] }
  }
  'wait-url' { if (-not $argsMap.ContainsKey('url') -and $positionals.Count -gt 0) { $argsMap.url = $positionals[0] } }
  'wait-text' { if (-not $argsMap.ContainsKey('text') -and $positionals.Count -gt 0) { $argsMap.text = $positionals[0] } }
  'elements' {
    if (-not $argsMap.ContainsKey('kind')) {
      if ($argsMap.ContainsKey('data-testid')) { $argsMap.kind = 'data-testid' }
      elseif ($argsMap.ContainsKey('data-test')) { $argsMap.kind = 'data-test' }
      elseif ($argsMap.ContainsKey('id')) { $argsMap.kind = 'id' }
    }
  }
  'storage' {
    if (-not $argsMap.ContainsKey('area') -and $positionals.Count -gt 0) { $argsMap.area = $positionals[0] }
  }
  'run-extractor' {
    if (-not $argsMap.ContainsKey('script') -and $positionals.Count -gt 0) {
      $argsMap.script = Get-Content -LiteralPath $positionals[0] -Raw
    }
  }
}

$payload = @{ command = $command; args = $argsMap } | ConvertTo-Json -Depth 8
$payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$headers = @{ Authorization = 'Bearer ' + [string]$descriptor.token }
$uri = 'http://127.0.0.1:' + [int]$descriptor.bridgePort + '/v1/command'
try {
  $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $payloadBytes -ContentType 'application/json; charset=utf-8'
  if ($response.ok -eq $false) {
    $response | ConvertTo-Json -Depth 12
    exit 3
  }
  if ($null -eq $response.result) {
    'null'
  } else {
    ConvertTo-Json -InputObject $response.result -Depth 20
  }
} catch {
  Write-Error $_.Exception.Message
  exit 4
}
