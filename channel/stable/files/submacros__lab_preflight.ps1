param(
    [Parameter(Mandatory=$true)][string]$InstallDir
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$logPath = Join-Path $root 'preflight.log'
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Log([string]$Text) {
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Write-Utf8NoBom([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

function Normalize-InstallDir([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'InstallDir is empty.' }
    $candidate = [Environment]::ExpandEnvironmentVariables($Value.Trim()).Trim('"')
    if ([string]::IsNullOrWhiteSpace($candidate)) { throw 'InstallDir became empty after normalization.' }
    $full = [IO.Path]::GetFullPath($candidate)
    if (!(Test-Path -LiteralPath $full -PathType Container)) { throw "InstallDir does not exist: $full" }
    return $full
}

function Backup-Main([string]$Main,[string]$Reason) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = $Main + '.preflight-' + $stamp + '.bak'
    Copy-Item -LiteralPath $Main -Destination $backup -Force
    Log ("BACKUP {0}: {1}" -f $Reason,$backup)
    return $backup
}

function Repair-StrayClear([string]$Text,[string]$Main,[ref]$Changed) {
    $pattern = '(?ms)^(?<indent>[ \t]*)Clear[ \t]*\r?\n(?=[ \t]*colors[ \t]*:=[ \t]*Map\(\)[ \t]*\r?\n[ \t]*colors\["Background"\])'
    $matches = [regex]::Matches($Text,$pattern)
    if ($matches.Count -gt 1) { throw "found $($matches.Count) candidate stray Clear lines; refusing ambiguous repair." }
    if ($matches.Count -eq 1) {
        Backup-Main $Main 'stray-Clear repair' | Out-Null
        $Text = [regex]::Replace($Text,$pattern,'',1)
        $Changed.Value = $true
        Log 'REPAIRED stray Clear parser line.'
    }
    return $Text
}

function Install-RemoteBoundary([string]$Text,[string]$Main,[ref]$Changed) {
    $original = $Text
    $marked = '(?ms)^[ \t]*; <StrategyLabRemoteBoundary>[ \t]*\r?\n.*?^[ \t]*; </StrategyLabRemoteBoundary>[ \t]*\r?\n?'
    $Text = [regex]::Replace($Text,$marked,'')

    $legacy = '(?ms)^[ \t]*stratName[ \t]*:=[ \t]*IniRead\(StateFile,[ \t]*"State",[ \t]*"Strategy",[ \t]*""\)[ \t]*\r?\n[ \t]*; Strategy Lab remote commands are consumed only between matches\.[ \t]*\r?\n[ \t]*labRemoteAction[ \t]*:=[ \t]*LabRemoteConsumeBetweenMatches\(&switched,[ \t]*&stratName\)[ \t]*\r?\n[ \t]*if[ \t]*\(labRemoteAction[ \t]*=[ \t]*"stop"\)[ \t]*\r?\n[ \t]+return[ \t]*\r?\n?'
    $Text = [regex]::Replace($Text,$legacy,'')

    $pattern = '(?m)^(?<indent>[ \t]*)switched[ \t]*:=[ \t]*false[ \t]*\r?$'
    $matches = [regex]::Matches($Text,$pattern)
    if ($matches.Count -ne 1) {
        Log ("WARN remote boundary not installed: expected exactly one 'switched := false', found {0}." -f $matches.Count)
        return $original
    }

    $m = $matches[0]
    $indent = $m.Groups['indent'].Value
    $block = $m.Value.TrimEnd("`r","`n") + "`r`n" +
        $indent + '; <StrategyLabRemoteBoundary>' + "`r`n" +
        $indent + 'stratName := IniRead(StateFile, "State", "Strategy", "")' + "`r`n" +
        $indent + '; Strategy Lab remote commands are consumed only between matches.' + "`r`n" +
        $indent + 'labRemoteAction := LabRemoteConsumeBetweenMatches(&switched, &stratName)' + "`r`n" +
        $indent + 'if (labRemoteAction = "stop")' + "`r`n" +
        $indent + '    return' + "`r`n" +
        $indent + '; </StrategyLabRemoteBoundary>'

    $Text = $Text.Substring(0,$m.Index) + $block + $Text.Substring($m.Index + $m.Length)
    $count = [regex]::Matches($Text,'LabRemoteConsumeBetweenMatches\(&switched,[ \t]*&stratName\)').Count
    if ($count -ne 1) {
        Log ("WARN remote boundary normalization produced {0} consumers; refusing change." -f $count)
        return $original
    }

    if ($Text -ne $original) {
        Backup-Main $Main 'remote-boundary normalize' | Out-Null
        $Changed.Value = $true
        Log 'INSTALLED/NORMALIZED safe remote between-match boundary in RunStrategy().'
    } else {
        Log 'OK remote between-match boundary already normalized.'
    }
    return $Text
}

function Remove-ObsoleteTitleRemoteShortcut([string]$Text,[string]$Main,[ref]$Changed) {
    # 0.3.7+ has a real Discord Remote Button. Binding the existing Webhook Text title
    # to a second callback can open DiscordSettings and Lab Remote simultaneously.
    $pattern = '(?m)^[ \t]*Tab4_Title\.OnEvent\("Click",[ \t]*LabRemoteLaunchSettings\)[ \t]*\r?\n?'
    $matches = [regex]::Matches($Text,$pattern)
    if ($matches.Count -gt 0) {
        Backup-Main $Main 'remove obsolete Webhook title remote shortcut' | Out-Null
        $Text = [regex]::Replace($Text,$pattern,'')
        $Changed.Value = $true
        Log ("REMOVED {0} obsolete Webhook title remote shortcut(s)." -f $matches.Count)
    }
    return $Text
}

function Verify-LabModules([string]$InstallRoot) {
    $required = @(
        'lib\StrategyLab\StrategyEditorTab.ahk',
        'lib\StrategyLab\StrategyEditorPlacements.ahk',
        'lib\StrategyLab\LabSimpleFootprints.ahk',
        'lib\StrategyLab\LabStatsTab.ahk',
        'lib\StrategyLab\LabSafety.ahk',
        'lib\StrategyLab\LabStrategyValidation.ahk',
        'lib\StrategyLab\LabTelemetry.ahk',
        'lib\StrategyLab\LabRewardCatalog.ahk',
        'lib\StrategyLab\LabRewardTracker.ahk',
        'lib\StrategyLab\LabRemoteGate.ahk',
        'submacros\lab_fingerprint.ps1',
        'submacros\lab_discord_worker.ps1',
        'submacros\lab_remote_settings.ps1'
    )
    $missing = @()
    foreach ($relative in $required) {
        if (!(Test-Path -LiteralPath (Join-Path $InstallRoot $relative) -PathType Leaf)) { $missing += $relative }
    }
    if ($missing.Count -gt 0) { throw ('Required Strategy Lab modules are missing: ' + ($missing -join ', ')) }
    Log 'OK Strategy Lab required module set present.'
}

try {
    $installRoot = Normalize-InstallDir $InstallDir
    Log ("INFO InstallDir raw=<{0}> normalized=<{1}>" -f $InstallDir,$installRoot)

    $main = Join-Path $installRoot 'Main_Lab.ahk'
    if (!(Test-Path -LiteralPath $main -PathType Leaf)) {
        Log 'ERROR Main_Lab.ahk is missing.'
        exit 2
    }

    $text = [IO.File]::ReadAllText($main)
    if ($text -match '(?m)^(<<<<<<<|=======|>>>>>>>)') {
        Log 'ERROR unresolved merge markers detected in Main_Lab.ahk; refusing automatic repair.'
        exit 3
    }

    Verify-LabModules $installRoot

    $changed = $false
    $text = Repair-StrayClear $text $main ([ref]$changed)
    $text = Remove-ObsoleteTitleRemoteShortcut $text $main ([ref]$changed)

    $remoteGate = Join-Path $installRoot 'lib\StrategyLab\LabRemoteGate.ahk'
    if (Test-Path -LiteralPath $remoteGate -PathType Leaf) {
        $text = Install-RemoteBoundary $text $main ([ref]$changed)
    }

    if ($changed) { Write-Utf8NoBom $main $text }
    else { Log 'OK no Main_Lab source repair required.' }

    exit 0
} catch {
    Log ('ERROR preflight exception: ' + $_.Exception.Message)
    exit 10
}
