param(
    [string]$InstallDir = (Get-Location).Path,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/alpizars2005-oss/ultimate-macro-strategy-lab.git'
$repairRoot = Join-Path $env:LOCALAPPDATA 'Ultimate_Macro\StrategyLabRepair'
$updaterRoot = Join-Path $env:LOCALAPPDATA 'Ultimate_Macro\StrategyLabUpdater'
$cacheRepo = Join-Path $updaterRoot 'repo'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $repairRoot "backups\$stamp"
$logPath = Join-Path $repairRoot 'repair.log'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
New-Item -ItemType Directory -Force -Path $updaterRoot | Out-Null

function Log([string]$Text) {
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Run-Git([string[]]$Arguments, [switch]$Visible) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'git.exe'
    $psi.WorkingDirectory = $updaterRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = !$Visible
    $psi.RedirectStandardOutput = !$Visible
    $psi.RedirectStandardError = !$Visible
    # .NET ProcessStartInfo on Windows PowerShell has no ArgumentList collection. Quote
    # each value ourselves; these arguments are controlled by this script, not user input.
    $quoted = foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]') { '"' + ($arg -replace '"','\"') + '"' } else { $arg }
    }
    $psi.Arguments = ($quoted -join ' ')
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    if (!$p.Start()) { throw 'Could not launch git.exe.' }
    $p.WaitForExit()
    if (!$Visible) {
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        if ($out) { Log ('GIT OUT ' + ($out.Trim() -replace "`r?`n", ' | ')) }
        if ($err) { Log ('GIT ERR ' + ($err.Trim() -replace "`r?`n", ' | ')) }
    }
    return $p.ExitCode
}

function Refresh-PrivateCache {
    try { & git.exe --version *> $null } catch { throw 'Git for Windows is required. Install Git or use the existing Strategy Lab updater cache.' }

    if (!(Test-Path -LiteralPath (Join-Path $cacheRepo '.git') -PathType Container)) {
        if (Test-Path -LiteralPath $cacheRepo) { Remove-Item -LiteralPath $cacheRepo -Recurse -Force }
        Write-Host 'Connecting to the private Strategy Lab repository...' -ForegroundColor Cyan
        Write-Host 'GitHub may open your browser once through Git Credential Manager.' -ForegroundColor DarkGray
        Log 'CACHE cloning private repository through Git Credential Manager.'
        $code = Run-Git @('clone','--depth','1','--branch','main',$RepoUrl,$cacheRepo) -Visible
        if ($code -ne 0 -or !(Test-Path -LiteralPath (Join-Path $cacheRepo '.git') -PathType Container)) {
            throw "Private repository clone failed (git exit $code). Complete any GitHub sign-in window and run the repair again."
        }
        return
    }

    Log 'CACHE refreshing existing private updater repository.'
    $code = Run-Git @('-C',$cacheRepo,'fetch','--quiet','--depth','1','origin','main')
    if ($code -ne 0) { throw "Could not fetch the private Strategy Lab repository (git exit $code)." }
    $code = Run-Git @('-C',$cacheRepo,'reset','--quiet','--hard','FETCH_HEAD')
    if ($code -ne 0) { throw "Could not reset the private Strategy Lab cache (git exit $code)." }
}

function Sha256File([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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
    Refresh-PrivateCache

    $channel = Join-Path $cacheRepo 'channel\stable'
    $versionPath = Join-Path $channel 'version.ini'
    $manifestPath = Join-Path $channel 'files.manifest'
    if (!(Test-Path -LiteralPath $versionPath -PathType Leaf) -or !(Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Private update cache is incomplete (version.ini/files.manifest missing).'
    }

    $versionText = Get-Content -LiteralPath $versionPath -Raw
    if ($versionText -notmatch '(?im)^Version\s*=\s*([^\r\n]+)') { throw 'Stable channel version.ini is invalid.' }
    $stableVersion = $Matches[1].Trim()

    $entries = @()
    foreach ($raw in Get-Content -LiteralPath $manifestPath) {
        $line = $raw.Trim()
        if (!$line -or $line.StartsWith('#')) { continue }
        $parts = $line.Split('|')
        if ($parts.Count -ne 4) { throw "Invalid stable manifest line: $line" }
        $hash = $parts[0].Trim().ToLowerInvariant()
        $target = $parts[1].Trim().Replace('/','\')
        $source = $parts[2].Trim().Replace('/','\')
        $mode = $parts[3].Trim().ToLowerInvariant()
        if ($hash -notmatch '^[0-9a-f]{64}$') { throw "Invalid SHA-256 in manifest: $line" }
        if (!(Safe-Target $target)) { continue }
        if ($mode -ne 'raw' -and $mode -ne 'base64') { throw "Unsupported mode: $mode" }
        $sourcePath = Join-Path $cacheRepo $source
        if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Stable source is missing: $source" }
        $entries += [PSCustomObject]@{ Hash=$hash; Target=$target; SourcePath=$sourcePath; Mode=$mode }
    }
    if ($entries.Count -lt 10) { throw 'Stable manifest did not contain the expected Strategy Lab module set.' }

    Write-Host "Strategy Lab recovery: restoring verified stable $stableVersion ..." -ForegroundColor Cyan
    $written = @()
    foreach ($entry in $entries) {
        $targetPath = Join-Path $InstallDir $entry.Target
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null

        $stage = Join-Path $env:TEMP ('strategy-lab-repair-' + [guid]::NewGuid().ToString('N'))
        if ($entry.Mode -eq 'base64') {
            $base64 = (Get-Content -LiteralPath $entry.SourcePath -Raw).Trim()
            [IO.File]::WriteAllBytes($stage, [Convert]::FromBase64String($base64))
        } else {
            Copy-Item -LiteralPath $entry.SourcePath -Destination $stage -Force
        }

        $actual = Sha256File $stage
        if ($actual -ne $entry.Hash) {
            Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue
            throw "Hash mismatch for $($entry.Target). Expected $($entry.Hash), got $actual"
        }

        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            $backupPath = Join-Path $backupRoot $entry.Target
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
            Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
        }

        Move-Item -LiteralPath $stage -Destination $targetPath -Force
        $written += $entry.Target
    }

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

    # Mark recovered version only after preflight AND the real bundled AutoHotkey parser pass.
    [IO.File]::WriteAllText((Join-Path $InstallDir 'lab_version.ini'), "[Lab]`r`nVersion=$stableVersion`r`n", (New-Object Text.UTF8Encoding($false)))

    Log ("SUCCESS repaired to {0}; files={1}" -f $stableVersion,$written.Count)
    Write-Host "`nSUCCESS: Strategy Lab $stableVersion passed the integrated AutoHotkey syntax check." -ForegroundColor Green
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
    Write-Host "`nResources\Strats was NOT touched." -ForegroundColor Yellow
    Write-Host "Log: $logPath" -ForegroundColor Yellow
    Write-Host "Backup: $backupRoot" -ForegroundColor Yellow
    exit 1
}
