# Enforce strict parsing and fail fast.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Expand $env:VARS and normalize slashes.
function Resolve-EnvRefs([string]$s) {
  if (-not $s) { return $null }
  # Normalize forward slashes for Windows APIs.
  $t = $s -replace '/', '\'
  # Replace $env:VAR tokens with process environment values.
  [regex]::Replace($t, '\$env:([A-Za-z_][A-Za-z0-9_]*)', {
    param($m) [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
  })
}

# Turn a repo-relative path into an absolute filesystem path.
function Resolve-RepoPath([string]$root, [string]$rel) {
  if (-not $rel) { return $null }
  # Join the repo root with a normalized relative path.
  Join-Path $root ($rel -replace '/', '\')
}

# Return a list value or an empty array when the property is missing.
function Get-PropList([object]$obj, [string]$name) {
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p -or $null -eq $p.Value) { @() } else { $p.Value }
}

# Locate the active LibreWolf profile directory by parsing profiles.ini.
function Get-LibreWolfProfilePath {
  # Point to profiles.ini in Roaming.
  $ini = Join-Path $env:APPDATA 'LibreWolf\profiles.ini'
  if (-not (Test-Path $ini -PathType Leaf)) { return $null }
  # Read raw content using default encoding to match file origin.
  $content  = Get-Content -Raw $ini
  # Extract only [Profile*] sections.
  $sections = ($content -split '\r?\n\r?\n') | Where-Object { $_ -match '^\[Profile' }
  # Prefer the section with Default=1, otherwise take the first section.
  $pick = $sections | Where-Object { $_ -match '^Default=1' } | Select-Object -First 1
  if (-not $pick) { $pick = $sections | Select-Object -First 1 }
  if (-not $pick) { return $null }
  # Extract the Path= value.
  $pathLine = ($pick -split '\r?\n') | Where-Object { $_ -like 'Path=*' } | Select-Object -First 1
  if (-not $pathLine) { return $null }
  $rel = $pathLine.Split('=',2)[1]
  # Build an absolute profile path from the relative value.
  $base = Join-Path $env:APPDATA 'LibreWolf'
  $full = if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $base $rel }
  # Normalize and expand any environment references.
  Resolve-EnvRefs $full
}

# Publish derived environment variables for use in JSON live paths.
function Initialize-Env {
  # Set LIBREWOLF only if not already provided by the caller.
  if (-not $env:LIBREWOLF) {
    $p = Get-LibreWolfProfilePath
    if ($p) { $env:LIBREWOLF = $p }
  }
}

# Check if a path is rooted and non-empty.
function Is-Rooted([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $false }
  [IO.Path]::IsPathRooted($p)
}

# Flatten map.json into a sequence of actionable plan items.
function Build-Plan([object]$map, [string]$root) {
  foreach ($app in $map.PSObject.Properties) {
    $name = $app.Name
    $val  = $app.Value

    # Translate file entries into plan items.
    foreach ($m in (Get-PropList $val 'files')) {
      if (-not $m) { continue }
      [pscustomobject]@{
        App      = $name
        Kind     = 'file'
        Label    = $m.backup
        LiveSpec = $m.live
        LivePath = Resolve-EnvRefs $m.live
        RepoPath = Resolve-RepoPath $root $m.backup
      }
    }

    # Translate directory entries into plan items.
    foreach ($m in (Get-PropList $val 'dirs')) {
      if (-not $m) { continue }
      [pscustomobject]@{
        App      = $name
        Kind     = 'dir'
        Label    = $m.backup
        LiveSpec = $m.live
        LivePath = Resolve-EnvRefs $m.live
        RepoPath = Resolve-RepoPath $root $m.backup
      }
    }

    # Translate registry entries into plan items.
    foreach ($rel in (Get-PropList $val 'reg')) {
      if (-not $rel) { continue }
      [pscustomobject]@{
        App      = $name
        Kind     = 'reg'
        Label    = $rel
        LiveSpec = $null
        LivePath = $null
        RepoPath = Resolve-RepoPath $root $rel
      }
    }

    # Translate manual items into plan items.
    foreach ($item in (Get-PropList $val 'manual')) {
      if (-not $item) { continue }
      [pscustomobject]@{
        App      = $name
        Kind     = 'manual'
        Label    = $item
        LiveSpec = $null
        LivePath = $null
        RepoPath = $null
      }
    }
  }
}

# Test existence and annotate each plan item with booleans.
function Test-Plan([object[]]$plan) {
  foreach ($it in $plan) {
    # Compute existence according to item kind.
    $liveOk = $null
    $repoOk = $null
    switch ($it.Kind) {
      'file' {
        $liveOk = if ($it.LivePath) { Test-Path $it.LivePath -PathType Leaf } else { $false }
        $repoOk = if ($it.RepoPath) { Test-Path $it.RepoPath -PathType Leaf } else { $false }
      }
      'dir'  {
        $liveOk = if ($it.LivePath) { Test-Path $it.LivePath -PathType Container } else { $false }
        $repoOk = if ($it.RepoPath) { Test-Path $it.RepoPath -PathType Container } else { $false }
      }
      'reg'  {
        $liveOk = $true
        $repoOk = if ($it.RepoPath) { Test-Path $it.RepoPath -PathType Leaf } else { $false }
      }
      default {
        $liveOk = $true
        $repoOk = $true
      }
    }
    # Attach results to the item and yield it.
    $it | Add-Member -NotePropertyName LiveOk -NotePropertyValue $liveOk -Force
    $it | Add-Member -NotePropertyName RepoOk -NotePropertyValue $repoOk -Force
    $it
  }
}