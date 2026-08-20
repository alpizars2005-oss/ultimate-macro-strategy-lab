param([switch]$Restore)
$ErrorActionPreference = "Stop"
$Helper = Join-Path $PSScriptRoot "apply_square_editor_baseline.ps1"
$SearchRoots = @(
    [Environment]::GetFolderPath("Desktop"),
    (Join-Path $env:APPDATA "Ultimate_Macro")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

Write-Host "`n=== LOCATING STRATEGY LAB ===" -ForegroundColor Cyan
$installs = @()
foreach ($root in $SearchRoots) {
    Write-Host "Searching: $root" -ForegroundColor DarkGray
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter "StrategyEditorMaps046.ahk" -ErrorAction SilentlyContinue) {
        $strategyLabDir = Split-Path -Parent $file.FullName
        $libDir = Split-Path -Parent $strategyLabDir
        $installDir = Split-Path -Parent $libDir
        if (Test-Path -LiteralPath (Join-Path $installDir "lib\StrategyLab\StrategyEditorUi.ahk")) {
            $installs += [System.IO.Path]::GetFullPath($installDir)
        }
    }
}
$installs = @($installs | Select-Object -Unique)

if ($installs.Count -eq 0) {
    Write-Host "No Strategy Lab installation was found under Desktop or AppData." -ForegroundColor Red
    Write-Host "Nothing was changed." -ForegroundColor Yellow
    exit 2
}
if ($installs.Count -gt 1) {
    Write-Host "More than one installation was found; nothing was changed:" -ForegroundColor Yellow
    $installs | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    Write-Host "Run apply_square_editor_baseline.ps1 with -InstallDir and the correct path." -ForegroundColor Cyan
    exit 3
}

$install = $installs[0]
Write-Host "Found: $install" -ForegroundColor Green
if ($Restore) {
    & powershell.exe -ExecutionPolicy Bypass -File $Helper -InstallDir $install -Restore
} else {
    & powershell.exe -ExecutionPolicy Bypass -File $Helper -InstallDir $install
}
exit $LASTEXITCODE
