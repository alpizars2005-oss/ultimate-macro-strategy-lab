#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; Runtime contract for the 0.4 single-canvas architecture. GDI+ wrappers are lightweight
; stubs: this test validates editor state, filtering, compositing flow and hit-regions
; without depending on GPU/display capture in GitHub Actions.

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

Gdip_CreateBitmapFromFile(*) => 101
Gdip_GetImageWidth(*) => 1920
Gdip_GetImageHeight(*) => 1009
Gdip_DisposeImage(*) => 0
Gdip_CreateBitmap(*) => 102
Gdip_GraphicsFromImage(*) => 103
Gdip_DrawImage(*) => 0
Gdip_DeleteGraphics(*) => 0
Gdip_BrushCreateSolid(*) => 104
Gdip_FillRectangle(*) => 0
Gdip_FillEllipse(*) => 0
Gdip_DeleteBrush(*) => 0
Gdip_CreatePen(*) => 105
Gdip_DrawEllipse(*) => 0
Gdip_DeletePen(*) => 0
Gdip_TextToGraphics(*) => 0
Gdip_BitmapFromScreen(*) => 106
Gdip_SaveBitmapToFile(bitmap, path, quality := 90) {
    if FileExist(path)
        FileDelete(path)
    FileAppend(StrReplace(Format("{:0600}", "frame"), " ", "x"), path, "UTF-8-RAW")
    return 0
}

#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorTab.ahk"

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

; Create the actual Editor controls so the renderer can use the real single Picture.
MainGui := Gui()
StrategyEditorCreateTab(MainGui)
LabEditorDoc := FakeEditorDoc()
LabEditorLayer := "All placements"
LabEditorSelectedRow := 1
LabEditorViewport.Reset()

source := A_Temp "\strategy-lab-canvas-source.tmp"
output := A_Temp "\strategy-lab-canvas-output.jpg"
try FileDelete(source)
try FileDelete(output)
FileAppend("fake source", source, "UTF-8-RAW")
LabEditorSourceImage := source
LabEditorBackgroundMode := "camera"

; The 0.4 placement renderer must never create per-placement controls.
StrategyEditorBuildMarkers()
if (LabEditorMarkerCtrls.Length != 0)
    fail("StrategyEditorBuildMarkers created placement Gui.Controls")
if (LabEditorMarkerByHwnd.Count != 0)
    fail("StrategyEditorBuildMarkers populated HWND marker map")

if !StrategyEditorRenderCompositeFrame(output)
    fail("single-canvas composite frame did not render")
if (LabEditorHitRegions.Length != 3)
    fail("All placements did not create exactly 3 geometric hit regions")

first := LabEditorHitRegions[1]
if (StrategyEditorHitTestPlacement(first.x, first.y) != first.index)
    fail("geometric hit-test did not resolve the painted placement")

; Layer filtering must affect the canvas itself, not just the ListView.
LabEditorLayer := "Slot 1 - Operator"
if !StrategyEditorRenderCompositeFrame(output)
    fail("filtered canvas frame did not render")
if (LabEditorHitRegions.Length != 2)
    fail("Slot 1 layer did not filter canvas hit regions to 2 placements")
for region in LabEditorHitRegions {
    if (region.index = 3)
        fail("filtered Warden placement remained on canvas")
}

; Radii cycle is state-only and must never create another HWND.
LabEditorRingMode := "all"
StrategyEditorToggleRings()
if (LabEditorRingMode != "selected")
    fail("Radii mode did not cycle All -> Selected")
if (LabEditorMarkerCtrls.Length != 0 || LabEditorMarkerByHwnd.Count != 0)
    fail("Radii toggle recreated native placement controls")

try FileDelete(source)
try FileDelete(output)
try MainGui.Destroy()
FileAppend("PASS: single-canvas render, filtering and hit-testing`n", "*")
ExitApp(0)
