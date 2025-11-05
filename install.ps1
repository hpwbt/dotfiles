# Enforce strict parsing and fail fast.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared helpers.
. "$PSScriptRoot\env.ps1"

# Initialize derived environment variables.
Initialize-Env

# Pin the repo root to this script’s folder.
$root = $PSScriptRoot

# Load and flatten the map.
$map  = Get-Content (Join-Path $root 'map.json') -Raw | ConvertFrom-Json
$plan = Build-Plan $map $root

# Copy one file with parent creation.
function Put-File([string]$src,[string]$dst,[string]$spec) {
  # Skip when the destination is not an absolute path with a valid root.
  if (-not (Is-AbsolutePath $dst)) { Write-Host ("    Skip unresolved: {0}." -f $spec); return }
  # Skip if the repo source is missing.
  if (-not (Test-Path $src -PathType Leaf)) { Write-Host ("    Skip missing repo file: {0}." -f $src); return }
  # Ensure parent directory exists.
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  # Copy the file over the target.
  Copy-Item $src $dst -Force
}

# Replace one directory with the repo snapshot.
function Put-Dir([string]$src,[string]$dst,[string]$spec) {
  # Skip when the destination is not an absolute path with a valid root.
  if (-not (Is-AbsolutePath $dst)) { Write-Host ("    Skip unresolved: {0}." -f $spec); return }
  # Skip if the repo source is missing.
  if (-not (Test-Path $src -PathType Container)) { Write-Host ("    Skip missing repo dir: {0}." -f $src); return }
  # Remove old directory to avoid stale files.
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
  # Ensure parent directory exists.
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  # Copy the snapshot recursively.
  Copy-Item $src $dst -Recurse -Force
}

# Import one .reg file as administrator.
function Import-Reg([string]$regPath) {
  # Skip if the repo source is missing.
  if (-not (Test-Path $regPath -PathType Leaf)) { Write-Host ("    Skip missing reg: {0}." -f $regPath); return }
  # Delegate to reg.exe with elevation.
  Start-Process reg.exe -ArgumentList @("import","`"$regPath`"") -Verb RunAs -Wait
}

# Execute the plan grouped by program for readable logs.
foreach ($group in $plan | Group-Object App) {
  Write-Host "== $($group.Name) =="

  foreach ($it in $group.Group) {
    switch ($it.Kind) {
      'file' {
        Write-Host ("  File: {0}" -f $it.Label)
        Write-Host ("    Copy to {0}." -f ($(if ($it.LivePath) { $it.LivePath } else { '<unresolved>' })))
        Put-File $it.RepoPath $it.LivePath $it.LiveSpec
      }
      'dir'  {
        Write-Host ("  Dir:  {0}" -f $it.Label)
        Write-Host ("    Replace {0}." -f ($(if ($it.LivePath) { $it.LivePath } else { '<unresolved>' })))
        Put-Dir $it.RepoPath $it.LivePath $it.LiveSpec
      }
      'reg'  {
        Write-Host ("  Reg:  {0}" -f $it.Label)
        Write-Host ("    Import.")
        Import-Reg $it.RepoPath
      }
      'manual' {
        Write-Host ("  Manual: {0}. Action required." -f $it.Label)
      }
    }
  }

  Write-Host
}

# Finish with a clear status line.
Write-Host "Install complete."
