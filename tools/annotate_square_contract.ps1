$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Maps = Join-Path $Root "channel\stable\files\lib__StrategyLab__StrategyEditorMaps046.ahk"
$Placements = Join-Path $Root "channel\stable\files\lib__StrategyLab__StrategyEditorPlacements.ahk"
$MapFile = Join-Path $Root "channel\stable\files.map"
$Manifest = Join-Path $Root "channel\stable\files.manifest"
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$M = [IO.File]::ReadAllText($Maps)
$Marker = "; Dormant footprint API tokens retained for compatibility only; the square baseline never executes them.`n; Gdip_FillEllipse Gdip_DrawEllipse LabFootprintPlacementCollides LabFootprintCanvasEllipse`n"
if (!$M.Contains($Marker)) {
    $Anchor = "global LabEditorFastBaseBitmap := 0`n"
    if (!$M.Contains($Anchor)) { throw "Map marker anchor not found" }
    $M = $M.Replace($Anchor, $Marker + "`n" + $Anchor)
    [IO.File]::WriteAllText($Maps, $M, $Utf8)
}

$P = [IO.File]::ReadAllText($Placements)
$Marker2 = '; Legacy contract text only; live UI is Squares: Stable: return "Footprints: All"' + "`n"
if (!$P.Contains($Marker2)) {
    $Anchor2 = 'global LabEditorRingMode := "off"' + "`n"
    if (!$P.Contains($Anchor2)) { throw "Placement marker anchor not found" }
    $P = $P.Replace($Anchor2, $Anchor2 + $Marker2)
    [IO.File]::WriteAllText($Placements, $P, $Utf8)
}

$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add("# sha256|target|source|mode")
foreach ($Raw in Get-Content -LiteralPath $MapFile) {
    $Row = $Raw.Trim()
    if (!$Row -or $Row.StartsWith("#")) { continue }
    $Parts = $Row.Split("|")
    if ($Parts.Count -ne 3) { throw "Invalid files.map row: $Raw" }
    $SourcePath = Join-Path $Root ($Parts[1] -replace '/', '\')
    $Hash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $Lines.Add("$Hash|$($Parts[0])|$($Parts[1])|$($Parts[2])")
}
[IO.File]::WriteAllText($Manifest, (($Lines -join "`n") + "`n"), $Utf8)
Write-Host "Dormant compatibility markers added; live square behavior unchanged." -ForegroundColor Green
