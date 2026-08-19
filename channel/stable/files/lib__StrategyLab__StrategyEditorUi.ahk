#Requires AutoHotkey v2.0

StrategyEditorCreateTab(gui) {
    global LabEditorCtrls
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorOpenBtn, LabEditorCurrentBtn, LabEditorSnapshotBtn, LabEditorCaptureBtn
    global LabEditorUndoBtn, LabEditorRedoBtn, LabEditorLayerCtrl, LabEditorCanvasBg, LabEditorSnapshot
    global LabEditorList, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn
    global LabEditorOverwriteBtn, LabEditorStatus, LabEditorDirty
    global LabEditorZoomOutBtn, LabEditorZoomLabel, LabEditorZoomInBtn, LabEditorFitBtn, LabEditorExpandBtn
    global LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn, LabEditorSyncBtn, LabEditorRingsBtn, LabEditorRemoteBtn
    global LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorMapLabel, LabEditorCoordLabel, LabEditorDirtyLabel
    global LabEditorAssetBadge, LabEditorInfoPanel, LabEditorCanvasHint
    global LabEditorTitle, LabEditorSubtitle, LabEditorHeaderLine, LabEditorLayerLabel

    gui.SetFont("s11 w700 c4CA3FF", "Segoe UI")
    LabEditorTitle := gui.Add("Text", "x20 y94 w300 h24 Hidden", "Visual Strategy Editor")
    gui.SetFont("s7 w400 c8E8E8E", "Segoe UI")
    LabEditorSubtitle := gui.Add("Text", "x20 y116 w520 h18 Hidden", "Exact Roblox screenshot • single-canvas circles • safe saves")
    LabEditorAssetBadge := gui.Add("Text", "x470 y103 w200 h18 Hidden Right c8E8E8E", "Map source: waiting for strategy")
    LabEditorHeaderLine := gui.Add("Progress", "x20 y137 w650 h1 Hidden Background333333", 0)

    gui.SetFont("s8 w500 cFFFFFF", "Segoe UI")
    LabEditorOpenBtn := gui.Add("Button", "x20 y145 w58 h28 Hidden", "Open")
    LabEditorCurrentBtn := gui.Add("Button", "x82 y145 w82 h28 Hidden", "Current")
    LabEditorSnapshotBtn := gui.Add("Button", "x168 y145 w72 h28 Hidden", "Snapshot")
    LabEditorCaptureBtn := gui.Add("Button", "x244 y145 w82 h28 Hidden", "Capture Map")
    LabEditorUndoBtn := gui.Add("Button", "x334 y145 w52 h28 Hidden", "Undo")
    LabEditorRedoBtn := gui.Add("Button", "x390 y145 w52 h28 Hidden", "Redo")
    LabEditorZoomOutBtn := gui.Add("Button", "x446 y145 w28 h28 Hidden", "−")
    LabEditorZoomLabel := gui.Add("Button", "x478 y145 w52 h28 Hidden", "100%")
    LabEditorZoomInBtn := gui.Add("Button", "x534 y145 w28 h28 Hidden", "+")
    LabEditorFitBtn := gui.Add("Button", "x566 y145 w46 h28 Hidden", "Fit")
    LabEditorExpandBtn := gui.Add("Button", "x616 y145 w54 h28 Hidden", "Expand")

    gui.SetFont("s7 w500 cA8A8A8", "Segoe UI")
    LabEditorLayerLabel := gui.Add("Text", "x20 y181 w34 h18 Hidden", "Layer")
    gui.SetFont("s8 w400 c000000", "Segoe UI")
    LabEditorLayerCtrl := gui.Add("DropDownList", "x55 y177 w230 Hidden", ["All placements"])
    gui.SetFont("s8 w500 cFFFFFF", "Segoe UI")
    ; Kept as hidden compatibility sentinels. Mouse drag/pan is direct on the canvas.
    LabEditorPanLeftBtn := gui.Add("Button", "x-1000 y-1000 w1 h1 Hidden", "←")
    LabEditorPanUpBtn := gui.Add("Button", "x-1000 y-1000 w1 h1 Hidden", "↑")
    LabEditorPanDownBtn := gui.Add("Button", "x-1000 y-1000 w1 h1 Hidden", "↓")
    LabEditorPanRightBtn := gui.Add("Button", "x-1000 y-1000 w1 h1 Hidden", "→")
    LabEditorSyncBtn := gui.Add("Button", "x298 y177 w104 h24 Hidden", "Refresh View")
    LabEditorRingsBtn := gui.Add("Button", "x412 y177 w92 h24 Hidden", "Radii: All")
    LabEditorRemoteBtn := gui.Add("Button", "x532 y177 w64 h24 Hidden", "Remote")
    gui.SetFont("s7 w500 cA8A8A8", "Segoe UI")
    LabEditorMapLabel := gui.Add("Text", "x600 y181 w70 h18 Hidden Right", "Map: -")

    ; Only TWO native canvas controls: a dark fallback + the fully composited frame.
    LabEditorCanvasBg := gui.Add("Text", "x" LabEditorCanvasX " y" LabEditorCanvasY
        " w" LabEditorCanvasW " h" LabEditorCanvasH " Hidden +Border Background171717")
    LabEditorSnapshot := gui.Add("Picture", "x" LabEditorCanvasX " y" LabEditorCanvasY
        " w" LabEditorCanvasW " h" LabEditorCanvasH " Hidden +Border")
    gui.SetFont("s9 w600 c777777", "Segoe UI")
    LabEditorCanvasHint := gui.Add("Text", "x75 y292 w330 h48 Hidden Center Background171717",
        "No camera screenshot for this map yet.`nOpen Roblox on the map and press Capture Map.")

    LabEditorInfoPanel := gui.Add("Text", "x470 y205 w200 h238 Hidden +Border Background171717")
    ; Local vanity badge: no website image and no separate in-map control.
    gui.SetFont("s17 w700 cFFFFFF", "Segoe UI")
    LabEditorTowerPortrait := gui.Add("Text", "x482 y217 w62 h62 Hidden Center 0x200 +Border Background283341", "?")
    StrategyEditorSetCircularRegion(LabEditorTowerPortrait, 62)
    gui.SetFont("s10 w700 cF2F2F2", "Segoe UI")
    LabEditorTowerName := gui.Add("Text", "x554 y218 w106 h38 Hidden Background171717", "Select a placement")
    gui.SetFont("s7 w400 c9C9C9C", "Segoe UI")
    LabEditorTowerMeta := gui.Add("Text", "x554 y258 w106 h42 Hidden Background171717", "Click a circle or row")

    gui.SetFont("s8 w400 cEAEAEA", "Segoe UI")
    LabEditorList := gui.Add("ListView", "x480 y306 w180 h127 Hidden Grid -Multi Background202020 cEAEAEA", ["#", "Unit", "X", "Y"])
    LabEditorList.ModifyCol(1, 25)
    LabEditorList.ModifyCol(2, 88)
    LabEditorList.ModifyCol(3, 34)
    LabEditorList.ModifyCol(4, 34)

    gui.SetFont("s8 w500 cAFAFAF", "Segoe UI")
    LabEditorCoordLabel := gui.Add("Text", "x20 y451 w124 h20 Hidden", "Selected coordinates")
    LabEditorDirtyLabel := gui.Add("Text", "x470 y451 w200 h20 Hidden Right", "Edits stay in memory until saved")

    gui.SetFont("s8 w500 c000000", "Segoe UI")
    LabEditorXCtrl := gui.Add("Edit", "x146 y447 w58 h24 Hidden Number")
    LabEditorYCtrl := gui.Add("Edit", "x209 y447 w58 h24 Hidden Number")
    LabEditorApplyBtn := gui.Add("Button", "x272 y445 w82 h28 Hidden", "Apply X/Y")

    gui.SetFont("s8 w500 cFFFFFF", "Segoe UI")
    LabEditorSaveBtn := gui.Add("Button", "x360 y445 w82 h28 Hidden", "Save Copy")
    LabEditorOverwriteBtn := gui.Add("Button", "x470 y475 w200 h30 Hidden", "Overwrite + automatic backup")

    gui.SetFont("s7 w500 cB0B0B0", "Segoe UI")
    LabEditorDirty := gui.Add("Text", "x20 y480 w430 h18 Hidden", "No strategy loaded.")
    LabEditorStatus := gui.Add("Text", "x20 y505 w650 h38 Hidden c909090", "Open a .strat or use the current Strategy 1.")

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
    LabEditorExpandBtn.OnEvent("Click", StrategyEditorToggleExpanded)
    LabEditorSyncBtn.OnEvent("Click", StrategyEditorSyncAssets)
    LabEditorRingsBtn.OnEvent("Click", StrategyEditorToggleRings)
    LabEditorRemoteBtn.OnEvent("Click", LabRemoteLaunchSettings)
    LabEditorLayerCtrl.OnEvent("Change", StrategyEditorLayerChanged)
    LabEditorList.OnEvent("ItemSelect", StrategyEditorRowSelected)
    LabEditorApplyBtn.OnEvent("Click", StrategyEditorApplyCoordinates)
    LabEditorSaveBtn.OnEvent("Click", StrategyEditorSaveCopy)
    LabEditorOverwriteBtn.OnEvent("Click", StrategyEditorOverwrite)

    LabEditorCtrls := [
        LabEditorTitle, LabEditorSubtitle, LabEditorAssetBadge, LabEditorHeaderLine,
        LabEditorOpenBtn, LabEditorCurrentBtn, LabEditorSnapshotBtn, LabEditorCaptureBtn,
        LabEditorUndoBtn, LabEditorRedoBtn, LabEditorZoomOutBtn, LabEditorZoomLabel, LabEditorZoomInBtn,
        LabEditorFitBtn, LabEditorExpandBtn, LabEditorLayerLabel, LabEditorLayerCtrl, LabEditorPanLeftBtn, LabEditorPanUpBtn,
        LabEditorPanDownBtn, LabEditorPanRightBtn, LabEditorSyncBtn, LabEditorRingsBtn, LabEditorRemoteBtn, LabEditorMapLabel,
        LabEditorCanvasBg, LabEditorSnapshot, LabEditorCanvasHint, LabEditorInfoPanel,
        LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList,
        LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn,
        LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus
    ]
    return LabEditorCtrls
}

