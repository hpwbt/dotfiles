# Enforce strict parsing and fail fast.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Expand $env:VARS and normalize slashes.
function Resolve-EnvRefs([string]$s) {
  if (-not $s) { return $null }
  $t = $s -replace '/', '\'
  [regex]::Replace($t, '\$env:([A-Za-z_][A-Za-z0-9_]*)', {
    param($m) [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
  })
}

# Turn a repo-relative path into an absolute path.
function Resolve-RepoPath([string]$root, [string]$rel) {
  if (-not $rel) { return $null }
  Join-Path $root ($rel -replace '/', '\')
}

# Locate the active LibreWolf profile by reading profiles.ini.
function Get-LibreWolfProfilePath {
  $ini = Join-Path $env:APPDATA 'LibreWolf\profiles.ini'
  if (-not (Test-Path $ini -PathType Leaf)) { return $null }
  $content  = Get-Content -Raw $ini -Encoding UTF8
  $sections = ($content -split '\r?\n\r?\n') | Where-Object { $_ -match '^\[Profile' }
  $pick = $sections | Where-Object { $_ -match '^Default=1' } | Select-Object -First 1
  if (-not $pick) {
    $pick = $sections | Select-Object -First 1
  }
  if (-not $pick) { return $null }
  $pathLine = ($pick -split '\r?\n') | Where-Object { $_ -like 'Path=*' } | Select-Object -First 1
  if (-not $pathLine) { return $null }
  $rel = $pathLine.Split('=',2)[1]
  $base = Join-Path $env:APPDATA 'LibreWolf'
  $full = if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $base $rel }
  Resolve-EnvRefs $full
}

# Publish derived environment variables used in map paths.
function Initialize-Env {
  if (-not $env:LIBREWOLF) {
    $p = Get-LibreWolfProfilePath
    if ($p) { $env:LIBREWOLF = $p }
  }
}

# Flatten map.json into a plan of work items.
function Build-Plan([object]$map, [string]$root) {
  foreach ($app in $map.PSObject.Properties) {
    $name = $app.Name
    $val  = $app.Value

    foreach ($m in ($val.files | ForEach-Object { $_ })) {
      [pscustomobject]@{
        App      = $name
        Kind     = 'file'
        LivePath = Resolve-EnvRefs $m.live
        RepoPath = Resolve-RepoPath $root $m.backup
        Label    = $m.backup
      }
    }
    foreach ($m in ($val.dirs | ForEach-Object { $_ })) {
      [pscustomobject]@{
        App      = $name
        Kind     = 'dir'
        LivePath = Resolve-EnvRefs $m.live
        RepoPath = Resolve-RepoPath $root $m.backup
        Label    = $m.backup
      }
    }
    foreach ($rel in ($val.reg | ForEach-Object { $_ })) {
      [pscustomobject]@{
        App      = $name
        Kind     = 'reg'
        LivePath = $null
        RepoPath = Resolve-RepoPath $root $rel
        Label    = $rel
      }
    }
    foreach ($item in ($val.manual | ForEach-Object { $_ })) {
      [pscustomobject]@{
        App      = $name
        Kind     = 'manual'
        LivePath = $null
        RepoPath = $null
        Label    = $item
      }
    }
  }
}

# Test existence and annotate the plan.
function Test-Plan([object[]]$plan) {
  foreach ($it in $plan) {
    $liveOk = $null
    $repoOk = $null
    switch ($it.Kind) {
      'file' { $liveOk = if ($it.LivePath) { Test-Path $it.LivePath -PathType Leaf } else { $false }
               $repoOk = if ($it.RepoPath) { Test-Path $it.RepoPath -PathType Leaf } else { $false } }
      'dir'  { $liveOk = if ($it.LivePath) { Test-Path $it.LivePath -PathType Container } else { $false }
               $repoOk = if ($it.RepoPath) { Test-Path $it.RepoPath -PathType Container } else { $false } }
      'reg'  { $liveOk = $true
               $repoOk = if ($it.RepoPath) { Test-Path $it.RepoPath -PathType Leaf } else { $false } }
      default { $liveOk = $true; $repoOk = $true }
    }
    $it | Add-Member -NotePropertyName LiveOk -NotePropertyValue $liveOk
    $it | Add-Member -NotePropertyName RepoOk -NotePropertyValue $repoOk
    $it
  }
}
