Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($PSVersionTable.PSVersion.Major -ge 7) { $PSNativeCommandUseErrorActionPreference = $true }

function Log([string]$v,[string]$l,[string]$x=$null){ if($x){Write-Host "$v $l $x"}else{Write-Host "$v $l"} }
function Is-Absolute([string]$p){ if([string]::IsNullOrWhiteSpace($p)){return $false}; [IO.Path]::IsPathRooted($p) }
function Ensure-Parent([string]$p){ $d=Split-Path $p; if($d){ New-Item -ItemType Directory -Force -Path $d | Out-Null } }
function Normalize([string]$p){ try{ [IO.Path]::GetFullPath($p) } catch { $p } }

function To-LongPath([string]$p){
  if ($p.StartsWith('\\?\')) { return $p }
  if ($p.StartsWith('\'))    { return '\\?\UNC' + $p }
  return '\\?\' + $p
}

try { . "$PSScriptRoot\env.ps1" } catch { Write-Host "Error env.ps1 $($_.Exception.Message)"; exit 1 }
try { Initialize-Env } catch { Write-Host "Error Initialize-Env $($_.Exception.Message)"; exit 1 }

$root = $PSScriptRoot
$map  = Get-Content (Join-Path $root 'map.json') -Raw -Encoding UTF8 | ConvertFrom-Json @(
  if ($PSVersionTable.PSVersion.Major -ge 7) { @{ AsHashtable = $true } else { @{} }
)
$plan = Build-Plan $map $root
if (-not $plan) { Write-Host "Error plan-empty"; exit 1 }

$haveRobo = (Get-Command robocopy.exe -ErrorAction SilentlyContinue) -ne $null

function Put-File([string]$src,[string]$dst,[string]$spec,[string]$label){
  try{
    if(-not (Is-Absolute $dst)){ Log "Skip" $label "unresolved:$spec"; return }
    $src = Normalize $src; $dst = Normalize $dst
    if(-not (Test-Path -LiteralPath $src -PathType Leaf)){ Log "Skip" $label "missing-src"; return }
    Ensure-Parent $dst
    $exists = Test-Path -LiteralPath $dst -PathType Leaf
    Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
    Log ($exists?"Update":"Create") $label $dst
  } catch { Log "Error" $label $_.Exception.Message; throw }
}

function Put-Dir([string]$src,[string]$dst,[string]$spec,[string]$label){
  try{
    if(-not (Is-Absolute $dst)){ Log "Skip" $label "unresolved:$spec"; return }
    $src = Normalize $src; $dst = Normalize $dst
    if(-not (Test-Path -LiteralPath $src -PathType Container)){ Log "Skip" $label "missing-src"; return }
    Ensure-Parent $dst
    $existed = Test-Path -LiteralPath $dst -PathType Container
    if($haveRobo){
      $s = To-LongPath $src
      $d = To-LongPath $dst
      $args = @($s,$d,"/MIR","/R:1","/W:1","/COPY:DAT","/DCOPY:DAT","/MT:16","/XJ","/SL","/FFT","/NFL","/NDL","/NP","/NJH","/NJS")
      $p = Start-Process -FilePath "robocopy.exe" -ArgumentList $args -NoNewWindow -PassThru -Wait
      if($p.ExitCode -lt 8){ Log ($existed?"Sync":"Create") $label $dst } else { Log "Error" $label "robocopy:$($p.ExitCode)"; throw "robocopy failed" }
    } else {
      if($existed){ Remove-Item -LiteralPath $dst -Recurse -Force }
      Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force -ErrorAction Stop
      Log ($existed?"Replace":"Create") $label $dst
    }
  } catch { Log "Error" $label $_.Exception.Message; throw }
}

function Import-Reg([string]$regPath,[string]$label){
  try{
    if(-not (Test-Path -LiteralPath $regPath -PathType Leaf)){ Log "Skip" $label "missing-reg"; return }
    $p = Start-Process -FilePath "reg.exe" -ArgumentList @("import",$regPath) -Verb RunAs -PassThru -Wait
    if($p.ExitCode -eq 0){ Log "Import" $label } else { Log "Error" $label "reg:$($p.ExitCode)"; throw "reg import failed" }
  } catch { Log "Error" $label $_.Exception.Message; throw }
}

$failed = $false
$last = $null
foreach($it in ($plan | Sort-Object App)){
  if($it.App -ne $last){ Write-Host "== $($it.App) =="; $last = $it.App }
  try{
    switch($it.Kind){
      'file'   { Put-File  $it.RepoPath $it.LivePath $it.LiveSpec $it.Label }
      'dir'    { Put-Dir   $it.RepoPath $it.LivePath $it.LiveSpec $it.Label }
      'reg'    { Import-Reg $it.RepoPath $it.Label }
      'manual' { Log "Manual" $it.Label "action-required" }
      default  { Log "Skip" $it.Label "unknown:$($it.Kind)" }
    }
  } catch { $failed = $true }
}
if($failed){ Write-Host "Done with errors."; exit 1 } else { Write-Host "Done." }
