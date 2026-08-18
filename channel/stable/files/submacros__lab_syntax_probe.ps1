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

try {
    $candidate = [Environment]::ExpandEnvironmentVariables($InstallDir.Trim()).Trim('"')
    $InstallDir = [IO.Path]::GetFullPath($candidate)
    $main = Join-Path $InstallDir 'Main_Lab.ahk'
    $ahk = Join-Path $InstallDir 'submacros\AutoHotkey64.exe'

    if (!(Test-Path -LiteralPath $main -PathType Leaf)) { Fail "Main_Lab.ahk is missing: $main" 2 }
    if (!(Test-Path -LiteralPath $ahk -PathType Leaf)) { Fail "Bundled AutoHotkey64.exe is missing: $ahk" 3 }

    $text = [IO.File]::ReadAllText($main)
    if ($text -match '(?m)^(<<<<<<<|=======|>>>>>>>)') { Fail 'Main_Lab.ahk contains unresolved merge markers.' 4 }

    # AutoHotkey v2 has a purpose-built /Validate switch: it loads, optimizes and
    # validates the entire script (including #Includes) and then exits WITHOUT running
    # the auto-execute section. This is safer and deterministic compared with injecting
    # ExitApp into a temporary copy. /ErrorStdOut keeps load errors out of GUI dialogs.
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $ahk
    $psi.Arguments = '/Validate /ErrorStdOut=UTF-8 "' + $main + '"'
    $psi.WorkingDirectory = $InstallDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $psi
    if (!$proc.Start()) { Fail 'Could not start the bundled AutoHotkey validator.' 5 }

    # Read asynchronously enough to avoid pipe-buffer deadlocks while still enforcing a
    # bounded validation time.
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    if (!$proc.WaitForExit(20000)) {
        try { $proc.Kill() } catch {}
        Fail 'AutoHotkey /Validate timed out after 20 seconds.' 6
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $combined = (($stdout + "`r`n" + $stderr).Trim())

    if ($combined) { Log ('AHK ' + ($combined -replace "`r?`n", ' | ')) }
    if ($proc.ExitCode -ne 0 -or $combined -match '(?im)^Error:') {
        Fail ("Integrated AutoHotkey validation failed. See $logPath") 7
    }

    Log 'OK integrated Main_Lab + Strategy Lab /Validate passed.'
    if (!$Quiet) { Write-Host 'Strategy Lab AutoHotkey validation passed.' -ForegroundColor Green }
    exit 0
} catch {
    Fail ('syntax probe exception: ' + $_.Exception.Message) 10
}
