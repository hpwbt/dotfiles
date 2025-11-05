# Enforce strict parsing and fail fast.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared helpers.
. "$PSScriptRoot\env.ps1"

# Initialize derived environment variables.
Initialize-Env

# Load and flatten the map.
$root = $PSScriptRoot
$map  = Get-Content (Join-Path $root 'map.json') -Raw | ConvertFrom-Json
$plan = Build-Plan $map $root | Test-Plan

# Group output per program and state facts.
foreach ($group in $plan | Group-Object App) {
  Write-Host "== $($group.Name) =="
  foreach ($it in $group.Group) {
    switch ($it.Kind) {
      'file' { Write-Host ("  File: {0}" -f $it.Label)
               Write-Host ("    Live:   {0}." -f ($(if ($it.LiveOk) {'Exists'} else {'Missing'})))
               Write-Host ("    Backup: {0}." -f ($(if ($it.RepoOk) {'Exists'} else {'Missing'})))
               if ($it.LivePath) { Write-Host ("    Live path: {0}" -f $it.LivePath) } }
      'dir'  { Write-Host ("  Dir:  {0}" -f $it.Label)
               Write-Host ("    Live:   {0}." -f ($(if ($it.LiveOk) {'Exists'} else {'Missing'})))
               Write-Host ("    Backup: {0}." -f ($(if ($it.RepoOk) {'Exists'} else {'Missing'})))
               if ($it.LivePath) { Write-Host ("    Live path: {0}" -f $it.LivePath) } }
      'reg'  { Write-Host ("  Reg:  {0}" -f $it.Label)
               Write-Host ("    Backup: {0}." -f ($(if ($it.RepoOk) {'Exists'} else {'Missing'}))) }
      'manual' { Write-Host ("  Manual: {0}. Action required." -f $it.Label) }
    }
  }
  Write-Host
}

# Compute exit code from missing items.
$missing = @(
  $plan | Where-Object { $_.Kind -in 'file','dir' -and ($_.LiveOk -eq $false -or $_.RepoOk -eq $false) }
  $plan | Where-Object { $_.Kind -eq 'reg' -and ($_.RepoOk -eq $false) }
).Count

if ($missing -gt 0) { Write-Host ("Summary: {0} missing item(s)." -f $missing); exit 2 }
else { Write-Host "Summary: all present."; exit 0 }
