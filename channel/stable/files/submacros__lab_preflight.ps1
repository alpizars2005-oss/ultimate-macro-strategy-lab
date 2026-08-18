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
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
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
    Log ("BACKUP {0}: {1}" -f $Reason, $backup)
    return $backup
}

function Repair-StrayClear([string]$Text,[string]$Main,[ref]$Changed) {
    $pattern = '(?ms)^(?<indent>[ \t]*)Clear[ \t]*\r?\n(?=[ \t]*colors[ \t]*:=[ \t]*Map\(\)[ \t]*\r?\n[ \t]*colors\["Background"\])'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -gt 1) { throw "found $($matches.Count) candidate stray Clear lines; refusing ambiguous repair." }
    if ($matches.Count -eq 1) {
        Backup-Main $Main 'stray-Clear repair' | Out-Null
        $Text = [regex]::Replace($Text, $pattern, '', 1)
        $Changed.Value = $true
        Log 'REPAIRED stray Clear parser line.'
    }
    return $Text
}

function Install-RemoteBoundary([string]$Text,[string]$Main,[ref]$Changed) {
    if ($Text.Contains('LabRemoteConsumeBetweenMatches(&switched, &stratName)')) {
        Log 'OK remote between-match boundary already installed.'
        return $Text
    }

    # Ultimate Macro 1.3.x keeps this stable sequence at the beginning of RunStrategy.
    # We patch only that exact high-confidence boundary and never touch PlayStrategy().
    $pattern = '(?m)^(?<indent>[ \t]*)switched[ \t]*:=[ \t]*false[ \t]*\r?$'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -ne 1) {
        Log ("WARN remote boundary not installed: expected exactly one 'switched := false', found {0}." -f $matches.Count)
        return $Text
    }

    $m = $matches[0]
    $indent = $m.Groups['indent'].Value
    $hook = $m.Value + "`r`n" +
        $indent + 'stratName := IniRead(StateFile, "State", "Strategy", "")' + "`r`n" +
        $indent + '; Strategy Lab remote commands are consumed only between matches.' + "`r`n" +
        $indent + 'labRemoteAction := LabRemoteConsumeBetweenMatches(&switched, &stratName)' + "`r`n" +
        $indent + 'if (labRemoteAction = "stop")' + "`r`n" +
        $indent + '    return'

    Backup-Main $Main 'remote-boundary install' | Out-Null
    $Text = $Text.Substring(0, $m.Index) + $hook + $Text.Substring($m.Index + $m.Length)
    $Changed.Value = $true
    Log 'INSTALLED safe remote between-match boundary in RunStrategy().'
    return $Text
}

function Install-WebhookRemoteShortcut([string]$Text,[string]$Main,[ref]$Changed) {
    $event = 'Tab4_Title.OnEvent("Click", LabRemoteLaunchSettings)'
    if ($Text.Contains($event)) {
        Log 'OK Discord Webhook title remote shortcut already installed.'
        return $Text
    }

    # The upstream Webhook title is an ordinary Text control. Make that existing
    # "Discord Webhook" heading the discoverable entry-point Dark-style: clicking it
    # opens Strategy Lab's bot settings, while the original webhook controls remain.
    $pattern = '(?m)^(?<indent>[ \t]*)global[ \t]+Tab4_Title[ \t]*:=[^\r\n]*"Discord Webhook"[^\r\n]*\r?$'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -ne 1) {
        Log ("WARN Webhook remote shortcut not installed: expected one Discord Webhook title, found {0}." -f $matches.Count)
        return $Text
    }

    $m = $matches[0]
    $indent = $m.Groups['indent'].Value
    $replacement = $m.Value.TrimEnd("`r", "`n") + "`r`n" + $indent + $event
    Backup-Main $Main 'Webhook remote shortcut install' | Out-Null
    $Text = $Text.Substring(0, $m.Index) + $replacement + $Text.Substring($m.Index + $m.Length)
    $Changed.Value = $true
    Log 'INSTALLED Discord Webhook title -> Strategy Lab Remote settings shortcut.'
    return $Text
}

function Verify-LabModules([string]$InstallRoot) {
    $required = @(
        'lib\StrategyLab\StrategyEditorTab.ahk',
        'lib\StrategyLab\LabSafety.ahk',
        'lib\StrategyLab\LabStrategyValidation.ahk',
        'lib\StrategyLab\LabTelemetry.ahk',
        'lib\StrategyLab\LabRemoteGate.ahk',
        'submacros\lab_fingerprint.ps1',
        'submacros\lab_discord_worker.ps1',
        'submacros\lab_remote_settings.ps1'
    )
    $missing = @()
    foreach ($relative in $required) {
        if (!(Test-Path -LiteralPath (Join-Path $InstallRoot $relative) -PathType Leaf)) { $missing += $relative }
    }
    if ($missing.Count -gt 0) {
        Log ('WARN optional 0.3 modules missing locally: ' + ($missing -join ', ') + '. Run the Strategy Lab updater.')
    } else {
        Log 'OK Strategy Lab 0.3 module set present.'
    }
}

try {
    $installRoot = Normalize-InstallDir $InstallDir
    Log ("INFO InstallDir raw=<{0}> normalized=<{1}>" -f $InstallDir, $installRoot)

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

    $changed = $false
    $text = Repair-StrayClear $text $main ([ref]$changed)

    # Install remote integration only when the bridge module is actually present.
    $remoteGate = Join-Path $installRoot 'lib\StrategyLab\LabRemoteGate.ahk'
    if (Test-Path -LiteralPath $remoteGate -PathType Leaf) {
        $text = Install-RemoteBoundary $text $main ([ref]$changed)
        $text = Install-WebhookRemoteShortcut $text $main ([ref]$changed)
    } else {
        Log 'INFO remote bridge not installed yet; skipping remote Main_Lab hooks.'
    }

    if ($changed) { Write-Utf8NoBom $main $text }
    else { Log 'OK no Main_Lab source repair required.' }

    Verify-LabModules $installRoot
    exit 0
} catch {
    Log ('ERROR preflight exception: ' + $_.Exception.Message)
    exit 10
}
