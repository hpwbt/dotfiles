# Enforce strict parsing and fail fast.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared helpers.
. "$PSScriptRoot\env.ps1"

# Initialize derived environment variables.
Initialize-Env

# Pin the repo root to this script’s folder.
$root = $PSScriptRoot

# Load map once.
$map = Get-Content (Join-Path $root "map.json") -Raw | ConvertFrom-Json

# Install one file live.
function Install-File($liveSpec,$backupRel) {
  $live  = Resolve-EnvRefs $liveSpec
  $src   = Resolve-RepoPath $root $backupRel
  Write-Host "File: $backupRel"
  Write-Host "  Copy to $live"
  New-Item -ItemType Directory -Force -Path (Split-Path $live) | Out-Null
  Copy-Item $src $live -Force
}

# Install one dir live.
function Install-Dir($liveSpec,$backupRel) {
  $live  = Resolve-EnvRefs $liveSpec
  $src   = Resolve-RepoPath $root $backupRel
  Write-Host "Dir:  $backupRel"
  Write-Host "  Replace $live"
  if (Test-Path $live) { Remove-Item $live -Recurse -Force }
  New-Item -ItemType Directory -Force -Path (Split-Path $live) | Out-Null
  Copy-Item $src $live -Recurse -Force
}

# Import one reg file.
function Install-Reg($backupRel) {
  $src = Resolve-RepoPath $root $backupRel
  Write-Host "Reg:  $backupRel"
  Write-Host "  Import"
  Start-Process reg.exe -ArgumentList @("import","`"$src`"") -Verb RunAs -Wait
}

# Execute each program section.
foreach ($app in $map.PSObject.Properties) {
  Write-Host "== $($app.Name) =="

  foreach ($m in ($app.Value.files | ForEach-Object { $_ })) {
    Install-File $m.live $m.backup
  }

  foreach ($m in ($app.Value.dirs | ForEach-Object { $_ })) {
    Install-Dir $m.live $m.backup
  }

  foreach ($rel in ($app.Value.reg | ForEach-Object { $_ })) {
    Install-Reg $rel
  }

  foreach ($item in ($app.Value.manual | ForEach-Object { $_ })) {
    Write-Host "Manual: $item"
  }

  Write-Host
}

Write-Host "Done."
