#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; Validate-only harness: CI invokes this file with AutoHotkey v2 /Validate, so none of
; the runtime statements below execute. Function declarations and every #Include are
; still loaded and validated, including known upstream function arity. Warnings are
; disabled because this intentionally incomplete harness does not define every upstream
; runtime symbol; parser/arity failures remain fatal and are still reported.
ExitApp()

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
