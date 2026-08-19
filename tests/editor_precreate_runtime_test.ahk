#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; Runtime smoke test for the exact startup window that produced 0.3.11's
; "global LabEditorCanvasBg has not been assigned" crash. The Strategy Editor modules
; are loaded normally, but StrategyEditorCreateTab() is deliberately NOT called.
;
; The test then waits long enough for the early workspace/navigation timers to fire.
; All of them must fail closed while GUI-control globals are still sentinel values.

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
Gdip_DeleteBrush(*) => 0
Gdip_BitmapFromScreen(*) => 1

#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__StrategyEditorTab.ahk"

fail(message) {
    try FileAppend("FAIL: " message "`n", "*")
    ExitApp(1)
}

; Top-level control sentinels must already be assigned before any timer can call into
; StrategyEditorIsActive/WorkspaceMonitor.
if !IsSet(LabEditorCanvasBg)
    fail("LabEditorCanvasBg is unset before StrategyEditorCreateTab")
if !IsSet(LabEditorSnapshot)
    fail("LabEditorSnapshot is unset before StrategyEditorCreateTab")
if IsObject(LabEditorCanvasBg) || IsObject(LabEditorSnapshot)
    fail("pre-create control sentinels unexpectedly contain Gui.Control objects")

; Exercise the functions synchronously before the first timer tick.
try active := StrategyEditorIsActive()
catch Error as err
    fail("StrategyEditorIsActive threw before GUI creation: " err.Message)
if active
    fail("StrategyEditorIsActive returned true before GUI creation")

try StrategyEditorWorkspaceMonitor()
catch Error as err
    fail("StrategyEditorWorkspaceMonitor threw before GUI creation: " err.Message)

; Let the 75/250/400ms startup timers actually execute. This is the part /Validate
; cannot cover and is where the user's crash happened.
Sleep(650)

; Reproduce the other 0.3.11 bug class: a Gui.Control object can survive after the
; native HWND is destroyed. Activity checks must return false instead of throwing.
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

FileAppend("PASS: editor pre-create and destroyed-control lifecycle guards`n", "*")
ExitApp(0)
