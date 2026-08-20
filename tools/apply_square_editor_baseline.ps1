param(
    [string]$InstallDir = "",
    [switch]$Restore
)

$ErrorActionPreference = "Stop"

function Resolve-InstallDir {
    param([string]$Requested)

    $marker = "lib\StrategyLab\StrategyEditorMaps046.ahk"
    if ($Requested) {
        $full = [System.IO.Path]::GetFullPath($Requested)
        if (!(Test-Path -LiteralPath (Join-Path $full $marker))) {
            throw "Strategy Lab renderer not found under: $full"
        }
        return $full
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $cwd = (Get-Location).Path
        if (Test-Path -LiteralPath (Join-Path $cwd $marker)) {
            $candidates.Add($cwd)
        }
    } catch {}

    $desktop = [Environment]::GetFolderPath("Desktop")
    if ($desktop -and (Test-Path -LiteralPath $desktop)) {
        Get-ChildItem -LiteralPath $desktop -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-Path -LiteralPath (Join-Path $_.FullName $marker)) {
                $candidates.Add($_.FullName)
            }
        }
    }

    $unique = @($candidates | Select-Object -Unique)
    if ($unique.Count -eq 1) {
        return $unique[0]
    }
    if ($unique.Count -gt 1) {
        $lines = ($unique | ForEach-Object { "  - $_" }) -join "`n"
        throw "More than one Strategy Lab installation was found. Re-run with -InstallDir.`n$lines"
    }

    throw "No installed Strategy Lab was found automatically. Re-run with -InstallDir 'C:\path\to\Ultimate_Macro'."
}

function Read-Utf8Text {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path)
}

