Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$IsElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

$MapPath = Join-Path $PSScriptRoot '..\map.json'
if (-not (Test-Path -LiteralPath $MapPath)) {
    throw "Map not found at: $MapPath."
}

try {
    $Map = Get-Content -LiteralPath $MapPath -Raw | ConvertFrom-Json
} catch {
    throw "Failed to parse map: $($_.Exception.Message)"
}

if (-not $Map) { throw "Map parsed to null or empty content." }