#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; Headless runtime contract for the 0.4.10 client-aligned square-marker baseline.

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
GetRobloxHWND(*) => 0

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
try SetTimer(Lab044GameplayUiGuard, 0)

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

LabEditorLayer := "All placements"
if (StrategyEditorRingButtonText() != "Squares: Stable")
    fail("Square baseline toolbar label mismatch")
LabEditorRingMode := "off"
if StrategyEditorRingModeAllows(1)
    fail("Square baseline unexpectedly exposes footprint rendering")

small := StrategyEditorFootprintDiameter({slot: 5})
avg := StrategyEditorFootprintDiameter({slot: 1})
if (small <= 0 || avg <= 0 || small >= avg)
    fail("Small/Average footprint ordering is invalid")
; Operator Average=1.5 and the supplied TDS cyan boundary is ~78px diameter at 1920.
; On 646x348 canvas with the hotbar cropped, that projects to roughly 28px average.
if (avg < 25 || avg > 31)
    fail("Average cyan placement footprint is not near 28px; got " avg)
if (Abs(LabFootprintPixelsPerUnitForDocument(LabEditorDoc) - 26.0) > 0.01)
    fail("default cyan footprint scale is not 26 px/unit")

; Playable ROI stops above the hotbar. A strategy coordinate below that boundary must
; not appear in the canvas geometry or become draggable.
LabEditorDoc.Placements.Push({slot: 1, x: 960, y: 960, towerId: "hotbar"})
items := StrategyEditorCanvasPlacements()
if (items.Length != 3)
    fail("hotbar placement was not excluded from canvas geometry")
LabEditorDoc.Placements.Pop()

; Two Average footprints now have ~39px canonical radii. 60px separation collides;
; the original 140px separation does not.
LabEditorDoc.Placements[2].x := 1020
LabEditorDoc.Placements[2].y := 504
collisions := LabFootprintCollisionMap(LabEditorDoc)
if !collisions.Has(1) || !collisions.Has(2)
    fail("overlapping Average cyan footprints were not detected")
if collisions.Has(3)
    fail("distant Warden was incorrectly marked as colliding")
if !LabFootprintPlacementCollides(1, LabEditorDoc)
    fail("fast single-placement collision probe missed an overlap")

LabEditorDoc.Placements[2].x := 1100
LabEditorDoc.Placements[2].y := 560
collisions := LabFootprintCollisionMap(LabEditorDoc)
if collisions.Has(1) || collisions.Has(2)
    fail("separated Operator footprints remained colliding")

bottom := LabEditorViewport.ViewportToStrategy(323, 348, 1920,
    LabMapPlayableStrategyHeight(1009), 646, 348)
if (bottom.y < 915 || bottom.y > 920)
    fail("viewport bottom no longer maps just above hotbar; got " bottom.y)

if (LabEditorMarkerCtrls.Length != 0 || LabEditorMarkerByHwnd.Count != 0)
    fail("geometry operations created placement native controls")

FileAppend("PASS: 0.4.10 square markers, client ROI, preserved footprint math, layers and hit-testing`n", "*")
ExitApp(0)
