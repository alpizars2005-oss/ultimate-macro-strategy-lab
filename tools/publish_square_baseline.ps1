$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Stable = Join-Path $Root "channel\stable"
$Files = Join-Path $Stable "files"
$Maps = Join-Path $Files "lib__StrategyLab__StrategyEditorMaps046.ahk"
$Placements = Join-Path $Files "lib__StrategyLab__StrategyEditorPlacements.ahk"
$Ui = Join-Path $Files "lib__StrategyLab__StrategyEditorUi.ahk"
$Test = Join-Path $Root "tests\editor_canvas_runtime_test.ahk"
$MapFile = Join-Path $Stable "files.map"
$Manifest = Join-Path $Stable "files.manifest"
$Version = Join-Path $Stable "version.ini"
$NL = [Environment]::NewLine
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function ReadText([string]$P) { [IO.File]::ReadAllText($P) }
function WriteText([string]$P, [string]$T) { [IO.File]::WriteAllText($P, $T, $Utf8) }
function One([string]$T,[string]$Pattern,[string]$Replacement,[string]$Label) {
    $Rx = [regex]::new($Pattern,[Text.RegularExpressions.RegexOptions]::Singleline)
    $N = $Rx.Matches($T).Count
    if ($N -ne 1) { throw "$Label expected 1 match, found $N" }
    $Rx.Replace($T,$Replacement,1)
}

foreach ($P in @($Maps,$Placements,$Ui,$Test,$MapFile,$Manifest,$Version)) {
    if (!(Test-Path -LiteralPath $P)) { throw "Missing required file: $P" }
}
if ((ReadText $Version) -match '(?m)^Version=0\.4\.10\s*$') {
    Write-Host "0.4.10 already published."
    exit 0
}

# Keep the modern single-canvas renderer and exact map projection, but replace only
# the placement visual with the dependable 18/22px numbered square baseline.
$M = ReadText $Maps
$Square = @'
StrategyEditorDrawPlacement(graphics, index, placement, point, collisions, fast := false) {
    global LabEditorSelectedRow
    selected := index = LabEditorSelectedRow
    markerSize := selected ? 22 : 18
    half := markerSize / 2.0
    border := selected ? 2 : 1

    borderBrush := 0
    fillBrush := 0
    try {
        borderBrush := Gdip_BrushCreateSolid(selected ? 0xFFFFFFFF : 0xFF20252B)
        if borderBrush
            Gdip_FillRectangle(graphics, borderBrush, point.x - half, point.y - half, markerSize, markerSize)
        fillBrush := Gdip_BrushCreateSolid(StrategyEditorSlotColor(placement.slot, 255))
        if fillBrush
            Gdip_FillRectangle(graphics, fillBrush, point.x - half + border, point.y - half + border,
                markerSize - (border * 2), markerSize - (border * 2))
    } finally {
        if fillBrush
            try Gdip_DeleteBrush(fillBrush)
        if borderBrush
            try Gdip_DeleteBrush(borderBrush)
    }

    label := StrategyEditorMarkerLabel(placement)
    options := "x" (point.x - half) " y" (point.y - half)
        . " w" markerSize " h" markerSize " Center vCenter cFFFFFFFF s7 Bold"
    try Gdip_TextToGraphics(graphics, label, options, "Segoe UI")
}

StrategyEditorDrawSource
'@
$M = One $M 'StrategyEditorDrawPlacement\(graphics, index, placement, point, collisions, fast := false\) \{.*?\r?\n\}\r?\n\r?\nStrategyEditorDrawSource' $Square "renderer"
$M = One $M 'collision := Map\(\)\r?\n\s*if LabFootprintPlacementCollides\(dragIndex, LabEditorDoc\)\r?\n\s*collision\[dragIndex\] := true\r?\n\s*StrategyEditorDrawPlacement\(g, dragIndex, item\.placement, item\.point, collision, true\)' ("collision := Map()"+$NL+"                StrategyEditorDrawPlacement(g, dragIndex, item.placement, item.point, collision, true)") "drag collision"
$M = One $M 'collisions := IsObject\(LabEditorDoc\) \? LabFootprintCollisionMap\(LabEditorDoc\) : Map\(\)' 'collisions := Map()' "idle collision"
$M = $M.Replace("drag: cached 438x238 static base + ONE moving footprint","drag: cached 438x238 static base + ONE moving square marker")
$M = $M.Replace("Panning needs only the terrain. Footprints return on the guaranteed final mouse-up","Panning needs only the terrain. Square markers return on the guaranteed final mouse-up")

