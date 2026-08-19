#Requires AutoHotkey v2.0
#Include "%A_ScriptDir%\lib\StrategyLab\MapLibrary.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabAutoMapCapture.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\TowerCatalog.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabFootprintGeometry.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabRewardCatalog.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyCalibration.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabStrategyValidation.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorCore.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabSafety.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabTelemetry.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabRewardTracker.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabRemoteGate.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabStatsTab.ahk"

; Strategy Lab 0.4.6 single-canvas editor.
; Exact client screenshot + real TDS placement boundaries are painted into one bitmap.
; The hotbar is excluded from the editable ROI and post-run calibration can refine the
; visual placement center/scale without ever changing the source .strat coordinates.

global LabEditorCtrls := []
global LabEditorMarkerCtrls := []
global LabEditorMarkerByHwnd := Map()
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
global LabEditorAssetSyncPid := 0
global LabEditorAssetsRequested := false

global LabEditorViewportPath := A_AppData "\Ultimate_Macro\StrategyEditor\viewport-a.jpg"
global LabEditorViewportAltPath := A_AppData "\Ultimate_Macro\StrategyEditor\viewport-b.jpg"
global LabEditorViewportFrame := 0
global LabEditorCanvasBitmap := 0

global LabEditorCanvasX := 20
global LabEditorCanvasY := 205
global LabEditorCanvasW := 438
global LabEditorCanvasH := 238

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

StrategyEditorSetCircularRegion(ctrl, size) {
    if !IsObject(ctrl) || size <= 0
        return false
    hwnd := 0
    try hwnd := ctrl.Hwnd
    if !hwnd || !DllCall("user32\IsWindow", "Ptr", hwnd, "Int")
        return false
    diameter := Max(1, Round(size))
    region := DllCall("gdi32\CreateEllipticRgn",
        "Int", 0, "Int", 0, "Int", diameter + 1, "Int", diameter + 1, "Ptr")
    if !region
        return false
    if DllCall("user32\SetWindowRgn", "Ptr", hwnd, "Ptr", region, "Int", 1)
        return true
    DllCall("gdi32\DeleteObject", "Ptr", region)
    return false
}

#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorUi.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorPlacements.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorMaps046.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorSave.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabEditorStability.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorInteraction.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\StrategyEditorWorkspace.ahk"
#Include "%A_ScriptDir%\lib\StrategyLab\LabEditorHotfix044.ahk"

OnMessage(0x0201, Lab044CanvasMouseDown)
OnMessage(0x0200, Lab044CanvasMouseMove)
OnMessage(0x0202, Lab044CanvasMouseUp)
OnMessage(0x020A, Lab044CanvasWheel)
