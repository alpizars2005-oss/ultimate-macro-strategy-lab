#Requires AutoHotkey v2.0
#SingleInstance Force

; Execute nothing. AutoHotkey parses the complete script, all function declarations and
; all #Include files before running this first statement, so parser/arity errors are
; still caught while timers, OnExit hooks and GUI/module initialization never run.
ExitApp()

; Minimal upstream contract stubs. These are parsed even though runtime already exited.
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
