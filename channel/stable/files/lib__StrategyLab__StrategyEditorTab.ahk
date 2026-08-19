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

; Strategy Lab 0.4 single-canvas editor.
;
; The map screenshot, placement-radius circles and numbered markers are composited into
; ONE bitmap. There are no per-placement Gui.Controls and no transparent sibling ring
; HWNDs. Hit-testing is geometric, which keeps drag/layer/zoom independent from Windows
; control z-order and eliminates the visual stacking/tearing seen in the 0.3.x editor.

global LabEditorCtrls := []
global LabEditorMarkerCtrls := []          ; compatibility: intentionally always empty
global LabEditorMarkerByHwnd := Map()     ; compatibility: intentionally always empty
global LabEditorHitRegions := []
global LabEditorDoc := ""
global LabEditorLayer := "All placements"
global LabEditorSelectedRow := 0
global LabEditorDragPlacement := ""
global LabEditorDragIndex := 0
global LabEditorDragOldX := 0
global LabEditorDragOldY := 0
global LabEditorDragPreviewX := ""
global LabEditorDragPreviewY := ""
global LabEditorViewport := LabMapViewport()
global LabEditorSourceImage := ""
global LabEditorBackgroundMode := "none"
global LabEditorExpanded := false
global LabEditorCurrentMap := ""
global LabEditorAssetSyncPid := 0          ; legacy compatibility; web editor sync retired
global LabEditorAssetsRequested := false

global LabEditorViewportPath := A_AppData "\Ultimate_Macro\StrategyEditor\viewport-a.jpg"
global LabEditorViewportAltPath := A_AppData "\Ultimate_Macro\StrategyEditor\viewport-b.jpg"
global LabEditorViewportFrame := 0

global LabEditorCanvasX := 20
global LabEditorCanvasY := 205
global LabEditorCanvasW := 438
global LabEditorCanvasH := 238

; Controls are assigned by StrategyEditorCreateTab(). Every global used by an early
; timer starts as a safe sentinel so AHK v2 can never throw on an unset variable.
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
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorMaps.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorSave.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabEditorStability.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorInteraction.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorWorkspace.ahk"

OnMessage(0x0201, StrategyEditorDirectMouseDown)
OnMessage(0x0200, StrategyEditorInteractiveMouseMove)
OnMessage(0x0202, StrategyEditorInteractiveMouseUp)
OnMessage(0x020A, StrategyEditorInteractiveWheel)
