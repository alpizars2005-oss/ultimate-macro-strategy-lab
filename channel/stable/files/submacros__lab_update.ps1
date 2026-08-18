param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [Parameter(Mandatory=$true)][string]$CacheDir,
    [Parameter(Mandatory=$true)][string]$ExpectedVersion,
    [Parameter(Mandatory=$true)][int]$ParentPid,
    [string]$LauncherPath = '',
    [string]$EntryScript = ''
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'Ultimate_Macro\StrategyLabUpdater'
$log = Join-Path $root 'update.log'
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Log([string]$Text) {
    Add-Content -LiteralPath $log -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Show-Message([string]$Text, [string]$Title='Strategy Lab Update') {
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Text, $Title) | Out-Null
    } catch {}
}

function Restart-StrategyLab {
    $runLab = Join-Path $InstallDir 'run_lab.bat'
    if (Test-Path -LiteralPath $runLab -PathType Leaf) {
        try {
            Start-Process -FilePath $runLab -WorkingDirectory $InstallDir | Out-Null
            Log 'Restarted Strategy Lab through run_lab.bat.'
            return $true
        } catch {
            Log ('run_lab.bat restart failed: ' + $_.Exception.Message)
        }
    }

    if (![string]::IsNullOrWhiteSpace($LauncherPath) -and
        ![string]::IsNullOrWhiteSpace($EntryScript) -and
        (Test-Path -LiteralPath $LauncherPath -PathType Leaf) -and
        (Test-Path -LiteralPath $EntryScript -PathType Leaf)) {
        try {
            Start-Process -FilePath $LauncherPath -ArgumentList ('"' + $EntryScript + '"') -WorkingDirectory $InstallDir | Out-Null
            Log 'Restarted Strategy Lab through the current AutoHotkey executable.'
            return $true
        } catch {
            Log ('AutoHotkey restart failed: ' + $_.Exception.Message)
        }
    }

    $mainLab = Join-Path $InstallDir 'Main_Lab.ahk'
    if (Test-Path -LiteralPath $mainLab -PathType Leaf) {
        try {
            Start-Process -FilePath $mainLab -WorkingDirectory $InstallDir | Out-Null
            Log 'Restarted Strategy Lab through Main_Lab.ahk shell association.'
            return $true
        } catch {
            Log ('Main_Lab.ahk restart failed: ' + $_.Exception.Message)
        }
    }

    Log 'Could not find a working Strategy Lab restart path.'
    return $false
}

function Restore-AppliedFiles($Applied, [string]$BackupRoot, [string]$TargetRoot) {
    if ($null -eq $Applied) { return }
    for ($i = $Applied.Count - 1; $i -ge 0; $i--) {
        $item = $Applied[$i]
        $target = Join-Path $TargetRoot $item.Relative
        $backupTarget = Join-Path $BackupRoot $item.Relative
        try {
            if ($item.HadOriginal -and (Test-Path -LiteralPath $backupTarget -PathType Leaf)) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                Copy-Item -LiteralPath $backupTarget -Destination $target -Force
            } elseif (!$item.HadOriginal -and (Test-Path -LiteralPath $target -PathType Leaf)) {
                Remove-Item -LiteralPath $target -Force
            }
        } catch {
            Log ('ROLLBACK WARNING ' + $item.Relative + ': ' + $_.Exception.Message)
        }
    }
}

