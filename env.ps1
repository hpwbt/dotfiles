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

# Turn a repo-relative path into an absolute filesystem path.
function Resolve-RepoPath([string]$root, [string]$rel) {
  if (-not $rel) { return $null }
  Join-Path $root ($rel -replace '/', '\')
}

# Return a list value or empty array when property missing.
function Get-PropList([object]$obj, [string]$name) {
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p -or $null -eq $p.Value) { @() } else { $p.Value }
}

# Locate active LibreWolf profile.
function Get-LibreWolfProfilePath {
  $ini = Join-Path $env:APPDATA 'LibreWolf\profiles.ini'
  if (-not (Test-Path $ini -PathType Leaf)) { return $null }
  $content  = Get-Content -Raw $ini
  $sections = ($content -split '\r?\n\r?\n') | Where-Object { $_ -match '^\[Profile' }
  $pick = $sections | Where-Object { $_ -match '^Default=1' } | Select-Object -First 1
  if (-not $pick) { $pick = $sections | Select-Object -First 1 }
  if (-not $pick) { return $null }
  $pathLine = ($pick -split '\r?\n') | Where-Object { $_ -like 'Path=*' } | Select-Object -First 1
  if (-not $pathLine) { return $null }
  $rel = $pathLine.Split('=',2)[1]
  $base = Join-Path $env:APPDATA 'LibreWolf'
  $full = if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $base $rel }
  Resolve-EnvRefs $full
}

# Publish derived environment variables for use in JSON live paths.
function Initialize-Env {
  if (-not $env:LIBREWOLF) {
    $p = Get-LibreWolfProfilePath
    if ($p) { $env:LIBREWOLF = $p }
  }
}

# Must be drive-rooted or UNC.
function Is-AbsolutePath([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $false }
  $root = [IO.Path]::GetPathRoot($p)
  if ([string]::IsNullOrWhiteSpace($root)) { return $false }
  if ($root -eq '\' -or $root -eq '/') { return $false }
  return $true
}

# Flatten map.json into a sequence of actionable plan items.
function Build-Plan([object]$map, [string]$root) {
  foreach ($app in $map.PSObject.Properties) {
    $name = $app.Name
    $val  = $app.Value

    foreach ($m in (Get-PropList $val 'files')) {
      if (-not $m) { continue }
      [pscustomobject]@{ App=$name;Kind='file';Label=$m.backup;LiveSpec=$m.live;LivePath=(Resolve-EnvRefs $m.live);RepoPath=(Resolve-RepoPath $root $m.backup) }
    }
    foreach ($m in (Get-PropList $val 'dirs')) {
      if (-not $m) { continue }
      [pscustomobject]@{ App=$name;Kind='dir';Label=$m.backup;LiveSpec=$m.live;LivePath=(Resolve-EnvRefs $m.live);RepoPath=(Resolve-RepoPath $root $m.backup) }
    }
    foreach ($rel in (Get-PropList $val 'reg')) {
      if (-not $rel) { continue }
      [pscustomobject]@{ App=$name;Kind='reg';Label=$rel;LiveSpec=$null;LivePath=$null;RepoPath=(Resolve-RepoPath $root $rel) }
    }
    foreach ($item in (Get-PropList $val 'manual')) {
      if (-not $item) { continue }
      [pscustomobject]@{ App=$name;Kind='manual';Label=$item;LiveSpec=$null;LivePath=$null;RepoPath=$null }
    }
  }
}

# Test existence and attach booleans.
function Test-Plan([object[]]$plan) {
  foreach ($it in $plan) {
    switch ($it.Kind) {
      'file' { $l = if ($it.LivePath) {Test-Path $it.LivePath -PathType Leaf} else {$false}; $r = if ($it.RepoPath) {Test-Path $it.RepoPath -PathType Leaf} else {$false} }
      'dir'  { $l = if ($it.LivePath) {Test-Path $it.LivePath -PathType Container} else {$false}; $r = if ($it.RepoPath) {Test-Path $it.RepoPath -PathType Container} else {$false} }
      'reg'  { $l = $true; $r = if ($it.RepoPath) {Test-Path $it.RepoPath -PathType Leaf} else {$false} }
      default{ $l = $true; $r = $true }
    }
    $it | Add-Member LiveOk $l -Force
    $it | Add-Member RepoOk $r -Force
    $it
  }
}
