#Requires AutoHotkey v2.0

StrategyEditorLoadSnapshot(*) {
    path := FileSelect(1, , "Choose Roblox/TDS screenshot", "Images (*.png; *.jpg; *.jpeg; *.bmp)")
    if (path = "")
        return
    StrategyEditorSetBackground(path, "snapshot")
    StrategyEditorSetStatus("Reference snapshot loaded. This screen-view image uses the strategy coordinate plane.")
}

StrategyEditorCaptureRoblox(*) {
    global MainGui, LabEditorAssetBadge
    if !WinExist("ahk_exe RobloxPlayerBeta.exe") {
        StrategyEditorSetStatus("Roblox is not running.", true)
        return
    }

    pBitmap := 0
    captureError := ""
    capturePath := ""
    MainGui.Hide()
    try {
        Sleep(180)
        try WinActivate("ahk_exe RobloxPlayerBeta.exe")
        try WinWaitActive("ahk_exe RobloxPlayerBeta.exe", , 1)
        Sleep(120)

        getRobloxPos(&pX, &pY, &w, &h)
        if (w < 100 || h < 100)
            throw Error("Could not read the Roblox client area.")

        dir := A_AppData "\Ultimate_Macro\StrategyEditor"
        if !DirExist(dir)
            DirCreate(dir)
        capturePath := dir "\last-capture.png"
        pBitmap := Gdip_BitmapFromScreen(pX "|" pY "|" w "|" h)
        if !pBitmap
            throw Error("Could not capture Roblox.")

        Gdip_SaveBitmapToFile(pBitmap, capturePath, 95)
    } catch Error as err {
        captureError := err.Message
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
        try MainGui.Show("NA")
    }

    if (captureError != "") {
        StrategyEditorSetStatus(captureError, true)
        return
    }

    mapName := StrategyEditorMapName()
    if (mapName != "") {
        libraryPath := LabMapSaveCameraCapture(mapName, capturePath)
        if (libraryPath != "")
            capturePath := libraryPath
    }
    StrategyEditorSetBackground(capturePath, "camera")
    LabEditorAssetBadge.Text := "Assets: exact camera map"
    StrategyEditorSetStatus("Captured Roblox cleanly and saved the exact macro-camera view" (mapName != "" ? " for " mapName : "") ".")
}

StrategyEditorMapName() {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return ""
    return LabEditorDoc.Settings.Has("map") ? Trim(LabEditorDoc.Settings["map"]) : ""
}

StrategyEditorBackgroundDescription() {
    global LabEditorBackgroundMode
    if (LabEditorBackgroundMode = "camera")
        return "Exact camera map loaded."
    if (LabEditorBackgroundMode = "reference")
        return "Top-down reference loaded; Capture once to unlock exact drag alignment."
    if (LabEditorBackgroundMode = "snapshot")
        return "Reference snapshot loaded."
    return "No tactical map cached yet."
}

StrategyEditorClearBackground() {
    global LabEditorSourceImage, LabEditorBackgroundMode, LabEditorSnapshot, LabEditorViewport
    LabEditorSourceImage := ""
    LabEditorBackgroundMode := "none"
    LabEditorSnapshot.Value := ""
    LabEditorViewport.Reset()
    StrategyEditorRenderBackground()
}

StrategyEditorAutoLoadMap() {
    global LabEditorMapLabel, LabEditorCurrentMap, LabEditorAssetBadge
    mapName := StrategyEditorMapName()
    LabEditorCurrentMap := mapName
    LabEditorMapLabel.Text := mapName != "" ? "Map: " mapName : "Map: unknown"
    if (mapName = "") {
        StrategyEditorClearBackground()
        LabEditorAssetBadge.Text := "Assets: map unknown"
        return
    }
    bg := LabMapPreferredBackground(mapName)
    if (bg.path != "") {
        StrategyEditorSetBackground(bg.path, bg.mode)
        LabEditorAssetBadge.Text := bg.mode = "camera" ? "Assets: exact camera map" : "Assets: top-down reference"
    } else {
        StrategyEditorClearBackground()
        LabEditorAssetBadge.Text := "Assets: syncing needed"
    }
}

StrategyEditorSetBackground(path, mode := "snapshot") {
    global LabEditorSourceImage, LabEditorBackgroundMode, LabEditorViewport
    if (path = "" || !FileExist(path))
        return false
    LabEditorSourceImage := path
    LabEditorBackgroundMode := mode
    LabEditorViewport.Reset()
    StrategyEditorRenderBackground()
    return true
}

