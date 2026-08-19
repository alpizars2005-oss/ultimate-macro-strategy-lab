#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; Runtime smoke test for Editor startup/teardown before StrategyEditorCreateTab().

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
Gdip_GetImageWidth(*) => 100
Gdip_GetImageHeight(*) => 100
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

fail(message) {
    try FileAppend("FAIL: " message "`n", "*")
    ExitApp(1)
}

if !IsSet(LabEditorCanvasBg)
    fail("LabEditorCanvasBg is unset before StrategyEditorCreateTab")
if !IsSet(LabEditorSnapshot)
    fail("LabEditorSnapshot is unset before StrategyEditorCreateTab")
if IsObject(LabEditorCanvasBg) || IsObject(LabEditorSnapshot)
    fail("pre-create control sentinels unexpectedly contain Gui.Control objects")

try active := StrategyEditorIsActive()
catch Error as err
    fail("StrategyEditorIsActive threw before GUI creation: " err.Message)
if active
    fail("StrategyEditorIsActive returned true before GUI creation")

try StrategyEditorWorkspaceMonitor()
catch Error as err
    fail("StrategyEditorWorkspaceMonitor threw before GUI creation: " err.Message)

Sleep(650)

probeGui := Gui()
probeCtrl := probeGui.Add("Text", "w10 h10", "x")
LabEditorCanvasBg := probeCtrl
probeGui.Destroy()

try activeAfterDestroy := StrategyEditorIsActive()
catch Error as err
    fail("StrategyEditorIsActive threw for a destroyed control: " err.Message)
if activeAfterDestroy
    fail("destroyed control was treated as active")

LabEditorCanvasBg := ""
LabEditorSnapshot := ""
try StrategyEditorWorkspaceMonitor()
catch Error as err
    fail("Workspace monitor threw after destroyed-control recovery: " err.Message)

FileAppend("PASS: editor startup/teardown guards`n", "*")
ExitApp(0)
