#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; Compile-only contract for LabAutoMapCapture. The production module intentionally
; depends on MapLibrary + Ultimate Macro/GDI+ helpers, so declare their signatures here
; rather than trying to parse the module as a standalone program.

LabMapCameraPath(mapName) => ""
LabMapSaveCameraCapture(mapName, sourcePath) => sourcePath

getRobloxPos(&x, &y, &w, &h) {
    x := 0
    y := 0
    w := 1920
    h := 1009
}

Gdip_BitmapFromScreen(*) => 1
Gdip_SaveBitmapToFile(*) => 0
Gdip_DisposeImage(*) => 0

#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__LabAutoMapCapture.ahk"

ExitApp(0)