function Write-Utf8Text {
    param([string]$Path, [string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Replace-Required {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )
    $rx = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $count = $rx.Matches($Text).Count
    if ($count -ne 1) {
        throw "Patch '$Label' expected exactly one match but found $count. No partial write was performed for this file."
    }
    return $rx.Replace($Text, $Replacement, 1)
}

$InstallDir = Resolve-InstallDir $InstallDir
$maps = Join-Path $InstallDir "lib\StrategyLab\StrategyEditorMaps046.ahk"
$placements = Join-Path $InstallDir "lib\StrategyLab\StrategyEditorPlacements.ahk"
$ui = Join-Path $InstallDir "lib\StrategyLab\StrategyEditorUi.ahk"

foreach ($path in @($maps, $placements, $ui)) {
    if (!(Test-Path -LiteralPath $path)) {
        throw "Required editor file is missing: $path"
    }
}

Write-Host "`n=== STRATEGY LAB SQUARE BASELINE ===" -ForegroundColor Cyan
Write-Host "Install: $InstallDir" -ForegroundColor Green

$backupSuffix = ".square-baseline.bak"

if ($Restore) {
    foreach ($path in @($maps, $placements, $ui)) {
        $backup = $path + $backupSuffix
        if (!(Test-Path -LiteralPath $backup)) {
            throw "Backup not found: $backup"
        }
    }
    foreach ($path in @($maps, $placements, $ui)) {
        Copy-Item -LiteralPath ($path + $backupSuffix) -Destination $path -Force
        Write-Host "Restored: $path" -ForegroundColor Green
    }
    Write-Host "`nOriginal editor restored. Portrait/cache/map files were never touched." -ForegroundColor Green
    exit 0
}

# Preserve the exact pre-square-baseline editor files once. Re-running the helper is idempotent.
foreach ($path in @($maps, $placements, $ui)) {
    $backup = $path + $backupSuffix
    if (!(Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $path -Destination $backup
        Write-Host "Backup: $backup" -ForegroundColor DarkGray
    }
}

# -----------------------------------------------------------------------------
# Renderer: keep the modern single-HWND/client-aligned canvas, but render the old
# dependable numbered color squares. Footprint geometry remains installed for a
# future opt-in pass; it is simply not used by the live editor hot path.
# -----------------------------------------------------------------------------
$mapsText = Read-Utf8Text $maps

$squareRenderer = @'
StrategyEditorDrawPlacement(graphics, index, placement, point, collisions, fast := false) {
    global LabEditorSelectedRow

    selected := index = LabEditorSelectedRow
    markerSize := selected ? 22.0 : 18.0
    half := markerSize / 2.0
    border := selected ? 2.0 : 1.0

    ; Stable square baseline: the coordinate center is the tower placement point.
    ; No footprint/range geometry is painted here. We keep the single in-memory
    ; canvas, exact map capture, zoom/pan and geometric hit-testing introduced in 0.4.x.
    borderBrush := 0
    fillBrush := 0
    try {
        borderBrush := Gdip_BrushCreateSolid(selected ? 0xFFFFFFFF : 0xFF20252B)
        if borderBrush
            Gdip_FillRectangle(graphics, borderBrush,
                point.x - half, point.y - half, markerSize, markerSize)

        fillBrush := Gdip_BrushCreateSolid(StrategyEditorSlotColor(placement.slot, 255))
        if fillBrush
            Gdip_FillRectangle(graphics, fillBrush,
                point.x - half + border, point.y - half + border,
                markerSize - (border * 2), markerSize - (border * 2))
    } finally {
        if fillBrush
            try Gdip_DeleteBrush(fillBrush)
        if borderBrush
            try Gdip_DeleteBrush(borderBrush)
    }

    if !fast {
        label := StrategyEditorMarkerLabel(placement)
        options := "x" (point.x - half) " y" (point.y - half)
            . " w" markerSize " h" markerSize " Center vCenter cFFFFFFFF s7 Bold"
        try Gdip_TextToGraphics(graphics, label, options, "Segoe UI")
    }
}

StrategyEditorDrawSource
'@

$mapsText = Replace-Required $mapsText `
    'StrategyEditorDrawPlacement\(graphics, index, placement, point, collisions, fast := false\) \{.*?\r?\n\}\r?\n\r?\nStrategyEditorDrawSource' `
    $squareRenderer `
    "square marker renderer"

$mapsText = Replace-Required $mapsText `
    'collision := Map\(\)\r?\n\s*if LabFootprintPlacementCollides\(dragIndex, LabEditorDoc\)\r?\n\s*collision\[dragIndex\] := true\r?\n\s*StrategyEditorDrawPlacement\(g, dragIndex, item\.placement, item\.point, collision, true\)' `
    'collision := Map()`r`n                StrategyEditorDrawPlacement(g, dragIndex, item.placement, item.point, collision, true)' `
    "disable drag footprint collision probe"

$mapsText = Replace-Required $mapsText `
    'collisions := IsObject\(LabEditorDoc\) \? LabFootprintCollisionMap\(LabEditorDoc\) : Map\(\)' `
    'collisions := Map()' `
    "disable idle footprint collision pass"

$mapsText = $mapsText.Replace(
    "drag: cached 438x238 static base + ONE moving footprint",
    "drag: cached 438x238 static base + ONE moving square marker"
)
$mapsText = $mapsText.Replace(
    "Panning needs only the terrain. Footprints return on the guaranteed final mouse-up",
    "Panning needs only the terrain. Square markers return on the guaranteed final mouse-up"
)

# -----------------------------------------------------------------------------
# Placement interaction: footprints stay dormant and do not influence warnings,
# drag responsiveness or save behavior while the square baseline is active.
# -----------------------------------------------------------------------------
$placementsText = Read-Utf8Text $placements
$placementsText = Replace-Required $placementsText `
    'global LabEditorRingMode := "all"' `
    'global LabEditorRingMode := "off"' `
    "default footprints off"

$ringButton = @'
StrategyEditorRingButtonText() {
    return "Squares: Stable"
}
'@
$placementsText = Replace-Required $placementsText `
    'StrategyEditorRingButtonText\(\) \{.*?\r?\n\}' `
    $ringButton.TrimEnd() `
    "square baseline toolbar label"

$ringToggle = @'
StrategyEditorToggleRings(*) {
    global LabEditorRingMode, LabEditorRingsBtn
    LabEditorRingMode := "off"
    if LabEditorControlAlive(LabEditorRingsBtn)
        try LabEditorRingsBtn.Text := StrategyEditorRingButtonText()
    StrategyEditorSetStatus("Stable square-marker baseline active. Footprint geometry is preserved but paused for a later opt-in pass.")
}
'@
$placementsText = Replace-Required $placementsText `
    'StrategyEditorToggleRings\(\*\) \{.*?\r?\n\}' `
    $ringToggle.TrimEnd() `
    "pause footprint toggle"

$applyCoordinates = @'
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
$placementsText = Replace-Required $placementsText `
    'StrategyEditorApplyCoordinates\(\*\) \{.*?\r?\n\}\r?\n\r?\nStrategyEditorUndo' `
    ($applyCoordinates.TrimEnd() + "`r`n`r`nStrategyEditorUndo") `
    "coordinate apply without footprint warning"

$previewStatusPattern = 'collisions := LabFootprintCollisionMap\(LabEditorDoc\)\r?\n\s*StrategyEditorSetStatus\("Preview " LabEditorDragPlacement\.towerId " → \(" LabEditorDragPreviewX ", " LabEditorDragPreviewY "\)"\r?\n\s*\(collisions\.Has\(LabEditorDragIndex\) \? " • footprint collision" : ""\), collisions\.Has\(LabEditorDragIndex\)\)'
$previewStatusReplacement = 'StrategyEditorSetStatus("Preview " LabEditorDragPlacement.towerId " → (" LabEditorDragPreviewX ", " LabEditorDragPreviewY ")")'
$placementsText = Replace-Required $placementsText $previewStatusPattern $previewStatusReplacement "drag preview without footprint warning"

$mouseUpWarningPattern = 'if changed \{\r?\n\s*collisions := LabFootprintCollisionMap\(LabEditorDoc\)\r?\n\s*if collisions\.Has\(row\)\r?\n\s*StrategyEditorSetStatus\("Moved " placement\.towerId " to \(" placement\.x ", " placement\.y "\)\. WARNING: placement footprint intersects another tower\.", true\)\r?\n\s*else\r?\n\s*StrategyEditorSetStatus\("Moved " placement\.towerId " to \(" placement\.x ", " placement\.y "\)\. Not saved yet\."\)\r?\n\s*\}'
$mouseUpWarningReplacement = 'if changed`r`n        StrategyEditorSetStatus("Moved " placement.towerId " to (" placement.x ", " placement.y "). Not saved yet.")'
$placementsText = Replace-Required $placementsText $mouseUpWarningPattern $mouseUpWarningReplacement "mouse-up without footprint warning"

# -----------------------------------------------------------------------------
# UI wording only. Portrait sync, map capture/cache, layers, save/backup, remote,
# stats/rewards and every non-editor subsystem are deliberately untouched.
# -----------------------------------------------------------------------------
$uiText = Read-Utf8Text $ui
$uiText = $uiText.Replace(
    "Exact map screenshot • true placement footprints • safe saves",
    "Exact map screenshot • stable square markers • safe saves"
)
$uiText = $uiText.Replace(
    'LabEditorRingsBtn := gui.Add("Button", "x412 y177 w92 h24 Hidden", "Footprints: All")',
    'LabEditorRingsBtn := gui.Add("Button", "x412 y177 w92 h24 Hidden", "Squares: Stable")'
)
$uiText = $uiText.Replace(
    "Click a footprint or row",
    "Click a marker or row"
)

# Write only after every required transformation succeeded.
Write-Utf8Text $maps $mapsText
Write-Utf8Text $placements $placementsText
Write-Utf8Text $ui $uiText

Write-Host "`nPatched editor files:" -ForegroundColor Cyan
Get-Item -LiteralPath $maps, $placements, $ui |
    Select-Object Name, Length, LastWriteTime |
    Format-Table -AutoSize

Write-Host "Square baseline enabled." -ForegroundColor Green
Write-Host "Preserved: exact map capture/cache, portraits, zoom/pan, layers, coordinates, undo/redo, save backups, Remote, Stats, Rewards and calibration code." -ForegroundColor Green
Write-Host "Footprint geometry remains on disk but is not painted or evaluated by the live editor." -ForegroundColor Yellow
Write-Host "`nTo restore the exact previous editor:" -ForegroundColor Cyan
Write-Host ".\tools\apply_square_editor_baseline.ps1 -InstallDir `"$InstallDir`" -Restore" -ForegroundColor White
