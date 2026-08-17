#Requires AutoHotkey v2.0

StrategyEditorCreateTab(gui) {
    global LabEditorCtrls
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorOpenBtn, LabEditorCurrentBtn, LabEditorSnapshotBtn, LabEditorCaptureBtn
    global LabEditorUndoBtn, LabEditorRedoBtn, LabEditorLayerCtrl, LabEditorCanvasBg, LabEditorSnapshot
    global LabEditorList, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn
    global LabEditorOverwriteBtn, LabEditorStatus, LabEditorDirty
    global LabEditorZoomOutBtn, LabEditorZoomLabel, LabEditorZoomInBtn, LabEditorFitBtn, LabEditorExpandBtn
    global LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn, LabEditorSyncBtn
    global LabEditorTowerPortrait, LabEditorTowerName, LabEditorMapLabel, LabEditorCoordLabel, LabEditorDirtyLabel

    gui.SetFont("s10 w600 c3A86FF", "Segoe UI")
    title := gui.Add("Text", "x30 y95 w300 h22 Hidden", "Visual Strategy Editor")
    line := gui.Add("Progress", "x30 y118 w640 h1 Hidden Background333333", 0)

    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabEditorOpenBtn := gui.Add("Button", "x30 y128 w76 h28 Hidden", "Open")
    LabEditorCurrentBtn := gui.Add("Button", "x111 y128 w88 h28 Hidden", "Use Current")
    LabEditorSnapshotBtn := gui.Add("Button", "x204 y128 w82 h28 Hidden", "Snapshot")
    LabEditorCaptureBtn := gui.Add("Button", "x291 y128 w82 h28 Hidden", "Capture")
    LabEditorUndoBtn := gui.Add("Button", "x378 y128 w58 h28 Hidden", "Undo")
    LabEditorRedoBtn := gui.Add("Button", "x441 y128 w58 h28 Hidden", "Redo")
    LabEditorZoomOutBtn := gui.Add("Button", "x504 y128 w28 h28 Hidden", "-")
    LabEditorZoomLabel := gui.Add("Button", "x535 y128 w50 h28 Hidden", "100%")
    LabEditorZoomInBtn := gui.Add("Button", "x588 y128 w28 h28 Hidden", "+")
    LabEditorFitBtn := gui.Add("Button", "x619 y128 w51 h28 Hidden", "Fit")

    gui.SetFont("s8 w400 cAAAAAA", "Segoe UI")
    layerLabel := gui.Add("Text", "x30 y160 w38 h18 Hidden", "Layer")
    gui.SetFont("s8 w400 c000000", "Segoe UI")
    LabEditorLayerCtrl := gui.Add("DropDownList", "x68 y156 w158 Hidden", ["All placements"])
    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabEditorPanLeftBtn := gui.Add("Button", "x232 y156 w28 h22 Hidden", "←")
    LabEditorPanUpBtn := gui.Add("Button", "x263 y156 w28 h22 Hidden", "↑")
    LabEditorPanDownBtn := gui.Add("Button", "x294 y156 w28 h22 Hidden", "↓")
    LabEditorPanRightBtn := gui.Add("Button", "x325 y156 w28 h22 Hidden", "→")
    LabEditorExpandBtn := gui.Add("Button", "x358 y156 w62 h22 Hidden", "Expand")
    LabEditorSyncBtn := gui.Add("Button", "x425 y156 w82 h22 Hidden", "Sync Assets")
    gui.SetFont("s7 w400 cAAAAAA", "Segoe UI")
    LabEditorMapLabel := gui.Add("Text", "x512 y158 w158 h18 Hidden Right", "Map: -")

    LabEditorCanvasBg := gui.Add("Text", "x" LabEditorCanvasX " y" LabEditorCanvasY
        " w" LabEditorCanvasW " h" LabEditorCanvasH " Hidden +Border Background242424")
    LabEditorSnapshot := gui.Add("Picture", "x" LabEditorCanvasX " y" LabEditorCanvasY
        " w" LabEditorCanvasW " h" LabEditorCanvasH " Hidden")

    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabEditorTowerPortrait := gui.Add("Picture", "x465 y180 w56 h56 Hidden +Border")
    gui.SetFont("s9 w600 cFFFFFF", "Segoe UI")
    LabEditorTowerName := gui.Add("Text", "x530 y184 w140 h50 Hidden", "Select a placement")
    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabEditorList := gui.Add("ListView", "x465 y245 w205 h171 Hidden Grid -Multi", ["#", "Unit", "X", "Y"])
    LabEditorList.ModifyCol(1, 27)
    LabEditorList.ModifyCol(2, 92)
    LabEditorList.ModifyCol(3, 38)
    LabEditorList.ModifyCol(4, 38)

    gui.SetFont("s8 w400 cAAAAAA", "Segoe UI")
    LabEditorCoordLabel := gui.Add("Text", "x30 y425 w150 h20 Hidden", "Selected coordinates:")
    LabEditorDirtyLabel := gui.Add("Text", "x465 y425 w205 h20 Hidden", "Changes are in-memory until saved.")

    gui.SetFont("s8 w400 c000000", "Segoe UI")
    LabEditorXCtrl := gui.Add("Edit", "x155 y422 w60 h22 Hidden Number")
    LabEditorYCtrl := gui.Add("Edit", "x220 y422 w60 h22 Hidden Number")
    LabEditorApplyBtn := gui.Add("Button", "x285 y420 w78 h26 Hidden", "Apply X/Y")

    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabEditorSaveBtn := gui.Add("Button", "x370 y420 w80 h26 Hidden", "Save Copy")
    LabEditorOverwriteBtn := gui.Add("Button", "x465 y450 w205 h28 Hidden", "Overwrite + automatic backup")
    LabEditorDirty := gui.Add("Text", "x30 y452 w420 h18 Hidden cAAAAAA", "No strategy loaded.")
    LabEditorStatus := gui.Add("Text", "x30 y478 w640 h50 Hidden cAAAAAA", "Open a .strat or use the current Strategy 1.")

    LabEditorOpenBtn.OnEvent("Click", StrategyEditorOpen)
    LabEditorCurrentBtn.OnEvent("Click", StrategyEditorUseCurrent)
    LabEditorSnapshotBtn.OnEvent("Click", StrategyEditorLoadSnapshot)
    LabEditorCaptureBtn.OnEvent("Click", StrategyEditorCaptureRoblox)
    LabEditorUndoBtn.OnEvent("Click", StrategyEditorUndo)
    LabEditorRedoBtn.OnEvent("Click", StrategyEditorRedo)
    LabEditorZoomOutBtn.OnEvent("Click", (*) => StrategyEditorZoom(-0.25))
    LabEditorZoomLabel.OnEvent("Click", (*) => StrategyEditorZoomReset())
    LabEditorZoomInBtn.OnEvent("Click", (*) => StrategyEditorZoom(0.25))
    LabEditorFitBtn.OnEvent("Click", (*) => StrategyEditorZoomReset())
    LabEditorPanLeftBtn.OnEvent("Click", (*) => StrategyEditorPan(-0.18, 0))
    LabEditorPanUpBtn.OnEvent("Click", (*) => StrategyEditorPan(0, -0.18))
    LabEditorPanDownBtn.OnEvent("Click", (*) => StrategyEditorPan(0, 0.18))
    LabEditorPanRightBtn.OnEvent("Click", (*) => StrategyEditorPan(0.18, 0))
    LabEditorExpandBtn.OnEvent("Click", StrategyEditorToggleExpanded)
    LabEditorSyncBtn.OnEvent("Click", StrategyEditorSyncAssets)
    LabEditorLayerCtrl.OnEvent("Change", StrategyEditorLayerChanged)
    LabEditorList.OnEvent("ItemSelect", StrategyEditorRowSelected)
    LabEditorApplyBtn.OnEvent("Click", StrategyEditorApplyCoordinates)
    LabEditorSaveBtn.OnEvent("Click", StrategyEditorSaveCopy)
    LabEditorOverwriteBtn.OnEvent("Click", StrategyEditorOverwrite)

    LabEditorCtrls := [
        title, line, LabEditorOpenBtn, LabEditorCurrentBtn, LabEditorSnapshotBtn, LabEditorCaptureBtn,
        LabEditorUndoBtn, LabEditorRedoBtn, LabEditorZoomOutBtn, LabEditorZoomLabel, LabEditorZoomInBtn,
        LabEditorFitBtn, layerLabel, LabEditorLayerCtrl, LabEditorPanLeftBtn, LabEditorPanUpBtn,
        LabEditorPanDownBtn, LabEditorPanRightBtn, LabEditorExpandBtn, LabEditorSyncBtn, LabEditorMapLabel,
        LabEditorCanvasBg, LabEditorSnapshot, LabEditorTowerPortrait, LabEditorTowerName, LabEditorList,
        LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn,
        LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus
    ]
    return LabEditorCtrls
}

