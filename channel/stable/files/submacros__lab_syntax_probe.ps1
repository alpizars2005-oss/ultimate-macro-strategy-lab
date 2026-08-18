param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor'
$logPath = Join-Path $root 'syntax-probe.log'
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Log([string]$Text) {
    try { Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text) } catch {}
}

function Fail([string]$Message, [int]$Code = 1) {
    Log ('ERROR ' + $Message)
    if (!$Quiet) { Write-Host $Message -ForegroundColor Red }
    exit $Code
}

$probePath = $null
try {
    $candidate = [Environment]::ExpandEnvironmentVariables($InstallDir.Trim()).Trim('"')
    $InstallDir = [IO.Path]::GetFullPath($candidate)
    $main = Join-Path $InstallDir 'Main_Lab.ahk'
    $ahk = Join-Path $InstallDir 'submacros\AutoHotkey64.exe'

    if (!(Test-Path -LiteralPath $main -PathType Leaf)) { Fail "Main_Lab.ahk is missing: $main" 2 }
    if (!(Test-Path -LiteralPath $ahk -PathType Leaf)) { Fail "Bundled AutoHotkey64.exe is missing: $ahk" 3 }

    $text = [IO.File]::ReadAllText($main)
    if ($text -match '(?m)^(<<<<<<<|=======|>>>>>>>)') { Fail 'Main_Lab.ahk contains unresolved merge markers.' 4 }

    # AutoHotkey parses the complete script (including #Include files) before it runs
    # the first statement. Insert an immediate ExitApp into a temporary sibling copy:
    # runtime side effects never happen, while parser/arity/include errors still fail.
    $insertAt = 0
    $m = [regex]::Match($text, '(?m)^#SingleInstance[^\r\n]*(?:\r?\n|$)')
    if ($m.Success) {
        $insertAt = $m.Index + $m.Length
    } else {
        $m = [regex]::Match($text, '(?m)^#Requires[^\r\n]*(?:\r?\n|$)')
        if ($m.Success) { $insertAt = $m.Index + $m.Length }
    }

    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $probeText = $text.Substring(0, $insertAt) + 'ExitApp()' + $newline + $text.Substring($insertAt)
    $probePath = Join-Path $InstallDir 'Main_Lab.__strategy_lab_syntax_probe.ahk'
    [IO.File]::WriteAllText($probePath, $probeText, (New-Object Text.UTF8Encoding($false)))

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $ahk
    $psi.Arguments = '/ErrorStdOut "' + $probePath + '"'
    $psi.WorkingDirectory = $InstallDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $psi
    if (!$proc.Start()) { Fail 'Could not start the bundled AutoHotkey parser.' 5 }

    if (!$proc.WaitForExit(20000)) {
        try { $proc.Kill() } catch {}
        Fail 'AutoHotkey syntax probe timed out after 20 seconds.' 6
    }

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $combined = (($stdout + "`r`n" + $stderr).Trim())

    if ($proc.ExitCode -ne 0 -or $combined -match '(?im)^Error:') {
        if ($combined) { Log ('AHK ' + ($combined -replace "`r?`n", ' | ')) }
        Fail ("Integrated AutoHotkey syntax check failed. See $logPath") 7
    }

    Log 'OK integrated Main_Lab + Strategy Lab syntax probe passed.'
    if (!$Quiet) { Write-Host 'Strategy Lab syntax check passed.' -ForegroundColor Green }
    exit 0
} catch {
    Fail ('syntax probe exception: ' + $_.Exception.Message) 10
} finally {
    if ($probePath -and (Test-Path -LiteralPath $probePath)) {
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
    }
}
