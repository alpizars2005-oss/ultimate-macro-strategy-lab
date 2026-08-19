#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; Headless runtime contract for the 0.4 single-canvas geometry. Full syntax/include
; validation is covered separately; this test exercises the exact layer projection and
; geometric hit-testing used by the real bitmap renderer, without fake native images.

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

; Architecture contract: there are never placement native controls.
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

; The exact same visibility predicate must drive layer geometry.
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

; Radius state and footprint sizes are pure model state; toggling them must not create
; native controls or modify the filtering contract.
LabEditorRingMode := "all"
if (StrategyEditorRingButtonText() != "Radii: All")
    fail("Radii All label mismatch")
LabEditorRingMode := "selected"
if !StrategyEditorRingModeAllows(1) || StrategyEditorRingModeAllows(2)
    fail("Radii selected mode visibility mismatch")
LabEditorRingMode := "off"
if StrategyEditorRingModeAllows(1)
    fail("Radii Off still allows a radius")

small := StrategyEditorFootprintDiameter({slot: 5})
avg := StrategyEditorFootprintDiameter({slot: 1})
if (small <= 0 || avg <= 0)
    fail("footprint diameter returned a non-positive value")

if (LabEditorMarkerCtrls.Length != 0 || LabEditorMarkerByHwnd.Count != 0)
    fail("geometry operations created placement native controls")

FileAppend("PASS: single-canvas geometry, layers, radii and hit-testing`n", "*")
ExitApp(0)
