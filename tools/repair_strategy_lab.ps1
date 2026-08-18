param(
    [string]$InstallDir = (Get-Location).Path,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$RepoRawBase = 'https://raw.githubusercontent.com/alpizars2005-oss/ultimate-macro-strategy-lab/main/'
$repairRoot = Join-Path $env:LOCALAPPDATA 'Ultimate_Macro\StrategyLabRepair'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $repairRoot "backups\$stamp"
$logPath = Join-Path $repairRoot 'repair.log'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

function Log([string]$Text) {
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Raw-Url([string]$Relative) {
    $parts = $Relative.Replace('\','/').Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }
    return $RepoRawBase + ($parts -join '/')
}

function Download-Bytes([string]$Relative) {
    $wc = New-Object Net.WebClient
    $wc.Headers['User-Agent'] = 'UltimateMacroStrategyLab-Repair/1.0'
    try { return $wc.DownloadData((Raw-Url $Relative)) }
    finally { $wc.Dispose() }
}

function Sha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Safe-Target([string]$Relative) {
    $rel = $Relative.Replace('/','\')
    if ($rel.Contains('..') -or [IO.Path]::IsPathRooted($rel)) { return $false }
    $lower = $rel.ToLowerInvariant()
    if ($lower.StartsWith('resources\strats\')) { return $false }
    return ($lower -eq 'run_lab.bat' -or $lower -eq 'lab_readme.md' -or
            $lower.StartsWith('lib\strategylab\') -or
            $lower.StartsWith('submacros\lab_') -or
            $lower.StartsWith('resources\strategylab\'))
}

function Stop-RunningLab([string]$Root) {
    try {
        $normalized = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        $procs = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.Name -match '^AutoHotkey.*\.exe$' -and $_.CommandLine -and
            $_.CommandLine.IndexOf('Main_Lab.ahk',[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $_.CommandLine.IndexOf($normalized,[StringComparison]::OrdinalIgnoreCase) -ge 0
        }
        foreach ($p in $procs) {
            Log ("Stopping running Strategy Lab PID {0}" -f $p.ProcessId)
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Log ('INFO could not enumerate running Lab processes: ' + $_.Exception.Message)
    }
}

try {
    $InstallDir = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallDir.Trim()).Trim('"'))
    if (!(Test-Path -LiteralPath $InstallDir -PathType Container)) { throw "Install directory does not exist: $InstallDir" }
    if (!(Test-Path -LiteralPath (Join-Path $InstallDir 'Main_Lab.ahk') -PathType Leaf)) {
        throw "Main_Lab.ahk was not found in: $InstallDir`nPlace this repair script inside the Strategy Lab folder or pass -InstallDir."
    }

    Log ("BEGIN repair install={0}" -f $InstallDir)
    Stop-RunningLab $InstallDir

    $versionBytes = Download-Bytes 'channel/stable/version.ini'
    $versionText = [Text.Encoding]::UTF8.GetString($versionBytes)
    if ($versionText -notmatch '(?im)^Version\s*=\s*([^\r\n]+)') { throw 'Stable channel version.ini is invalid.' }
    $stableVersion = $Matches[1].Trim()

    $manifestBytes = Download-Bytes 'channel/stable/files.manifest'
    $manifestText = [Text.Encoding]::UTF8.GetString($manifestBytes)
    $entries = @()

    foreach ($raw in ($manifestText -split "`r?`n")) {
        $line = $raw.Trim()
        if (!$line -or $line.StartsWith('#')) { continue }
        $parts = $line.Split('|')
        if ($parts.Count -ne 4) { throw "Invalid stable manifest line: $line" }
        $hash = $parts[0].Trim().ToLowerInvariant()
        $target = $parts[1].Trim().Replace('/','\')
        $source = $parts[2].Trim().Replace('\','/')
        $mode = $parts[3].Trim().ToLowerInvariant()
        if ($hash -notmatch '^[0-9a-f]{64}$') { throw "Invalid SHA-256 in manifest: $line" }
        if (!(Safe-Target $target)) { continue } # Ignore non-Lab/upstream files defensively.
        if ($mode -ne 'raw' -and $mode -ne 'base64') { throw "Unsupported mode: $mode" }
        $entries += [PSCustomObject]@{ Hash=$hash; Target=$target; Source=$source; Mode=$mode }
    }
    if ($entries.Count -lt 10) { throw 'Stable manifest did not contain the expected Strategy Lab module set.' }

    Write-Host "Strategy Lab recovery: downloading verified stable $stableVersion ..." -ForegroundColor Cyan
    $written = @()
    foreach ($entry in $entries) {
        $sourceBytes = Download-Bytes $entry.Source
        if ($entry.Mode -eq 'base64') {
            $b64 = [Text.Encoding]::ASCII.GetString($sourceBytes).Trim()
            $payload = [Convert]::FromBase64String($b64)
        } else {
            $payload = $sourceBytes
        }

        $actual = Sha256 $payload
        if ($actual -ne $entry.Hash) { throw "Hash mismatch for $($entry.Target). Expected $($entry.Hash), got $actual" }

        $targetPath = Join-Path $InstallDir $entry.Target
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            $backupPath = Join-Path $backupRoot $entry.Target
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
            Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
        }

        $tmp = $targetPath + '.repair.tmp'
        [IO.File]::WriteAllBytes($tmp, $payload)
        Move-Item -LiteralPath $tmp -Destination $targetPath -Force
        $written += $entry.Target
    }

    # Mark the recovered module version only after every download/hash succeeds.
    [IO.File]::WriteAllText((Join-Path $InstallDir 'lab_version.ini'), "[Lab]`r`nVersion=$stableVersion`r`n", (New-Object Text.UTF8Encoding($false)))

    $preflight = Join-Path $InstallDir 'submacros\lab_preflight.ps1'
    if (Test-Path -LiteralPath $preflight -PathType Leaf) {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $preflight -InstallDir $InstallDir
        if ($LASTEXITCODE -ne 0) { throw "Preflight failed with exit code $LASTEXITCODE. See %APPDATA%\Ultimate_Macro\StrategyEditor\preflight.log" }
    }

    $probe = Join-Path $InstallDir 'submacros\lab_syntax_probe.ps1'
    if (!(Test-Path -LiteralPath $probe -PathType Leaf)) { throw 'Recovery installed no syntax probe; stable channel is incomplete.' }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $probe -InstallDir $InstallDir
    if ($LASTEXITCODE -ne 0) {
        throw "Integrated AutoHotkey syntax check still failed. See %APPDATA%\Ultimate_Macro\StrategyEditor\syntax-probe.log. Backups are in $backupRoot"
    }

    Log ("SUCCESS repaired to {0}; files={1}" -f $stableVersion,$written.Count)
    Write-Host "`nSUCCESS: Strategy Lab $stableVersion passed the integrated syntax check." -ForegroundColor Green
    Write-Host "Backup: $backupRoot" -ForegroundColor DarkGray

    if (!$NoLaunch) {
        $launcher = Join-Path $InstallDir 'run_lab.bat'
        if (Test-Path -LiteralPath $launcher -PathType Leaf) {
            Start-Process -FilePath $launcher -WorkingDirectory $InstallDir | Out-Null
            Write-Host 'Strategy Lab is starting...' -ForegroundColor Green
        }
    }
} catch {
    Log ('FAILED ' + $_.Exception.ToString())
    Write-Host "`nREPAIR FAILED SAFELY" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nNothing in Resources\Strats was touched." -ForegroundColor Yellow
    Write-Host "Log: $logPath" -ForegroundColor Yellow
    Write-Host "Backup: $backupRoot" -ForegroundColor Yellow
    exit 1
}
