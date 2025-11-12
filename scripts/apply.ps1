Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Resolve repository root based on script location.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = Split-Path $ScriptDir -Parent
$MapPath = Join-Path $RepoRoot "map.json"

# Ensure map.json exists.
if (-not (Test-Path $MapPath)) {
    throw "Map configuration file not found at: $MapPath."
}

# Prepare global tallies.
$Totals = @{
    Copied  = 0
    Skipped = 0
    Missing = 0
    Errors  = 0
}

# Read and parse the map configuration.
$ConfigJson = Get-Content -LiteralPath $MapPath -Raw -Encoding UTF8
try {
    $Config = $ConfigJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Map configuration could not be parsed: $($_.Exception.Message)."
}

# Ensure the root of the store is defined.
if (-not ($Config -and $Config.PSObject.Properties.Name -contains 'storeRoot')) {
    throw "Map configuration lacks a defined store root."
}
if (-not ($Config.storeRoot -is [string]) -or [string]::IsNullOrWhiteSpace($Config.storeRoot)) {
    throw "Store root must be a non-empty text value."
}

# Ensure the list of program entries is present.
if (-not ($Config.PSObject.Properties.Name -contains 'programs')) {
    throw "Map configuration is missing a list of program entries."
}
if (-not ($Config.programs -is [System.Collections.IEnumerable])) {
    throw "Program entries must be provided as a list."
}

# Validate each program entry.
$Programs = @($Config.programs)
for ($i = 0; $i -lt $Programs.Count; $i++) {
    $p = $Programs[$i]

    if (-not ($p -is [psobject])) { throw "Program entry must be an object." }
    if (-not ($p.PSObject.Properties.Name -contains 'name')) { throw "Program entry lacks a name." }
    if (-not ($p.name -is [string]) -or [string]::IsNullOrWhiteSpace($p.name)) { throw "Program name must be a non-empty text value." }

    if ($p.PSObject.Properties.Name -contains 'files') {
        if (-not ($p.files -is [System.Collections.IEnumerable])) { throw "File mappings must be provided as a list." }
        $fi = 0
        foreach ($f in $p.files) {
            if (-not ($f -is [psobject])) { throw "File mapping must be an object." }
            if (-not ($f.PSObject.Properties.Name -contains 'live')) { throw "File mapping lacks a live path." }
            if (-not ($f.PSObject.Properties.Name -contains 'store')) { throw "File mapping lacks a store path." }
            if (-not ($f.live -is [string]) -or [string]::IsNullOrWhiteSpace($f.live)) { throw "File live path must be a non-empty text value." }
            if (-not ($f.store -is [string]) -or [string]::IsNullOrWhiteSpace($f.store)) { throw "File store path must be a non-empty text value." }
            $fi++
        }
    }

    if ($p.PSObject.Properties.Name -contains 'directories') {
        if (-not ($p.directories -is [System.Collections.IEnumerable])) { throw "Directory mappings must be provided as a list." }
        $di = 0
        foreach ($d in $p.directories) {
            if (-not ($d -is [psobject])) { throw "Directory mapping must be an object." }
            if (-not ($d.PSObject.Properties.Name -contains 'live')) { throw "Directory mapping lacks a live path." }
            if (-not ($d.PSObject.Properties.Name -contains 'store')) { throw "Directory mapping lacks a store path." }
            if (-not ($d.live -is [string]) -or [string]::IsNullOrWhiteSpace($d.live)) { throw "Directory live path must be a non-empty text value." }
            if (-not ($d.store -is [string]) -or [string]::IsNullOrWhiteSpace($d.store)) { throw "Directory store path must be a non-empty text value." }
            $di++
        }
    }

    if ($p.PSObject.Properties.Name -contains 'manual') {
        if (-not ($p.manual -is [System.Collections.IEnumerable])) { throw "Manual checklist must be provided as a list." }
        $mi = 0
        foreach ($m in $p.manual) {
            if (-not ($m -is [string]) -or [string]::IsNullOrWhiteSpace($m)) { throw "Manual checklist item must be a non-empty text value." }
            $mi++
        }
    }

    if ($p.PSObject.Properties.Name -contains 'registryFiles') {
        if (-not ($p.registryFiles -is [System.Collections.IEnumerable])) { throw "Registry file list must be provided as a list." }
        $ri = 0
        foreach ($r in $p.registryFiles) {
            if (-not ($r -is [string]) -or [string]::IsNullOrWhiteSpace($r)) { throw "Registry file entry must be a non-empty text value." }
            if (-not ($r.ToString().ToLowerInvariant().EndsWith('.reg'))) { throw "Registry file entry must end with .reg." }
            $ri++
        }
    }
}

