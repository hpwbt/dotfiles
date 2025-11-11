Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$profilesRoot = Join-Path $env:APPDATA 'LibreWolf\Profiles'
if (-not (Test-Path -LiteralPath $profilesRoot)) {
    throw "LibreWolf profiles directory not found."
}

$matches = @(Get-ChildItem -LiteralPath $profilesRoot -Directory -Filter '*.default-default' |
           Select-Object -ExpandProperty FullName)

if ($matches.Count -eq 0) { throw "No *.default-default profile found." }
if ($matches.Count -gt 1) { throw "Multiple default-default profiles found." }

$env:LIBREPROFILE = $matches[0]
Write-Host ""
Write-Host "Environmental variable successfully set:" -ForegroundColor Green
Get-ChildItem Env: | Where-Object { $_.Name -in 'LIBREPROFILE' } | ForEach-Object {
    Write-Host ("$($_.Name) = `"$($_.Value)`"")
}
Write-Host ""