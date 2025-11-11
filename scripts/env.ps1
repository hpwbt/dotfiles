Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProfilesRoot = Join-Path $env:APPDATA 'LibreWolf\Profiles'
if (-not (Test-Path -LiteralPath $ProfilesRoot)) {
    throw "LibreWolf profiles directory not found."
}

$ProfileMatches = @(Get-ChildItem -LiteralPath $ProfilesRoot -Directory -Filter '*.default-default' |
           Select-Object -ExpandProperty FullName)

if ($ProfileMatches.Count -eq 0) { throw "No *.default-default profile found." }
if ($ProfileMatches.Count -gt 1) { throw "Multiple default-default profiles found." }

$env:LIBREPROFILE = $ProfileMatches[0]
Write-Host ""
Write-Host "Environmental variable successfully set:" -ForegroundColor Green
Get-ChildItem Env: | Where-Object { $_.Name -in 'LIBREPROFILE' } | ForEach-Object {
    Write-Host ("$($_.Name) = `"$($_.Value)`"")
}
Write-Host ""