try {
    $InstallDir = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallDir.Trim()).Trim('"'))
    $CacheDir = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CacheDir.Trim()).Trim('"'))

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }

    $channel = Join-Path $CacheDir 'channel\stable'
    $versionFile = Join-Path $channel 'version.ini'
    $manifestFile = Join-Path $channel 'files.manifest'
    if (!(Test-Path -LiteralPath $versionFile) -or !(Test-Path -LiteralPath $manifestFile)) {
        throw 'Update channel is incomplete.'
    }

    $versionText = Get-Content -LiteralPath $versionFile -Raw
    if ($versionText -notmatch '(?im)^Version\s*=\s*([^\r\n]+)') {
        throw 'Update channel has no version.'
    }
    $remoteVersion = $Matches[1].Trim()
    if ($remoteVersion -ne $ExpectedVersion) {
        throw "Expected version $ExpectedVersion but cache contains $remoteVersion."
    }

    $entries = @()
    foreach ($line in Get-Content -LiteralPath $manifestFile) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $parts = $line.Split('|')
        if ($parts.Count -ne 4) { throw "Invalid update manifest line: $line" }
        $hash = $parts[0].Trim().ToLowerInvariant()
        $rel = $parts[1].Trim().Replace('/', '\')
        $sourceRel = $parts[2].Trim().Replace('/', '\')
        $mode = $parts[3].Trim().ToLowerInvariant()
        if ($hash -notmatch '^[0-9a-f]{64}$') { throw "Invalid SHA-256 in manifest: $line" }
        if ($rel.Contains('..') -or [IO.Path]::IsPathRooted($rel)) { throw "Unsafe update target: $rel" }
        if ($sourceRel.Contains('..') -or [IO.Path]::IsPathRooted($sourceRel)) { throw "Unsafe update source: $sourceRel" }
        if ($mode -ne 'raw' -and $mode -ne 'base64') { throw "Unsupported update mode: $mode" }

        $lower = $rel.ToLowerInvariant()
        $allowed = ($lower -eq 'main_lab.ahk' -or $lower -eq 'run_lab.bat' -or
                    $lower -eq 'lab_readme.md' -or $lower -eq 'readme.md' -or
                    $lower.StartsWith('lib\') -or $lower.StartsWith('submacros\') -or
                    $lower.StartsWith('resources\'))
        if (!$allowed -or $lower.StartsWith('resources\strats\')) {
            throw "Update target is outside the Lab allow-list: $rel"
        }
        $entries += [PSCustomObject]@{ Hash=$hash; Relative=$rel; Source=$sourceRel; Mode=$mode }
    }
    if ($entries.Count -eq 0) { throw 'Update manifest is empty.' }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $stage = Join-Path $env:TEMP "UltimateMacroStrategyLab-stage-$stamp"
    $backup = Join-Path $root "backups\$stamp"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    New-Item -ItemType Directory -Force -Path $backup | Out-Null

    foreach ($entry in $entries) {
        $source = Join-Path $CacheDir $entry.Source
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing update source: $($entry.Source)" }

        $staged = Join-Path $stage $entry.Relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $staged) | Out-Null
        if ($entry.Mode -eq 'raw') {
            Copy-Item -LiteralPath $source -Destination $staged -Force
        } else {
            $base64 = (Get-Content -LiteralPath $source -Raw).Trim()
            [IO.File]::WriteAllBytes($staged, [Convert]::FromBase64String($base64))
        }
        $stageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $staged).Hash.ToLowerInvariant()
        if ($stageHash -ne $entry.Hash) { throw "Staging hash mismatch: $($entry.Relative)" }
    }

    $applied = @()
    try {
        foreach ($entry in $entries) {
            $target = Join-Path $InstallDir $entry.Relative
            $staged = Join-Path $stage $entry.Relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null

            $hadOriginal = Test-Path -LiteralPath $target -PathType Leaf
            if ($hadOriginal) {
                $backupTarget = Join-Path $backup $entry.Relative
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupTarget) | Out-Null
                Copy-Item -LiteralPath $target -Destination $backupTarget -Force
            }

            Copy-Item -LiteralPath $staged -Destination $target -Force
            $applied += [PSCustomObject]@{ Relative=$entry.Relative; HadOriginal=$hadOriginal }
        }

        # Validate the exact installed Main_Lab + all of its #Includes before declaring
        # the update successful. The probe runs an immediate-exit sibling copy, so no
        # gameplay code executes. A failure restores every file from this transaction.
        $syntaxProbe = Join-Path $InstallDir 'submacros\lab_syntax_probe.ps1'
        if (Test-Path -LiteralPath $syntaxProbe -PathType Leaf) {
            & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $syntaxProbe -InstallDir $InstallDir -Quiet
            if ($LASTEXITCODE -ne 0) {
                throw "Integrated AutoHotkey syntax validation failed (exit $LASTEXITCODE)."
            }
            Log 'Post-update integrated AutoHotkey syntax validation passed.'
        } else {
            throw 'The update did not install the required lab_syntax_probe.ps1 reliability helper.'
        }
    } catch {
        Restore-AppliedFiles $applied $backup $InstallDir
        Log ('ROLLBACK completed after apply/validation failure: ' + $_.Exception.Message)
        throw
    }

    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    $installedVersion = Join-Path $InstallDir 'lab_version.ini'
    [IO.File]::WriteAllText($installedVersion, "[Lab]`r`nVersion=$ExpectedVersion`r`n", (New-Object Text.UTF8Encoding($false)))
    Log "Updated Strategy Lab to $ExpectedVersion ($($entries.Count) files)."

    if (!(Restart-StrategyLab)) {
        Show-Message "Strategy Lab updated successfully, but Windows did not relaunch it automatically. Please open it once manually."
    }
} catch {
    Log ('UPDATE FAILED: ' + $_.Exception.Message)
    Show-Message ("Strategy Lab update failed safely. Your previous files were preserved/restored.`n`n" + $_.Exception.Message)
    try { Restart-StrategyLab | Out-Null } catch {}
    exit 1
}