StrategyEditorRenderBackground() {
    global LabEditorSourceImage, LabEditorViewport, LabEditorViewportPath
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorSnapshot, LabEditorCanvasBg, LabEditorCanvasHint, LabEditorZoomLabel

    if (LabEditorSourceImage = "" || !FileExist(LabEditorSourceImage)) {
        LabEditorSnapshot.Visible := false
        LabEditorCanvasBg.Visible := true
        LabEditorCanvasHint.Visible := true
        LabEditorCanvasHint.Move(LabEditorCanvasX + 44, LabEditorCanvasY + Floor(LabEditorCanvasH / 2) - 26,
            Max(220, LabEditorCanvasW - 88), 52)
        LabEditorZoomLabel.Text := "100%"
        StrategyEditorRefreshVisuals()
        return false
    }

    dir := A_AppData "\Ultimate_Macro\StrategyEditor"
    if !DirExist(dir)
        DirCreate(dir)
    if LabMapRenderViewport(LabEditorSourceImage, LabEditorViewport, LabEditorViewportPath, LabEditorCanvasW, LabEditorCanvasH) {
        LabEditorSnapshot.Value := ""
        LabEditorSnapshot.Value := LabEditorViewportPath
        LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
        LabEditorSnapshot.Visible := true
        LabEditorCanvasBg.Visible := false
        LabEditorCanvasHint.Visible := false
        LabEditorZoomLabel.Text := Round(LabEditorViewport.Zoom * 100) "%"
        StrategyEditorRefreshVisuals()
        return true
    }

    LabEditorSnapshot.Visible := false
    LabEditorCanvasBg.Visible := true
    LabEditorCanvasHint.Text := "The cached image could not be rendered.`nRun Sync Assets again or Capture Roblox."
    LabEditorCanvasHint.Visible := true
    return false
}

StrategyEditorPlacementPoint(placement) {
    global LabEditorDoc, LabEditorViewport
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    if !IsObject(LabEditorDoc)
        return {x: LabEditorCanvasX, y: LabEditorCanvasY, visible: false}
    point := LabEditorViewport.StrategyToViewport(
        placement.x, placement.y, LabEditorDoc.StrategyWidth, LabEditorDoc.StrategyHeight,
        LabEditorCanvasW, LabEditorCanvasH)
    point.x += LabEditorCanvasX
    point.y += LabEditorCanvasY
    return point
}

StrategyEditorViewportToStrategy(mx, my) {
    global LabEditorDoc, LabEditorViewport
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    return LabEditorViewport.ViewportToStrategy(
        mx - LabEditorCanvasX, my - LabEditorCanvasY,
        LabEditorDoc.StrategyWidth, LabEditorDoc.StrategyHeight,
        LabEditorCanvasW, LabEditorCanvasH)
}

StrategyEditorZoom(delta) {
    global LabEditorViewport
    LabEditorViewport.ZoomBy(delta)
    StrategyEditorRenderBackground()
    StrategyEditorRefreshVisuals()
}

StrategyEditorZoomReset(*) {
    global LabEditorViewport
    LabEditorViewport.Reset()
    StrategyEditorRenderBackground()
    StrategyEditorRefreshVisuals()
}

StrategyEditorPan(dx, dy) {
    global LabEditorViewport
    if (LabEditorViewport.Zoom <= 1)
        return
    LabEditorViewport.Pan(dx, dy)
    StrategyEditorRenderBackground()
    StrategyEditorRefreshVisuals()
}

StrategyEditorMouseWheel(wParam, lParam, msg, hwnd) {
    global CurrentTab, LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    if (CurrentTab != "Tab7")
        return
    StrategyEditorGetClientCursor(&mx, &my)
    if (mx < LabEditorCanvasX || mx > LabEditorCanvasX + LabEditorCanvasW
        || my < LabEditorCanvasY || my > LabEditorCanvasY + LabEditorCanvasH)
        return
    delta := (wParam >> 16) & 0xFFFF
    if (delta > 32767)
        delta -= 65536
    StrategyEditorZoom(delta > 0 ? 0.25 : -0.25)
    return 0
}

StrategyEditorToggleExpanded(*) {
    global LabEditorExpanded, LabEditorCanvasW, LabEditorCanvasH, LabEditorExpandBtn
    global LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList, LabEditorCoordLabel, LabEditorDirtyLabel
    global LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn
    global LabEditorDirty, LabEditorStatus, LabEditorSnapshot, LabEditorCanvasBg, LabEditorCanvasHint, LabEditorInfoPanel
    LabEditorExpanded := !LabEditorExpanded
    if LabEditorExpanded {
        LabEditorCanvasW := 650
        LabEditorCanvasH := 300
        LabEditorExpandBtn.Text := "Compact"
        for ctrl in [LabEditorInfoPanel, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList,
            LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn,
            LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus]
            ctrl.Visible := false
    } else {
        LabEditorCanvasW := 438
        LabEditorCanvasH := 238
        LabEditorExpandBtn.Text := "Expand"
        for ctrl in [LabEditorInfoPanel, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList,
            LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn,
            LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus]
            ctrl.Visible := true
    }
    LabEditorCanvasBg.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    LabEditorCanvasHint.Move(LabEditorCanvasX + 44, LabEditorCanvasY + Floor(LabEditorCanvasH / 2) - 26,
        Max(220, LabEditorCanvasW - 88), 52)
    StrategyEditorRenderBackground()
    StrategyEditorRefreshVisuals()
}

