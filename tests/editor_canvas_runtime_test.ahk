#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; Headless runtime contract for the 0.4.3 single-canvas geometry. Full syntax/include
; validation is covered separately; this test exercises layer projection, hit-testing,
; calibrated placement footprint size and footprint collision detection.

StartStrategy(ctrl, *) {
}
StopStrategy(ctrl, *) {
}
KillSubmacros(*) {
}
LoadStrategyFile(path) {
}
getRobloxPos(&x, &y, &w, &h) {
    x := 0, y := 0, w := 1920, h := 1009
}

Gdip_CreateBitmapFromFile(*) => 1
Gdip_GetImageWidth(*) => 1920
Gdip_GetImageHeight(*) => 1009
Gdip_DisposeImage(*) => 0
Gdip_CreateBitmap(*) => 1
Gdip_GraphicsFromImage(*) => 1
Gdip_DrawImage(*) => 0
Gdip_SaveBitmapToFile(*) => 0
Gdip_DeleteGraphics(*) => 0
Gdip_BrushCreateSolid(*) => 1
Gdip_FillRectangle(*) => 0
Gdip_FillEllipse(*) => 0
Gdip_DeleteBrush(*) => 0
Gdip_CreatePen(*) => 1
Gdip_DrawEllipse(*) => 0
Gdip_DeletePen(*) => 0
Gdip_TextToGraphics(*) => 0
Gdip_BitmapFromScreen(*) => 1

#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorTab.ahk"

try SetTimer(StrategyEditorWorkspaceMonitor, 0)
try SetTimer(StrategyEditorInteractiveStateGuard, 0)
try SetTimer(StrategyEditorInstallDirectNavigation, 0)
try SetTimer(LabStatsRefresh, 0)
try SetTimer(LabRewardTrackerTick, 0)
try SetTimer(LabTelemetryTick, 0)
try SetTimer(LabRewardMaybeSyncAssets, 0)

fail(message) {
    try FileAppend("FAIL: " message "`n", "*")
    ExitApp(1)
}

class FakeEditorDoc {
    __New() {
        this.StrategyWidth := 1920
        this.StrategyHeight := 1009
        this.Settings := Map("map", "Dead Ahead")
        this.RequiredTowers := ["Operator", "Warden"]
        this.Placements := [
            {slot: 1, x: 960, y: 504, towerId: "p1"},
            {slot: 1, x: 1100, y: 560, towerId: "p2"},
            {slot: 5, x: 700, y: 400, towerId: "p3"}
        ]
    }
    TowerNameForSlot(slot) {
        return String(slot) = "1" ? "Operator" : "Warden"
    }
}

LabEditorDoc := FakeEditorDoc()
LabEditorLayer := "All placements"
LabEditorSelectedRow := 1
LabEditorViewport.Reset()
LabEditorCanvasX := 20
LabEditorCanvasY := 205
LabEditorCanvasW := 646
LabEditorCanvasH := 348

if (LabEditorMarkerCtrls.Length != 0)
    fail("placement control array is not empty")
if (LabEditorMarkerByHwnd.Count != 0)
    fail("placement HWND map is not empty")

items := StrategyEditorCanvasPlacements()
if (items.Length != 3)
    fail("All placements geometry did not contain exactly 3 items")
StrategyEditorRebuildHitRegions(items)
if (LabEditorHitRegions.Length != 3)
    fail("All placements did not create exactly 3 hit regions")

first := LabEditorHitRegions[1]
if (StrategyEditorHitTestPlacement(first.x, first.y) != first.index)
    fail("geometric hit-test did not resolve first painted placement")

LabEditorLayer := "Slot 1 - Operator"
items := StrategyEditorCanvasPlacements()
if (items.Length != 2)
    fail("Slot 1 layer did not filter geometry to 2 placements")
StrategyEditorRebuildHitRegions(items)
if (LabEditorHitRegions.Length != 2)
    fail("Slot 1 layer did not filter hit regions to 2 placements")
for region in LabEditorHitRegions {
    if (region.index = 3)
        fail("Warden placement remained in Operator layer hit regions")
}

LabEditorRingMode := "all"
if (StrategyEditorRingButtonText() != "Footprints: All")
    fail("Footprints All label mismatch")
LabEditorRingMode := "selected"
if !StrategyEditorRingModeAllows(1) || StrategyEditorRingModeAllows(2)
    fail("Footprints selected mode visibility mismatch")
LabEditorRingMode := "off"
if StrategyEditorRingModeAllows(1)
    fail("Footprints Off still allows a footprint")

small := StrategyEditorFootprintDiameter({slot: 5})
avg := StrategyEditorFootprintDiameter({slot: 1})
if (small <= 0 || avg <= 0 || small >= avg)
    fail("Small/Average footprint calibration ordering is invalid")
; Average(1.5) at this 646x348 canvas should project to about 12px, not the old 28px+ halo.
if (avg < 10 || avg > 14)
    fail("Average footprint projection is not calibrated near 12px; got " avg)

; Two Average footprints have 18px reference radii each. 25px center separation must
; collide, while the original 140px separation does not.
LabEditorDoc.Placements[2].x := 985
LabEditorDoc.Placements[2].y := 504
collisions := LabFootprintCollisionMap(LabEditorDoc)
if !collisions.Has(1) || !collisions.Has(2)
    fail("overlapping Average footprints were not detected")
if collisions.Has(3)
    fail("distant Warden was incorrectly marked as colliding")

LabEditorDoc.Placements[2].x := 1100
LabEditorDoc.Placements[2].y := 560
collisions := LabFootprintCollisionMap(LabEditorDoc)
if collisions.Has(1) || collisions.Has(2)
    fail("separated Operator footprints remained colliding")

if (LabEditorMarkerCtrls.Length != 0 || LabEditorMarkerByHwnd.Count != 0)
    fail("geometry operations created placement native controls")

FileAppend("PASS: single-canvas layers, calibrated footprints, collisions and hit-testing`n", "*")
ExitApp(0)
