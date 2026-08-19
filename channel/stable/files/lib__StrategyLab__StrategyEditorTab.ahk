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
;
; AHK v2 throws before a helper can run if an unset global is passed as an argument.
; Every GUI-control global used by early timers is therefore initialized before any
; editor module that can schedule work is included.

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

global LabEditorViewportPath := A_AppData "\Ultimate_Macro\StrategyEditor\viewport-a.jpg"
global LabEditorViewportAltPath := A_AppData "\Ultimate_Macro\StrategyEditor\viewport-b.jpg"
global LabEditorViewportFrame := 0

global LabEditorCanvasX := 20
global LabEditorCanvasY := 205
global LabEditorCanvasW := 438
global LabEditorCanvasH := 238

; Controls are assigned real Gui.Control objects by StrategyEditorCreateTab().
; Empty-string sentinels make startup/teardown checks safe before that happens.
global LabEditorOpenBtn := ""
global LabEditorCurrentBtn := ""
global LabEditorSnapshotBtn := ""
global LabEditorCaptureBtn := ""
global LabEditorUndoBtn := ""
global LabEditorRedoBtn := ""
global LabEditorLayerCtrl := ""
global LabEditorCanvasBg := ""
global LabEditorSnapshot := ""
global LabEditorList := ""
global LabEditorXCtrl := ""
global LabEditorYCtrl := ""
global LabEditorApplyBtn := ""
global LabEditorSaveBtn := ""
global LabEditorOverwriteBtn := ""
global LabEditorStatus := ""
global LabEditorDirty := ""
global LabEditorZoomOutBtn := ""
global LabEditorZoomLabel := ""
global LabEditorZoomInBtn := ""
global LabEditorFitBtn := ""
global LabEditorExpandBtn := ""
global LabEditorPanLeftBtn := ""
global LabEditorPanUpBtn := ""
global LabEditorPanDownBtn := ""
global LabEditorPanRightBtn := ""
global LabEditorSyncBtn := ""
global LabEditorRingsBtn := ""
global LabEditorRemoteBtn := ""
global LabEditorTowerPortrait := ""
global LabEditorTowerName := ""
global LabEditorTowerMeta := ""
global LabEditorMapLabel := ""
global LabEditorCoordLabel := ""
global LabEditorDirtyLabel := ""
global LabEditorAssetBadge := ""
global LabEditorInfoPanel := ""
global LabEditorCanvasHint := ""
global LabEditorTitle := ""
global LabEditorSubtitle := ""
global LabEditorHeaderLine := ""
global LabEditorLayerLabel := ""

#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorUi.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorPlacements.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabSimpleFootprints.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorMaps.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorSave.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabEditorStability.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorInteraction.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorWorkspace.ahk"

OnMessage(0x0201, StrategyEditorDirectMouseDown)
OnMessage(0x0200, StrategyEditorInteractiveMouseMove)
OnMessage(0x0202, StrategyEditorInteractiveMouseUp)
OnMessage(0x020A, StrategyEditorInteractiveWheel)
