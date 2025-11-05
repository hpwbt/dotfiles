# Enforce strict parsing and fail fast.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared helpers.
. "$PSScriptRoot/env.ps1"
Initialize-Env

# Load plan.
$root = $PSScriptRoot
$map  = Get-Content (Join-Path $root 'map.json') -Raw | ConvertFrom-Json
$plan = Build-Plan $map $root

function Put-File([string]$src,[string]$dst,[string]$spec) {
  if (-not (Is-AbsolutePath $dst)) { Write-Host "    Skip unresolved: $spec."; return }
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item $src $dst -Force
}

function Put-Dir([string]$src,[string]$dst,[string]$spec) {
  if (-not (Is-AbsolutePath $dst)) { Write-Host "    Skip unresolved: $spec."; return }
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item $src $dst -Recurse -Force
}

function Import-Reg([string]$regPath) {
  Start-Process reg.exe -ArgumentList @("import","`"$regPath`"") -Verb RunAs -Wait
}

foreach ($g in $plan | Group-Object App) {
  Write-Host "== $($g.Name) =="
  foreach ($it in $g.Group) {
    switch ($it.Kind) {
      'file' {Write-Host "  File: $($it.Label)";Write-Host "    Copy to $($it.LivePath).";Put-File $it.RepoPath $it.LivePath $it.LiveSpec}
      'dir'  {Write-Host "  Dir:  $($it.Label)";Write-Host "    Replace $($it.LivePath).";Put-Dir $it.RepoPath $it.LivePath $it.LiveSpec}
      'reg'  {Write-Host "  Reg:  $($it.Label)";Write-Host "    Import.";Import-Reg $it.RepoPath}
      'manual' {Write-Host "  Manual: $($it.Label). Action required."}
    }
  }
  Write-Host
}

Write-Host "Install complete."