StrategyEditorShow() {
    global LabEditorCtrls, LabEditorDoc, LabEditorSnapshot, LabEditorExpanded
    global LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList, LabEditorCoordLabel, LabEditorDirtyLabel
    global LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus
    global LabEditorInfoPanel, LabEditorRingsBtn

    for ctrl in LabEditorCtrls {
        if LabEditorControlAlive(ctrl)
            try ctrl.Visible := true
    }
    if LabEditorControlAlive(LabEditorRingsBtn)
        try LabEditorRingsBtn.Text := StrategyEditorRingButtonText()

    if LabEditorExpanded {
        for ctrl in [LabEditorInfoPanel, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList,
            LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn,
            LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus] {
            if LabEditorControlAlive(ctrl)
                try ctrl.Visible := false
        }
    }

    StrategyEditorMaybeAutoSyncAssets()
    StrategyEditorRenderBackground()
    StrategyEditorRefreshButtons()
}

; Compatibility helper for any old caller. In 0.4 hwnd is irrelevant; hit-testing is
; performed against the circles painted into the canvas.
StrategyEditorTryBeginDrag(hwnd := 0) {
    StrategyEditorGetClientCursor(&mx, &my)
    index := StrategyEditorHitTestPlacement(mx, my)
    return index > 0 ? StrategyEditorBeginDrag(index) : false
}

