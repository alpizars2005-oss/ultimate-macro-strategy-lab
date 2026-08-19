param(
    [string[]]$SourceRoot,
    [switch]$IncludeRemoteVariant
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$UpstreamRoot = Join-Path $RepoRoot ".upstream-local"
$Desktop = [Environment]::GetFolderPath("Desktop")

function Write-Step {
    param([string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Add-LocalExclude {
    $excludePath = Join-Path $RepoRoot ".git\info\exclude"
    if (!(Test-Path -LiteralPath $excludePath)) {
        New-Item -ItemType File -Force -Path $excludePath | Out-Null
    }

    $rule = ".upstream-local/"
    $already = Select-String -LiteralPath $excludePath -SimpleMatch -Pattern $rule -Quiet -ErrorAction SilentlyContinue
    if (!$already) {
        Add-Content -LiteralPath $excludePath -Value $rule
    }
}

function Get-DefaultSources {
    $candidates = @(
        (Join-Path $Desktop "TDS_Macro")
    )

    if ($IncludeRemoteVariant) {
        $candidates += (Join-Path $Desktop "Ultimate_Macro_Remote")
    }

    return @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
}

function Test-UsefulFile {
    param([System.IO.FileInfo]$File)

    $name = $File.Name
    $ext = $File.Extension.ToLowerInvariant()

    if ($name -match '(?i)^AutoHotkey(32|64)?\.exe$') {
        return $true
    }

    return $ext -in @(
        '.ahk', '.ps1', '.bat', '.cmd', '.ini', '.json', '.yaml', '.yml',
        '.md', '.txt', '.cfg', '.conf', '.toml'
    )
}

function Copy-SourceSnapshot {
    param([string]$Root)

    $resolved = (Resolve-Path -LiteralPath $Root).Path
    $label = Split-Path -Leaf $resolved
    if ([string]::IsNullOrWhiteSpace($label)) {
        $label = "upstream"
    }

    $destRoot = Join-Path $UpstreamRoot $label
    if (Test-Path -LiteralPath $destRoot) {
        Remove-Item -LiteralPath $destRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $destRoot | Out-Null

    Write-Step "SNAPSHOT: $label"
    Write-Host "Source: $resolved" -ForegroundColor DarkGray
    Write-Host "Target: $destRoot" -ForegroundColor DarkGray

    $files = @(Get-ChildItem -LiteralPath $resolved -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { Test-UsefulFile $_ })

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($resolved.Length).TrimStart('\')
        $target = Join-Path $destRoot $relative
        $targetDir = Split-Path -Parent $target
        if (!(Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }

    $inventoryPath = Join-Path $destRoot "UPSTREAM_INVENTORY.txt"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("SourceRoot=$resolved")
    $lines.Add("CapturedAt=$(Get-Date -Format o)")
    $lines.Add("FileCount=$($files.Count)")
    $lines.Add("")

    foreach ($file in (Get-ChildItem -LiteralPath $destRoot -Recurse -File | Where-Object { $_.Name -ne 'UPSTREAM_INVENTORY.txt' } | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($destRoot.Length).TrimStart('\')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $lines.Add("$relative|$($file.Length)|$hash")
    }

    Set-Content -LiteralPath $inventoryPath -Value $lines -Encoding UTF8

    $ahkFiles = @(Get-ChildItem -LiteralPath $destRoot -Recurse -File -Filter '*.ahk')
    $mainCandidates = @($ahkFiles | Sort-Object Length -Descending | Select-Object -First 10)

    Write-Host "Captured source-like files: $($files.Count)" -ForegroundColor Green
    Write-Host "AHK files: $($ahkFiles.Count)" -ForegroundColor Green

    if ($mainCandidates.Count -gt 0) {
        Write-Host "`nLargest AHK candidates (useful for identifying the real upstream entry point):" -ForegroundColor Yellow
        $mainCandidates |
            Select-Object @{N='Path';E={$_.FullName.Substring($destRoot.Length).TrimStart('\')}}, Length |
            Format-Table -AutoSize
    }

    $watchdogs = @($ahkFiles | Where-Object { $_.Name -match '(?i)watchdog' })
    $gdip = @($ahkFiles | Where-Object { $_.Name -match '(?i)gdip' })
    $runtimes = @(Get-ChildItem -LiteralPath $destRoot -Recurse -File | Where-Object { $_.Name -match '(?i)^AutoHotkey(32|64)?\.exe$' })

    Write-Host "Watchdog-like AHK files: $($watchdogs.Count)" -ForegroundColor DarkGray
    Write-Host "GDI+-like AHK files: $($gdip.Count)" -ForegroundColor DarkGray
    Write-Host "AutoHotkey runtimes: $($runtimes.Count)" -ForegroundColor DarkGray

    return $destRoot
}

Write-Step "PREPARE LOCAL UPSTREAM EVIDENCE"
Write-Host "Repository: $RepoRoot" -ForegroundColor Green

if (!(Test-Path -LiteralPath (Join-Path $RepoRoot '.git') -PathType Container)) {
    throw "This script must be run from the cloned ultimate-macro-strategy-lab repository."
}

Add-LocalExclude
New-Item -ItemType Directory -Force -Path $UpstreamRoot | Out-Null

$sources = @()
if ($SourceRoot -and $SourceRoot.Count -gt 0) {
    $sources = @($SourceRoot | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
} else {
    $sources = @(Get-DefaultSources)
}

if ($sources.Count -eq 0) {
    Write-Host "No source folder was found automatically." -ForegroundColor Red
    Write-Host "Run for example:" -ForegroundColor Yellow
    Write-Host '.\tools\prepare_upstream_local.ps1 -SourceRoot "C:\Users\YOUR_USER\Desktop\TDS_Macro"' -ForegroundColor Yellow
    exit 2
}

$captured = @()
foreach ($source in $sources) {
    $captured += Copy-SourceSnapshot -Root $source
}

Write-Step "RESULT"
Write-Host "Local evidence root: $UpstreamRoot" -ForegroundColor Green
Write-Host "This directory is excluded only through .git/info/exclude and is NOT committed." -ForegroundColor DarkGray

Write-Host "`nGit status:" -ForegroundColor Cyan
& git -C $RepoRoot status --short

Write-Host "`nCopilot can now audit the snapshots below:" -ForegroundColor Green
$captured | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }

Write-Host "`nDone." -ForegroundColor Green