StrategyEditorShow() {
    global LabEditorCtrls, LabEditorDoc, LabEditorCanvasBg, LabEditorSnapshot, LabEditorExpanded
    global LabEditorTowerPortrait, LabEditorTowerName, LabEditorList, LabEditorCoordLabel, LabEditorDirtyLabel
    global LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus
    for ctrl in LabEditorCtrls
        ctrl.Visible := true
    if (LabEditorSnapshot.Value != "")
        LabEditorCanvasBg.Visible := false
    if LabEditorExpanded {
        for ctrl in [LabEditorTowerPortrait, LabEditorTowerName, LabEditorList, LabEditorCoordLabel, LabEditorDirtyLabel,
            LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus]
            ctrl.Visible := false
    }
    StrategyEditorMaybeAutoSyncAssets()
    StrategyEditorRenderBackground()
    StrategyEditorApplyLayer()
    StrategyEditorRefreshButtons()
}

StrategyEditorTryBeginDrag(hwnd) {
    global LabEditorMarkerByHwnd, LabEditorDragPlacement, LabEditorDragMarker
    global LabEditorDragOldX, LabEditorDragOldY, MainGui, LabEditorBackgroundMode
    if !LabEditorMarkerByHwnd.Has(hwnd)
        return false
    if (LabEditorBackgroundMode = "reference") {
        StrategyEditorSetStatus("Top-down Wiki images are reference-only. Use Capture once on this map to create an exact macro-camera background before dragging.", true)
        return true
    }

    entry := LabEditorMarkerByHwnd[hwnd]
    LabEditorDragPlacement := entry.placement
    LabEditorDragMarker := entry.ctrl
    LabEditorDragOldX := entry.placement.x
    LabEditorDragOldY := entry.placement.y
    StrategyEditorSelectPlacement(entry.index)
    DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return true
}

