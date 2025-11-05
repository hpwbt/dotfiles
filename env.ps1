Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Precompile once
$script:EnvRefRe = New-Object System.Text.RegularExpressions.Regex(
  '\$env:([A-Za-z_][A-Za-z0-9_]*)',
  [System.Text.RegularExpressions.RegexOptions]::Compiled
)

function Resolve-EnvRefs {
  [CmdletBinding()]
  param([string]$s)
  if (-not $s) { return $null }
  $t = $s -replace '/', '\'
  $script:EnvRefRe.Replace($t, {
    param($m)
    $name = $m.Groups[1].Value
    $val  = [Environment]::GetEnvironmentVariable($name)
    if ($null -eq $val) { throw "Environment variable `$env:$name not set." }
    $val
  })
}

function Resolve-RepoPath {
  [CmdletBinding()]
  param([string]$root, [string]$rel)
  if (-not $rel) { return $null }
  Join-Path -Path $root -ChildPath ($rel -replace '/', '\')
}

function Get-PropList {
  [CmdletBinding()]
  param([object]$obj, [string]$name)
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p -or $null -eq $p.Value) { return @() }
  $v = $p.Value
  if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) { return $v }
  ,$v
}

function Get-LibreWolfProfilePath {
  [CmdletBinding()]
  param()
  $ini = Join-Path $env:APPDATA 'LibreWolf\profiles.ini'
  if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) { return $null }
  $content  = Get-Content -LiteralPath $ini -Raw
  $sections = ($content -split '\r?\n\r?\n') | Where-Object { $_ -match '^\[Profile' }
  $pick     = ($sections | Where-Object { $_ -match '^Default=1' } | Select-Object -First 1)
  if (-not $pick) { $pick = $sections | Select-Object -First 1 }
  if (-not $pick) { return $null }
  $pathLine = ($pick -split '\r?\n') | Where-Object { $_ -like 'Path=*' } | Select-Object -First 1
  if (-not $pathLine) { return $null }
  $rel  = $pathLine.Split('=',2)[1]
  $base = Join-Path $env:APPDATA 'LibreWolf'
  $full = if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $base $rel }
  Resolve-EnvRefs $full
}

function Initialize-Env {
  [CmdletBinding()]
  param()
  if (-not $env:LIBREWOLF) {
    $p = Get-LibreWolfProfilePath
    if ($p) { $env:LIBREWOLF = $p }
  }
  $env:LIBREWOLF
}

function New-PlanItem {
  param($app,$kind,$label,$liveSpec,$livePath,$repoPath)
  [pscustomobject]@{
    App      = $app
    Kind     = $kind
    Label    = $label
    LiveSpec = $liveSpec
    LivePath = $livePath
    RepoPath = $repoPath
  }
}

function Build-Plan {
  [CmdletBinding()]
  param([object]$map, [string]$root)

  foreach ($app in $map.PSObject.Properties) {
    $name = $app.Name
    $val  = $app.Value

    foreach ($m in (Get-PropList $val 'files')) {
      if ($m) {
        $lp = Resolve-EnvRefs $m.live
        $rp = Resolve-RepoPath $root $m.backup
        New-PlanItem $name 'file' $m.backup $m.live $lp $rp
      }
    }

    foreach ($m in (Get-PropList $val 'dirs')) {
      if ($m) {
        $lp = Resolve-EnvRefs $m.live
        $rp = Resolve-RepoPath $root $m.backup
        New-PlanItem $name 'dir' $m.backup $m.live $lp $rp
      }
    }

    foreach ($rel in (Get-PropList $val 'registry')) {
      if ($rel) {
        New-PlanItem $name 'reg' $rel $null $null (Resolve-RepoPath $root $rel)
      }
    }

    foreach ($item in (Get-PropList $val 'manual')) {
      if ($item) {
        New-PlanItem $name 'manual' $item $null $null $null
      }
    }
  }
}

function Test-Plan {
  [CmdletBinding()]
  param([object[]]$plan)

  foreach ($it in $plan) {
    switch ($it.Kind) {
      'file' {
        $l = if ($it.LivePath) { Test-Path -LiteralPath $it.LivePath -PathType Leaf } else { $false }
        $r = if ($it.RepoPath) { Test-Path -LiteralPath $it.RepoPath -PathType Leaf } else { $false }
      }
      'dir' {
        $l = if ($it.LivePath) { Test-Path -LiteralPath $it.LivePath -PathType Container } else { $false }
        $r = if ($it.RepoPath) { Test-Path -LiteralPath $it.RepoPath -PathType Container } else { $false }
      }
      'reg' {
        $l = $true
        $r = if ($it.RepoPath) { Test-Path -LiteralPath $it.RepoPath -PathType Leaf } else { $false }
      }
      default {
        $l = $true
        $r = $true
      }
    }
    $it | Add-Member -Name LiveOk -Value $l -MemberType NoteProperty -Force
    $it | Add-Member -Name RepoOk -Value $r -MemberType NoteProperty -Force
    $it
  }
}