StrategyEditorShowTower(placement) {
    global LabEditorDoc, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta
    towerName := LabEditorDoc.TowerNameForSlot(placement.slot)
    if (towerName = "")
        towerName := "Slot " placement.slot
    portrait := LabTowerPortraitPath(towerName)
    LabEditorTowerPortrait.Value := ""
    if (portrait != "")
        LabEditorTowerPortrait.Value := portrait
    LabEditorTowerName.Text := LabTowerPlacementDisplay(LabEditorDoc, placement)
    LabEditorTowerMeta.Text := LabTowerPlacementMeta(LabEditorDoc, placement) "`nX " placement.x "  •  Y " placement.y
}

StrategyEditorAssetsMissing() {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return false
    mapName := StrategyEditorMapName()
    if (mapName != "" && LabMapPreferredBackground(mapName).path = "")
        return true
    for tower in LabEditorDoc.RequiredTowers {
        if (LabTowerCachedPortraitPath(tower) = "")
            return true
    }
    return false
}

StrategyEditorMaybeAutoSyncAssets() {
    global LabEditorAssetsRequested, LabEditorDoc, LabEditorAssetBadge
    if LabEditorAssetsRequested || !IsObject(LabEditorDoc)
        return
    if !StrategyEditorAssetsMissing() {
        LabEditorAssetBadge.Text := "Assets: ready"
        return
    }
    LabEditorAssetsRequested := true
    LabEditorAssetBadge.Text := "Assets: queued"
    SetTimer(StrategyEditorSyncAssets, -250)
}

StrategyEditorSyncAssets(*) {
    global LabEditorSyncBtn, LabEditorAssetSyncPid, LabEditorDoc, LabEditorAssetBadge
    if (LabEditorAssetSyncPid && ProcessExist(LabEditorAssetSyncPid))
        return
    script := A_ScriptDir "\submacros\lab_assets.ps1"
    if !FileExist(script) {
        StrategyEditorSetStatus("Asset sync helper is missing.", true)
        return
    }
    LabEditorSyncBtn.Enabled := false
    LabEditorSyncBtn.Text := "Syncing..."
    LabEditorAssetBadge.Text := "Assets: syncing..."
    StrategyEditorSetStatus("Syncing base tower portraits and the current map's top-down reference from the TDS Wiki...")
    mapName := StrategyEditorMapName()
    towerNames := ""
    if IsObject(LabEditorDoc) {
        for tower in LabEditorDoc.RequiredTowers {
            entry := LabTowerResolve(tower)
            towerNames .= (towerNames != "" ? "|" : "") entry.name
        }
    }
    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' script
        . '" -InstallDir "' A_ScriptDir '" -MapName "' StrReplace(mapName, '"', '')
        . '" -TowerNames "' StrReplace(towerNames, '"', '') '"'
    try {
        Run(cmd, , "Hide", &LabEditorAssetSyncPid)
        SetTimer(StrategyEditorAssetSyncPoll, 500)
    } catch Error as err {
        LabEditorAssetSyncPid := 0
        LabEditorSyncBtn.Enabled := true
        LabEditorSyncBtn.Text := "Sync Assets"
        LabEditorAssetBadge.Text := "Assets: sync failed"
        StrategyEditorSetStatus("Asset sync could not start: " err.Message, true)
    }
}

StrategyEditorAssetSyncPoll(*) {
    global LabEditorAssetSyncPid, LabEditorSyncBtn, LabEditorDoc, LabEditorSelectedRow, LabEditorAssetBadge
    if (LabEditorAssetSyncPid && ProcessExist(LabEditorAssetSyncPid))
        return
    SetTimer(StrategyEditorAssetSyncPoll, 0)
    LabEditorAssetSyncPid := 0
    LabEditorSyncBtn.Enabled := true
    LabEditorSyncBtn.Text := "Sync Assets"

    towers := 0
    maps := 0
    misses := 0
    errors := 0
    statusPath := A_AppData "\Ultimate_Macro\StrategyEditor\asset-sync-status.ini"
    if FileExist(statusPath) {
        try towers := Integer(IniRead(statusPath, "Sync", "Towers", 0))
        try maps := Integer(IniRead(statusPath, "Sync", "Maps", 0))
        try misses := Integer(IniRead(statusPath, "Sync", "Misses", 0))
        try errors := Integer(IniRead(statusPath, "Sync", "Errors", 0))
    }

    if IsObject(LabEditorDoc) {
        selected := LabEditorSelectedRow
        StrategyEditorAutoLoadMap()
        if (selected > 0)
            StrategyEditorSelectPlacement(selected)
    }
    StrategyEditorRenderBackground()

    if (towers > 0 || maps > 0)
        LabEditorAssetBadge.Text := "Assets: " towers " tower" (towers = 1 ? "" : "s") " • " maps " map" (maps = 1 ? "" : "s")
    else if (errors > 0 || misses > 0)
        LabEditorAssetBadge.Text := "Assets: no new art found"
    else
        LabEditorAssetBadge.Text := StrategyEditorAssetsMissing() ? "Assets: incomplete" : "Assets: ready"

    StrategyEditorSetStatus("Asset sync complete: " towers " tower portrait(s), " maps " map reference(s), " misses " miss(es), " errors " error(s). " StrategyEditorBackgroundDescription())
}