StrategyEditorOpen(*) {
    path := FileSelect(1, , "Open Ultimate Macro strategy", "Strategy (*.strat)")
    if (path != "")
        StrategyEditorLoadPath(path)
}

StrategyEditorUseCurrent(*) {
    global Strategy1Ctrl, Strategy1Path
    path := ""
    try path := Trim(Strategy1Ctrl.Text)
    if (path = "")
        path := Strategy1Path
    if (path = "" || !FileExist(path)) {
        StrategyEditorSetStatus("Strategy 1 is empty or the file no longer exists.", true)
        return
    }
    StrategyEditorLoadPath(path)
}

StrategyEditorLoadPath(path) {
    global LabEditorDoc, LabEditorLayer, LabEditorSelectedRow, LabEditorAssetsRequested
    try {
        LabEditorDoc := LabStratDocument(path)
        if (LabEditorDoc.Placements.Length = 0)
            throw Error("No SpawnTower placements were found in [Steps].")
        LabEditorLayer := "All placements"
        LabEditorSelectedRow := 0
        LabEditorAssetsRequested := false
        StrategyEditorBuildLayers()
        StrategyEditorAutoLoadMap()
        StrategyEditorBuildMarkers()
        StrategyEditorSetStatus("Loaded " LabEditorDoc.Placements.Length " placements from " path ". " StrategyEditorBackgroundDescription())
        StrategyEditorRefreshButtons()
        StrategyEditorRefreshDirty()
    } catch Error as err {
        LabEditorDoc := ""
        StrategyEditorClearMarkers()
        StrategyEditorSetStatus("Could not load strategy: " err.Message, true)
    }
}