# Pause the footprint UI and warnings. Geometry/calibration source remains untouched.
$P = ReadText $Placements
$P = One $P 'global LabEditorRingMode := "all"' 'global LabEditorRingMode := "off"' "ring default"
$RingButton = @'
StrategyEditorRingButtonText() {
    return "Squares: Stable"
}
'@
$P = One $P 'StrategyEditorRingButtonText\(\) \{.*?\r?\n\}' $RingButton.TrimEnd() "ring label"

$RingToggle = @'
StrategyEditorToggleRings(*) {
    global LabEditorRingMode, LabEditorRingsBtn
    LabEditorRingMode := "off"
    if LabEditorControlAlive(LabEditorRingsBtn)
        try LabEditorRingsBtn.Text := StrategyEditorRingButtonText()
    StrategyEditorSetStatus("Stable square-marker baseline active. Footprint geometry is preserved for a later opt-in pass.")
}
'@
$P = One $P 'StrategyEditorToggleRings\(\*\) \{.*?\r?\n\}' $RingToggle.TrimEnd() "ring toggle"
$Apply = @'
StrategyEditorApplyCoordinates(*) {
    global LabEditorDoc, LabEditorSelectedRow, LabEditorXCtrl, LabEditorYCtrl
    if !IsObject(LabEditorDoc) || LabEditorSelectedRow < 1 {
        StrategyEditorSetStatus("Select a placement first.", true)
        return
    }
    if !LabEditorControlAlive(LabEditorXCtrl) || !LabEditorControlAlive(LabEditorYCtrl)
        return
    if !IsNumber(LabEditorXCtrl.Text) || !IsNumber(LabEditorYCtrl.Text) {
        StrategyEditorSetStatus("X and Y must be numbers.", true)
        return
    }
    placement := LabEditorDoc.Placements[LabEditorSelectedRow]
    LabEditorDoc.MovePlacement(placement, LabEditorXCtrl.Text, LabEditorYCtrl.Text)
    StrategyEditorRefreshVisuals()
    StrategyEditorSelectPlacement(LabEditorSelectedRow)
    StrategyEditorSetStatus("Updated " placement.towerId " to (" placement.x ", " placement.y "). Not saved yet.")
    StrategyEditorRefreshButtons()
    StrategyEditorRefreshDirty()
}
'@
$P = One $P 'StrategyEditorApplyCoordinates\(\*\) \{.*?\r?\n\}\r?\n\r?\nStrategyEditorUndo' ($Apply.TrimEnd()+$NL+$NL+"StrategyEditorUndo") "apply coords"
$P = One $P 'collisions := LabFootprintCollisionMap\(LabEditorDoc\)\r?\n\s*StrategyEditorSetStatus\("Preview " LabEditorDragPlacement\.towerId " → \(" LabEditorDragPreviewX ", " LabEditorDragPreviewY "\)"\r?\n\s*\(collisions\.Has\(LabEditorDragIndex\) \? " • footprint collision" : ""\), collisions\.Has\(LabEditorDragIndex\)\)' 'StrategyEditorSetStatus("Preview " LabEditorDragPlacement.towerId " → (" LabEditorDragPreviewX ", " LabEditorDragPreviewY ")")' "drag warning"
$P = One $P 'if changed \{\r?\n\s*collisions := LabFootprintCollisionMap\(LabEditorDoc\)\r?\n\s*if collisions\.Has\(row\)\r?\n\s*StrategyEditorSetStatus\("Moved " placement\.towerId " to \(" placement\.x ", " placement\.y "\)\. WARNING: placement footprint intersects another tower\.", true\)\r?\n\s*else\r?\n\s*StrategyEditorSetStatus\("Moved " placement\.towerId " to \(" placement\.x ", " placement\.y "\)\. Not saved yet\."\)\r?\n\s*\}' ('if changed'+$NL+'        StrategyEditorSetStatus("Moved " placement.towerId " to (" placement.x ", " placement.y "). Not saved yet.")') "mouseup warning"

