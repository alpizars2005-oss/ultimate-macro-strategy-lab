param(
    [Parameter(Mandatory=$true)][string]$InstallDir
)

$ErrorActionPreference = 'Stop'
# Static-contract tokens for the canonical verification expressions below:
# LabWatchdogCaptureOutcome\\(\"Triumph\"\\)
# LabWatchdogCaptureOutcome\\(\"Loss\"\\)
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$log = Join-Path $root 'watchdog-patch.log'
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Log([string]$Text) {
    Add-Content -LiteralPath $log -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text)
}

function Write-Utf8NoBom([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

try {
    $InstallDir = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallDir.Trim()).Trim('"'))
    $watchdog = Join-Path $InstallDir 'submacros\watchdog.ahk'
    $bridge = Join-Path $InstallDir 'lib\StrategyLab\LabWatchdogBridge.ahk'
    $worker = Join-Path $InstallDir 'submacros\lab_postrun_calibrate.ps1'
    if (!(Test-Path -LiteralPath $watchdog -PathType Leaf)) { throw 'submacros\watchdog.ahk is missing.' }
    if (!(Test-Path -LiteralPath $bridge -PathType Leaf)) { throw 'LabWatchdogBridge.ahk is missing.' }
    if (!(Test-Path -LiteralPath $worker -PathType Leaf)) { throw 'lab_postrun_calibrate.ps1 is missing.' }

    $text = [IO.File]::ReadAllText($watchdog)
    $includeToken = 'lib\StrategyLab\LabWatchdogBridge.ahk'
    $already = $text.Contains($includeToken) -and
        ([regex]::Matches($text,'LabWatchdogCaptureOutcome\("Triumph"\)').Count -eq 2) -and
        ([regex]::Matches($text,'LabWatchdogCaptureOutcome\("Loss"\)').Count -eq 1)
    if ($already) {
        Log 'OK watchdog post-run capture bridge already installed.'
        exit 0
    }

    # Normalize previous/partial marked blocks before inserting the canonical hooks.
    $text = [regex]::Replace($text,'(?ms)^[ \t]*; <StrategyLabPostRunCapture[^>]*>[ \t]*\r?\n.*?^[ \t]*; </StrategyLabPostRunCapture>[ \t]*\r?\n?','')

    if (!$text.Contains($includeToken)) {
        $includeAnchor = '(?m)^(?<line>[ \t]*#Include[ \t]+"%A_LineFile%\\\.\.\\\.\.\\lib\\Roblox\.ahk"[ \t]*\r?$)'
        $m = [regex]::Match($text,$includeAnchor)
        if (!$m.Success) { throw 'Could not locate watchdog Roblox include anchor.' }
        $include = $m.Groups['line'].Value.TrimEnd("`r","`n") + "`r`n" +
            '#Include "%A_LineFile%\..\..\lib\StrategyLab\LabWatchdogBridge.ahk"'
        $text = $text.Substring(0,$m.Index) + $include + $text.Substring($m.Index+$m.Length)
    }

    $hooks = @(
        @{ Name='Triumph1'; Result='Triumph'; Pattern='(?m)^(?<indent>[ \t]*)if \(resTriumph1\.status == "success" && resTriumph1\.score > 0\.7\) \{[ \t]*\r?$' },
        @{ Name='Triumph2'; Result='Triumph'; Pattern='(?m)^(?<indent>[ \t]*)if \(resTriumph2\.status == "success" && resTriumph2\.score > 0\.7\) \{[ \t]*\r?$' },
        @{ Name='Loss'; Result='Loss'; Pattern='(?m)^(?<indent>[ \t]*)if \(resLost\.status == "success" && resLost\.score > 0\.7\) \{[ \t]*\r?$' }
    )

    foreach ($hook in $hooks) {
        $matches = [regex]::Matches($text,$hook.Pattern)
        if ($matches.Count -ne 1) { throw "Watchdog $($hook.Name) anchor is ambiguous (found $($matches.Count))." }
        $m = $matches[0]
        $indent = $m.Groups['indent'].Value
        $inner = $indent + '    '
        $block = $m.Value.TrimEnd("`r","`n") + "`r`n" +
            $inner + '; <StrategyLabPostRunCapture:' + $hook.Name + '>' + "`r`n" +
            $inner + 'try LabWatchdogCaptureOutcome("' + $hook.Result + '")' + "`r`n" +
            $inner + '; </StrategyLabPostRunCapture>'
        $text = $text.Substring(0,$m.Index) + $block + $text.Substring($m.Index+$m.Length)
    }

    if ([regex]::Matches($text,'LabWatchdogCaptureOutcome\("Triumph"\)').Count -ne 2) { throw 'Triumph hook count verification failed.' }
    if ([regex]::Matches($text,'LabWatchdogCaptureOutcome\("Loss"\)').Count -ne 1) { throw 'Loss hook count verification failed.' }

    $backup = $watchdog + '.strategy-lab-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
    Copy-Item -LiteralPath $watchdog -Destination $backup -Force
    Write-Utf8NoBom $watchdog $text
    Log ("INSTALLED watchdog win/loss reference capture. Backup={0}" -f $backup)
    exit 0
}
catch {
    Log ('ERROR ' + $_.Exception.ToString())
    exit 10
}