StrategyEditorOpen(*) {
    path := FileSelect(1, , "Open Ultimate Macro strategy", "Strategy (*.strat)")
    if (path != "")
        StrategyEditorLoadPath(path)
}

StrategyEditorUseCurrent(*) {
    global Strategy1Ctrl, Strategy1Path
    path := ""
    if IsSet(Strategy1Ctrl) && IsObject(Strategy1Ctrl)
        try path := Trim(Strategy1Ctrl.Text)
    if (path = "" && IsSet(Strategy1Path))
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
        LabStrategyValidate(path)
        LabEditorDoc := LabStratDocument(path)
        if (LabEditorDoc.Placements.Length = 0)
            throw Error("No SpawnTower placements were found in [Steps].")
        LabEditorLayer := "All placements"
        LabEditorSelectedRow := 0
        LabEditorAssetsRequested := false
        StrategyEditorBuildLayers()
        StrategyEditorAutoLoadMap()
        StrategyEditorBuildMarkers()
        StrategyEditorSelectPlacement(1)
        StrategyEditorSetStatus("Loaded " LabEditorDoc.Placements.Length " placements from " path ". " StrategyEditorBackgroundDescription())
        StrategyEditorRefreshButtons()
        StrategyEditorRefreshDirty()
    } catch Error as err {
        LabEditorDoc := ""
        StrategyEditorClearMarkers()
        StrategyEditorSetStatus("Could not load strategy: " err.Message, true)
    }
}
