#Requires AutoHotkey v2.0
#SingleInstance Force

; CI verification trigger after fixing GUI-subsystem process waiting.
; Minimal upstream contract stubs. The harness exits before any included module executes,
; but AutoHotkey still parses the complete script and validates calls against known
; signatures. This catches the exact classes that escaped Python-only checks before:
; illegal ByRef targets, malformed expressions, missing includes and function arity.

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

; Runtime side effects below this point are unreachable. #Include is processed during
; load/parse, therefore every module is still syntax-checked before ExitApp executes.
ExitApp()

#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__MapLibrary.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__TowerCatalog.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__StrategyCalibration.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__LabStrategyValidation.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__LabSafety.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__LabTelemetry.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__LabRemoteGate.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__StrategyEditorUi.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__StrategyEditorPlacements.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__StrategyEditorMaps.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__StrategyEditorSave.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__StrategyEditorInteraction.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__StrategyEditorWorkspace.ahk"
#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__LabUpdater.ahk"