# Expose validated values for later components.
$StoreRootRaw = [string]$Config.storeRoot
$Programs     = @($Config.programs)

# Expand $env: tokens, failing on unknown names.
function Expand-EnvTokens {
    param([Parameter(Mandatory=$true)][string]$Text)
    $pattern = '(?i)\$env:([A-Za-z0-9_]+)'
    return ([System.Text.RegularExpressions.Regex]::Replace($Text, $pattern, {
        param($m)
        $name = $m.Groups[1].Value
        $val = [Environment]::GetEnvironmentVariable($name)
        if ($null -eq $val) {
            throw "Unknown environment variable: $name."
        }
        return $val
    }))
}

# Normalize slashes and collapse path segments.
function Normalize-Path {
    param([Parameter(Mandatory=$true)][string]$Text)
    $p = $Text -replace '/', '\'
    return [System.IO.Path]::GetFullPath($p)
}

# Resolve a path inside the program’s store folder and block traversal.
function Resolve-StorePath {
    param(
        [Parameter(Mandatory=$true)][string]$ProgramStoreRoot,
        [Parameter(Mandatory=$true)][string]$RelativePath
    )
    $rel = $RelativePath -replace '/', '\'
    $combined = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($ProgramStoreRoot, $rel))
    if (-not $combined.StartsWith($ProgramStoreRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Store path escapes the program’s store folder: $RelativePath."
    }
    return $combined
}

# Expand and normalize the store root.
$StoreRoot = Normalize-Path (Expand-EnvTokens -Text $StoreRootRaw)

