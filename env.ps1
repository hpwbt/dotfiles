# Enforce strict parsing and fail fast.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Expand $env:VARS and normalize slashes.
function Resolve-EnvRefs([string]$s) {
  if (-not $s) { return $null }
  $t = $s -replace '/', '\'
  $t = [regex]::Replace($t, '\$env:([A-Za-z_][A-Za-z0-9_]*)', {
    param($m) [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
  })
  return $t
}

# Turn a repo-relative path into an absolute filesystem path.
function Resolve-RepoPath([string]$root, [string]$rel) {
  if (-not $rel) { return $null }
  $p = $rel -replace '/', '\'
  Join-Path $root $p
}

# Locate the active LibreWolf profile by reading profiles.ini.
function Get-LibreWolfProfilePath {
  $ini = Join-Path $env:APPDATA 'LibreWolf\profiles.ini'
  if (-not (Test-Path $ini -PathType Leaf)) { return $null }
  $content = Get-Content -Raw $ini -Encoding UTF8
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

# Publish derived environment variables used in map paths.
function Initialize-Env {
  if (-not $env:LIBREWOLF) {
    $p = Get-LibreWolfProfilePath
    if ($p) { $env:LIBREWOLF = $p }
  }
}