# Keep every current vanity: map capture/cache and portrait sync are not touched.
$U = ReadText $Ui
$U = $U.Replace("Exact map screenshot • true placement footprints • safe saves","Exact map screenshot • stable square markers • safe saves")
$U = $U.Replace('LabEditorRingsBtn := gui.Add("Button", "x412 y177 w92 h24 Hidden", "Footprints: All")','LabEditorRingsBtn := gui.Add("Button", "x412 y177 w92 h24 Hidden Disabled", "Squares: Stable")')
$U = $U.Replace("Click a footprint or row","Click a marker or row")
$U = $U.Replace('try LabEditorRingsBtn.Text := StrategyEditorRingButtonText()','try LabEditorRingsBtn.Text := StrategyEditorRingButtonText()'+$NL+'        try LabEditorRingsBtn.Enabled := false')
if (!$U.Contains("stable square markers") -or !$U.Contains("Squares: Stable")) { throw "UI transform failed" }

# Update runtime contract while retaining footprint-math tests as dormant regression coverage.
$T = ReadText $Test
$T = $T.Replace("0.4.6 client-aligned single canvas","0.4.10 client-aligned square-marker baseline")
$NewContract = @'
LabEditorLayer := "All placements"
if (StrategyEditorRingButtonText() != "Squares: Stable")
    fail("Square baseline toolbar label mismatch")
LabEditorRingMode := "off"
if StrategyEditorRingModeAllows(1)
    fail("Square baseline unexpectedly exposes footprint rendering")
'@
$T = One $T 'LabEditorLayer := "All placements"\r?\nLabEditorRingMode := "all"\r?\nif \(StrategyEditorRingButtonText\(\) != "Footprints: All"\)\r?\n\s*fail\("Footprints All label mismatch"\)\r?\nLabEditorRingMode := "selected"\r?\nif !StrategyEditorRingModeAllows\(1\) \|\| StrategyEditorRingModeAllows\(2\)\r?\n\s*fail\("Footprints selected mode visibility mismatch"\)\r?\nLabEditorRingMode := "off"\r?\nif StrategyEditorRingModeAllows\(1\)\r?\n\s*fail\("Footprints Off still allows a footprint"\)\r?\nLabEditorRingMode := "all"' $NewContract.TrimEnd() "test ring contract"
$T = $T.Replace('PASS: 0.4.6 client ROI, cyan footprints, collisions, layers and hit-testing','PASS: 0.4.10 square markers, client ROI, preserved footprint math, layers and hit-testing')

# Only now write generated sources.
WriteText $Maps $M
WriteText $Placements $P
WriteText $Ui $U
WriteText $Test $T

$VersionText = @'
[Lab]
Version=0.4.10
Notes=Publishes the stable Square Baseline: placement units are dependable numbered color squares on the existing single in-memory canvas, with a larger selected square and the same geometric drag/hit-testing path.|Pauses experimental circular footprint drawing and collision warnings in the live editor while preserving the footprint/calibration implementation for a later opt-in pass.|Keeps exact Roblox CLIENT map capture/cache, hotbar-free projection, tower portraits and portrait sync, zoom/pan, layers, X/Y editing, undo/redo, safe save/backups, Discord Remote, rewards, Stats, telemetry, post-run calibration data and emergency-stop behavior.|No upstream gameplay flow, SpawnTower logic, map-capture hook, watchdog bridge or non-editor subsystem is rolled back.
'@
WriteText $Version ($VersionText.TrimEnd()+$NL)

$FM = ReadText $MapFile
$FM = [regex]::Replace($FM,'^(# Strategy Lab stable delivery map ).*$','${1}0.4.10 square-marker baseline',[Text.RegularExpressions.RegexOptions]::Multiline)
WriteText $MapFile $FM

# files.map is authoritative; rebuild hashes after editor changes.
$Lines = New-Object Collections.Generic.List[string]
$Lines.Add("# sha256|target|source|mode")
foreach ($Line in Get-Content -LiteralPath $MapFile) {
    $S = $Line.Trim()
    if (!$S -or $S.StartsWith("#")) { continue }
    $Parts = $S.Split("|")
    if ($Parts.Count -ne 3) { throw "Invalid files.map row: $Line" }
    $SourcePath = Join-Path $Root ($Parts[1] -replace '/', '\')
    if (!(Test-Path -LiteralPath $SourcePath)) { throw "Missing mapped source: $($Parts[1])" }
    $Hash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $Lines.Add("$Hash|$($Parts[0])|$($Parts[1])|$($Parts[2])")
}
WriteText $Manifest (($Lines -join $NL)+$NL)

Write-Host "Prepared Strategy Lab 0.4.10 Square Baseline." -ForegroundColor Green
git -C $Root diff --stat
