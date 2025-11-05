# Enforce strict parsing and fail fast.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared helpers.
. "$PSScriptRoot\env.ps1"

# Initialize derived environment variables.
Initialize-Env

# Pin the repo root to this script’s folder.
$root = $PSScriptRoot

# Load the mapping file once.
$map  = Get-Content (Join-Path $root 'map.json') -Raw | ConvertFrom-Json

# Track missing items for exit code.
$miss = 0

# Emit a simple exists/missing sentence.
function Say([string]$prefix, [bool]$ok) {
  if ($ok) { Write-Host ("    {0}: Exists." -f $prefix) }
  else { $global:miss++; Write-Host ("    {0}: Missing." -f $prefix) }
}

# Walk each program section and describe status per item.
foreach ($app in $map.PSObject.Properties) {
  $name = $app.Name
  $val  = $app.Value
  Write-Host "== $name =="

  # Report files with live and backup status.
  foreach ($m in ($val.files | ForEach-Object { $_ })) {
    $livePath = Resolve-EnvRefs $m.live
    $bakPath  = Resolve-RepoPath $root $m.backup
    $liveOk = if ($livePath) { Test-Path $livePath -PathType Leaf } else { $false }
    $bakOk  = if ($bakPath)  { Test-Path $bakPath  -PathType Leaf } else { $false }
    Write-Host ("  File: {0}" -f $m.backup)
    Say "Live" $liveOk
    Say "Backup" $bakOk
    if ($livePath) { Write-Host ("    Live path: {0}" -f $livePath) }
  }

  # Report directories with live and backup status.
  foreach ($m in ($val.dirs | ForEach-Object { $_ })) {
    $livePath = Resolve-EnvRefs $m.live
    $bakPath  = Resolve-RepoPath $root $m.backup
    $liveOk = if ($livePath) { Test-Path $livePath -PathType Container } else { $false }
    $bakOk  = if ($bakPath)  { Test-Path $bakPath  -PathType Container } else { $false }
    Write-Host ("  Dir:  {0}" -f $m.backup)
    Say "Live" $liveOk
    Say "Backup" $bakOk
    if ($livePath) { Write-Host ("    Live path: {0}" -f $livePath) }
  }

  # Report registry assets from repo only.
  foreach ($rel in ($val.reg | ForEach-Object { $_ })) {
    $bakPath = Resolve-RepoPath $root $rel
    $bakOk   = if ($bakPath) { Test-Path $bakPath -PathType Leaf } else { $false }
    Write-Host ("  Reg:  {0}" -f $rel)
    Say "Backup" $bakOk
  }

  # List manual items that need human action.
  foreach ($item in ($val.manual | ForEach-Object { $_ })) {
    Write-Host ("  Manual: {0}. Action required." -f $item)
  }

  Write-Host
}

# Exit with nonzero code if anything is missing.
if ($miss -gt 0) {
  Write-Host ("Summary: {0} missing item(s)." -f $miss)
  exit 2
} else {
  Write-Host "Summary: all present."
  exit 0
}