# Prepare program contexts with computed store folders.
$ProgramContexts = foreach ($p in $Programs) {
    $progStoreRoot = [System.IO.Path]::Combine($StoreRoot, ($p.name -replace '/', '\'))
    $progStoreRootFull = [System.IO.Path]::GetFullPath($progStoreRoot)
    [pscustomobject]@{
        Name             = $p.name
        Spec             = $p
        ProgramStoreRoot = $progStoreRootFull
    }
}

# Detect whether the process has administrative rights.
function Test-IsElevated {
    try {
        $id  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pri = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $pri.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        throw "Failed to determine elevation state: $($_.Exception.Message)."
    }
}

# Cache elevation state for later decisions.
$IsElevated = Test-IsElevated

# Ensure parent folder exists for a target path.
function Ensure-ParentDirectory {
    param([Parameter(Mandatory=$true)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($parent)) { return }
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

# Remove read-only attribute so overwrites succeed.
function Clear-ReadOnly {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $attrs = [System.IO.File]::GetAttributes($Path)
        if (($attrs -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            [System.IO.File]::SetAttributes($Path, $attrs -bxor [System.IO.FileAttributes]::ReadOnly)
        }
    } catch {
        throw "Failed to clear read-only attribute: $($_.Exception.Message)."
    }
}

# Compare two files by size and modification time.
function Compare-Files {
    param(
        [Parameter(Mandatory=$true)][string]$A,
        [Parameter(Mandatory=$true)][string]$B
    )
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    $fa = Get-Item -LiteralPath $A -Force
    $fb = Get-Item -LiteralPath $B -Force
    return ($fa.Length -eq $fb.Length) -and ($fa.LastWriteTimeUtc -eq $fb.LastWriteTimeUtc)
}

# Copy a single file with skip and overwrite logic.
function Copy-File {
    param(
        [Parameter(Mandatory=$true)][string]$Src,
        [Parameter(Mandatory=$true)][string]$Dst
    )
    if (-not (Test-Path -LiteralPath $Src)) {
        return [pscustomobject]@{ Status='missing'; Src=$Src; Dst=$Dst; Message='Source not found.' }
    }

    try {
        Ensure-ParentDirectory -Path $Dst

        if (Test-Path -LiteralPath $Dst) {
            if (Compare-Files -A $Src -B $Dst) {
                return [pscustomobject]@{ Status='skipped'; Src=$Src; Dst=$Dst; Message='Already identical.' }
            }
            Clear-ReadOnly -Path $Dst
        }

        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        return [pscustomobject]@{ Status='copied'; Src=$Src; Dst=$Dst; Message=$null }
    } catch {
        return [pscustomobject]@{ Status='error'; Src=$Src; Dst=$Dst; Message=$_.Exception.Message }
    }
}

# Copy a directory tree with per-file decisions.
function Copy-Directory {
    param(
        [Parameter(Mandatory=$true)][string]$Src,
        [Parameter(Mandatory=$true)][string]$Dst
    )

    if (-not (Test-Path -LiteralPath $Src)) {
        return [pscustomobject]@{
            Results = @([pscustomobject]@{ Status='missing'; Src=$Src; Dst=$Dst; Message='Source folder not found.' })
        }
    }

    $results = New-Object System.Collections.Generic.List[object]

    try {
        if (-not (Test-Path -LiteralPath $Dst)) {
            New-Item -ItemType Directory -Path $Dst -Force | Out-Null
        }

        Get-ChildItem -LiteralPath $Src -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($Src.Length).TrimStart('\','/')
            $dstFile = Join-Path $Dst $rel
            $srcFile = $_.FullName
            $res = Copy-File -Src $srcFile -Dst $dstFile
            $results.Add($res) | Out-Null
        }
    } catch {
        $results.Add([pscustomobject]@{ Status='error'; Src=$Src; Dst=$Dst; Message=$_.Exception.Message }) | Out-Null
    }

    return [pscustomobject]@{ Results = $results }
}

# Import a registry file using the system tool.
function Import-RegFile {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Status='failed'; File=$Path; Message='File not found.' }
    }
    if (-not ($Path.ToLowerInvariant().EndsWith('.reg'))) {
        return [pscustomobject]@{ Status='failed'; File=$Path; Message='File must end with .reg.' }
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'reg.exe'
        $psi.Arguments = "import `"$Path`""
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()

        if ($proc.ExitCode -eq 0) {
            return [pscustomobject]@{ Status='imported'; File=$Path; Message=$null }
        } else {
            return [pscustomobject]@{ Status='failed'; File=$Path; Message=("Exit code {0}." -f $proc.ExitCode) }
        }
    } catch {
        return [pscustomobject]@{ Status='failed'; File=$Path; Message=$_.Exception.Message }
    }
}

# Process each program entry and apply mappings.
foreach ($ctx in $ProgramContexts) {
    $p = $ctx.Spec
    $name = $ctx.Name
    $programStoreRoot = $ctx.ProgramStoreRoot

    Write-Host ""
    Write-Host $name

    $pCopied = 0
    $pSkipped = 0
    $pMissing = 0
    $pErrors = 0
    $pRegImported = 0
    $pRegFailed = 0

    # Apply file mappings.
    if ($p.PSObject.Properties.Name -contains 'files' -and $p.files) {
        foreach ($f in $p.files) {
            try {
                $src = Resolve-StorePath -ProgramStoreRoot $programStoreRoot -RelativePath $f.store
                $dst = Normalize-Path (Expand-EnvTokens -Text $f.live)

                if (-not (Test-Path -LiteralPath $src)) {
                    Write-Host ("MISSING {0}" -f $src)
                    $pMissing++; continue
                }

                $res = Copy-File -Src $src -Dst $dst
                switch ($res.Status) {
                    'copied' {
                        Write-Host ("COPIED  {0} -> {1}" -f $res.Src, $res.Dst)
                        $pCopied++
                    }
                    'skipped' {
                        Write-Host ("SKIPPED {0}" -f $res.Dst)
                        $pSkipped++
                    }
                    'missing' {
                        Write-Host ("MISSING {0}" -f $res.Src)
                        $pMissing++
                    }
                    'error' {
                        $errPath = if ($res.Dst) { $res.Dst } else { $res.Src }
                        Write-Host ("ERROR   {0}: {1}" -f $errPath, $res.Message)
                        $pErrors++
                    }
                }
            } catch {
                Write-Host ("ERROR   {0}: {1}" -f $f.live, $_.Exception.Message)
                $pErrors++
            }
        }
    }

    # Apply directory mappings.
    if ($p.PSObject.Properties.Name -contains 'directories' -and $p.directories) {
        foreach ($d in $p.directories) {
            try {
                $srcDir = Resolve-StorePath -ProgramStoreRoot $programStoreRoot -RelativePath $d.store
                $dstDir = Normalize-Path (Expand-EnvTokens -Text $d.live)

                if (-not (Test-Path -LiteralPath $srcDir)) {
                    Write-Host ("MISSING {0}" -f $srcDir)
                    $pMissing++; continue
                }

                $dirRes = Copy-Directory -Src $srcDir -Dst $dstDir
                foreach ($r in $dirRes.Results) {
                    switch ($r.Status) {
                        'copied' {
                            Write-Host ("COPIED  {0} -> {1}" -f $r.Src, $r.Dst)
                            $pCopied++
                        }
                        'skipped' {
                            Write-Host ("SKIPPED {0}" -f $r.Dst)
                            $pSkipped++
                        }
                        'missing' {
                            Write-Host ("MISSING {0}" -f $r.Src)
                            $pMissing++
                        }
                        'error' {
                            $errPath = if ($r.Dst) { $r.Dst } else { $r.Src }
                            Write-Host ("ERROR   {0}: {1}" -f $errPath, $r.Message)
                            $pErrors++
                        }
                    }
                }
            } catch {
                Write-Host ("ERROR   {0}: {1}" -f $d.live, $_.Exception.Message)
                $pErrors++
            }
        }
    }

    # Apply registry imports if elevated.
    if ($p.PSObject.Properties.Name -contains 'registryFiles' -and $p.registryFiles) {
        if (-not $IsElevated) {
            Write-Host "Registry skipped (not elevated)."
            $pSkipped++
        } else {
            foreach ($rf in $p.registryFiles) {
                try {
                    if (-not ($rf.ToString().ToLowerInvariant().EndsWith('.reg'))) {
                        Write-Host ("REG FAILED   {0}: {1}" -f $rf, "File must end with .reg.")
                        $pRegFailed++; $pErrors++; continue
                    }
                    $regPath = Resolve-StorePath -ProgramStoreRoot $programStoreRoot -RelativePath $rf
                    $res = Import-RegFile -Path $regPath
                    if ($res.Status -eq 'imported') {
                        Write-Host ("REG IMPORTED {0}" -f $regPath)
                        $pRegImported++; $pCopied++
                    } else {
                        Write-Host ("REG FAILED   {0}: {1}" -f $regPath, $res.Message)
                        $pRegFailed++
                        if ($res.Message -match 'not found') { $pMissing++ } else { $pErrors++ }
                    }
                } catch {
                    Write-Host ("REG FAILED   {0}: {1}" -f $rf, $_.Exception.Message)
                    $pRegFailed++; $pErrors++
                }
            }
        }
    }

    # Print manual checklist if present.
    if ($p.PSObject.Properties.Name -contains 'manual' -and $p.manual) {
        foreach ($m in $p.manual) {
            Write-Host ("- {0}" -f $m)
        }
    }

    # Program summary and global tally.
    Write-Host ("Summary: copied={0} skipped={1} missing={2} errors={3} reg: imported={4} failed={5}" -f `
        $pCopied, $pSkipped, $pMissing, $pErrors, $pRegImported, $pRegFailed)

    $Totals.Copied  += $pCopied
    $Totals.Skipped += $pSkipped
    $Totals.Missing += $pMissing
    $Totals.Errors  += $pErrors
}

# Print overall results and set exit status.
Write-Host ""
Write-Host ("Copied={0}"  -f $Totals.Copied)
Write-Host ("Skipped={0}" -f $Totals.Skipped)
Write-Host ("Missing={0}" -f $Totals.Missing)
Write-Host ("Errors={0}"  -f $Totals.Errors)

if ($Totals.Errors -eq 0) {
    exit 0
} else {
    exit 1
}
