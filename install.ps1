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

# Emit a normalized action line.
function Log([string]$verb, [string]$label, [string]$extra = $null) {
  if ($extra) { Write-Host ("  {0,-8} {1}  {2}" -f $verb, $label, $extra) }
  else       { Write-Host ("  {0,-8} {1}"      -f $verb, $label) }
}

# Copy one file with parent creation and contextual logging.
function Put-File([string]$src,[string]$dst,[string]$spec,[string]$label) {
  # Skip when the destination is not an absolute path with a valid root.
  if (-not (Is-AbsolutePath $dst)) { Log "Skip"  $label "Unresolved live path from: $spec."; return }
  # Skip if the repo source is missing.
  if (-not (Test-Path $src -PathType Leaf)) { Log "Skip"  $label "Missing repo file."; return }
  # Ensure parent directory exists.
  $parent = Split-Path $dst
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  # Decide action based on current state.
  $exists = Test-Path $dst -PathType Leaf
  Copy-Item $src $dst -Force
  if ($exists) { Log "Update" $label $dst }
  else         { Log "Create" $label $dst }
}

# Replace one directory with the repo snapshot and contextual logging.
function Put-Dir([string]$src,[string]$dst,[string]$spec,[string]$label) {
  # Skip when the destination is not an absolute path with a valid root.
  if (-not (Is-AbsolutePath $dst)) { Log "Skip"    $label "Unresolved live path from: $spec."; return }
  # Skip if the repo source is missing.
  if (-not (Test-Path $src -PathType Container)) { Log "Skip" $label "Missing repo dir."; return }
  # Ensure parent directory exists.
  $parent = Split-Path $dst
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  # Decide action and perform copy.
  $existed = Test-Path $dst -PathType Container
  if ($existed) { Remove-Item $dst -Recurse -Force }
  Copy-Item $src $dst -Recurse -Force
  if ($existed) { Log "Replace" $label $dst }
  else          { Log "Create"  $label $dst }
}

# Import one .reg file as administrator with logging.
function Import-Reg([string]$regPath,[string]$label) {
  # Skip if the repo source is missing.
  if (-not (Test-Path $regPath -PathType Leaf)) { Log "Skip" $label "Missing reg file."; return }
  Start-Process reg.exe -ArgumentList @("import","`"$regPath`"") -Verb RunAs -Wait
  Log "Import" $label
}

# Execute the plan grouped by program for readable logs.
foreach ($group in $plan | Group-Object App) {
  Write-Host "== $($group.Name) =="
  foreach ($it in $group.Group) {
    switch ($it.Kind) {
      'file'   { Put-File $it.RepoPath $it.LivePath $it.LiveSpec $it.Label }
      'dir'    { Put-Dir  $it.RepoPath $it.LivePath $it.LiveSpec $it.Label }
      'reg'    { Import-Reg $it.RepoPath $it.Label }
      'manual' { Log "Manual" $it.Label "Action required." }
    }
  }
  Write-Host
}

# Finish with a clear status line.
Write-Host "Install complete."
