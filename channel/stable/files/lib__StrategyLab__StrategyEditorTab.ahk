#Requires AutoHotkey v2.0
#Include "%A_ScriptDir%\lib\StrategyLab\MapLibrary.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\TowerCatalog.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabRewardCatalog.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyCalibration.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabStrategyValidation.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorCore.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabSafety.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabTelemetry.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabRewardTracker.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabRemoteGate.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabStatsTab.ahk"

; Integrated Strategy Editor tab for Main_Lab.ahk.
; Keep StrategyEditorCore above StrategyEditorUi: the UI constructs LabStratDocument
; at runtime and must never rely on a test harness or another include to provide it.

global LabEditorCtrls := []
global LabEditorMarkerCtrls := []
global LabEditorMarkerByHwnd := Map()
global LabEditorDoc := ""
global LabEditorLayer := "All placements"
global LabEditorSelectedRow := 0
global LabEditorDragPlacement := ""
global LabEditorDragMarker := ""
global LabEditorDragOldX := 0
global LabEditorDragOldY := 0
global LabEditorViewport := LabMapViewport()
global LabEditorSourceImage := ""
global LabEditorBackgroundMode := "none"
global LabEditorExpanded := false
global LabEditorCurrentMap := ""
global LabEditorAssetSyncPid := 0
global LabEditorAssetsRequested := false
; Double-buffered JPEG viewport frames reduce disk traffic and stale Picture-control flashes.
global LabEditorViewportPath := A_AppData "\Ultimate_Macro\StrategyEditor\viewport-a.jpg"
global LabEditorViewportAltPath := A_AppData "\Ultimate_Macro\StrategyEditor\viewport-b.jpg"
global LabEditorViewportFrame := 0

global LabEditorCanvasX := 20
global LabEditorCanvasY := 205
global LabEditorCanvasW := 438
global LabEditorCanvasH := 238

#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorUi.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorPlacements.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabSimpleFootprints.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorMaps.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorSave.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorInteraction.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorWorkspace.ahk"

OnMessage(0x0201, StrategyEditorDirectMouseDown)
OnMessage(0x0200, StrategyEditorInteractiveMouseMove)
OnMessage(0x0202, StrategyEditorInteractiveMouseUp)
OnMessage(0x020A, StrategyEditorInteractiveWheel)
