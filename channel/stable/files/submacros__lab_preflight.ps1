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

try {
    $main = Join-Path $InstallDir 'Main_Lab.ahk'
    if (!(Test-Path -LiteralPath $main -PathType Leaf)) {
        Log 'ERROR Main_Lab.ahk is missing.'
        exit 2
    }

    $text = [IO.File]::ReadAllText($main)

    # Never touch a file that appears to contain an unresolved source-control merge.
    if ($text -match '(?m)^(<<<<<<<|=======|>>>>>>>)') {
        Log 'ERROR unresolved merge markers detected in Main_Lab.ahk; refusing automatic repair.'
        exit 3
    }

    # Live Windows testing exposed one local package with an isolated bare `Clear`
    # immediately before the theme color map. `Clear` is not a valid AHK v2 action,
    # so the parser exits before Strategy Lab can even reach its updater. Repair only
    # this exact, high-confidence signature; never delete arbitrary lines named Clear.
    $pattern = '(?ms)^(?<indent>[ \t]*)Clear[ \t]*\r?\n(?=[ \t]*colors[ \t]*:=[ \t]*Map\(\)[ \t]*\r?\n[ \t]*colors\["Background"\])'
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -gt 1) {
        Log "ERROR found $($matches.Count) candidate stray Clear lines; refusing ambiguous repair."
        exit 4
    }

    if ($matches.Count -eq 1) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = $main + '.preflight-' + $stamp + '.bak'
        Copy-Item -LiteralPath $main -Destination $backup -Force
        $fixed = [regex]::Replace($text, $pattern, '', 1)
        Write-Utf8NoBom $main $fixed
        Log "REPAIRED stray Clear parser line. Backup: $backup"
    } else {
        Log 'OK no known Main_Lab parser corruption detected.'
    }

    exit 0
} catch {
    Log ('ERROR preflight exception: ' + $_.Exception.Message)
    exit 10
}
