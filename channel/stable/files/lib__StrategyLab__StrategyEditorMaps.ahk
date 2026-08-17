#Requires AutoHotkey v2.0

StrategyEditorLoadSnapshot(*) {
    global LabEditorSnapshot, LabEditorCanvasBg
    path := FileSelect(1, , "Choose Roblox/TDS screenshot", "Images (*.png; *.jpg; *.jpeg; *.bmp)")
    if (path = "")
        return
    StrategyEditorSetBackground(path, "snapshot")
    StrategyEditorSetStatus("Reference snapshot loaded. This screen-view image uses the strategy coordinate plane.")
}

StrategyEditorCaptureRoblox(*) {
    global LabEditorSnapshot, LabEditorCanvasBg, MainGui
    if !WinExist("ahk_exe RobloxPlayerBeta.exe") {
        StrategyEditorSetStatus("Roblox is not running.", true)
        return
    }

    ; The editor itself can overlap Roblox. Hide it before screen capture so the
    ; reference image contains only the Roblox client, then always restore the GUI.
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
        ; Show without stealing focus from Roblox. The previous position/options are retained.
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
    StrategyEditorSetStatus("Captured a clean Roblox client image and saved it to the map library" (mapName != "" ? " for " mapName : "") ".")
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
    return "No map image cached yet."
}

StrategyEditorAutoLoadMap() {
    global LabEditorMapLabel, LabEditorCurrentMap
    mapName := StrategyEditorMapName()
    LabEditorCurrentMap := mapName
    LabEditorMapLabel.Text := mapName != "" ? "Map: " mapName : "Map: unknown"
    if (mapName = "")
        return
    bg := LabMapPreferredBackground(mapName)
    if (bg.path != "")
        StrategyEditorSetBackground(bg.path, bg.mode)
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
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH, LabEditorSnapshot, LabEditorCanvasBg, LabEditorZoomLabel
    if (LabEditorSourceImage = "" || !FileExist(LabEditorSourceImage)) {
        LabEditorSnapshot.Visible := false
        LabEditorCanvasBg.Visible := true
        return false
    }
    dir := A_AppData "\Ultimate_Macro\StrategyEditor"
    if !DirExist(dir)
        DirCreate(dir)
    if LabMapRenderViewport(LabEditorSourceImage, LabEditorViewport, LabEditorViewportPath, LabEditorCanvasW, LabEditorCanvasH) {
        ; Force Picture to reload even when the temp path did not change.
        LabEditorSnapshot.Value := ""
        LabEditorSnapshot.Value := LabEditorViewportPath
        LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
        LabEditorSnapshot.Visible := true
        LabEditorCanvasBg.Visible := false
        LabEditorZoomLabel.Text := Round(LabEditorViewport.Zoom * 100) "%"
        StrategyEditorRefreshVisuals()
        return true
    }
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
    global LabEditorTowerPortrait, LabEditorTowerName, LabEditorList, LabEditorCoordLabel, LabEditorDirtyLabel
    global LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn
    global LabEditorDirty, LabEditorStatus, LabEditorSnapshot, LabEditorCanvasBg
    LabEditorExpanded := !LabEditorExpanded
    if LabEditorExpanded {
        LabEditorCanvasW := 640
        LabEditorCanvasH := 345
        LabEditorExpandBtn.Text := "Compact"
        for ctrl in [LabEditorTowerPortrait, LabEditorTowerName, LabEditorList, LabEditorCoordLabel, LabEditorDirtyLabel,
            LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus]
            ctrl.Visible := false
    } else {
        LabEditorCanvasW := 420
        LabEditorCanvasH := 236
        LabEditorExpandBtn.Text := "Expand"
        for ctrl in [LabEditorTowerPortrait, LabEditorTowerName, LabEditorList, LabEditorCoordLabel, LabEditorDirtyLabel,
            LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus]
            ctrl.Visible := true
    }
    LabEditorCanvasBg.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    StrategyEditorRenderBackground()
    StrategyEditorRefreshVisuals()
}

StrategyEditorShowTower(placement) {
    global LabEditorDoc, LabEditorTowerPortrait, LabEditorTowerName
    towerName := LabEditorDoc.TowerNameForSlot(placement.slot)
    if (towerName = "")
        towerName := "Slot " placement.slot
    entry := LabTowerResolve(towerName)
    portrait := LabTowerPortraitPath(towerName)
    if (portrait != "")
        LabEditorTowerPortrait.Value := portrait
    limitText := entry.placementLimit = 1 ? "Unique placement" : (entry.placementLimit > 1 ? "Limit: " entry.placementLimit : "Placement limit: catalog pending")
    LabEditorTowerName.Text := LabTowerPlacementDisplay(LabEditorDoc, placement) "`n" limitText
}

StrategyEditorMaybeAutoSyncAssets() {
    global LabEditorAssetsRequested, LabEditorDoc
    if LabEditorAssetsRequested || !IsObject(LabEditorDoc)
        return
    mapName := StrategyEditorMapName()
    marker := A_AppData "\Ultimate_Macro\StrategyEditor\asset-sync-" LabMapSafeKey(mapName) ".done"
    if (mapName != "" && FileExist(marker))
        return
    LabEditorAssetsRequested := true
    SetTimer(StrategyEditorSyncAssets, -250)
}

StrategyEditorSyncAssets(*) {
    global LabEditorSyncBtn, LabEditorAssetSyncPid
    if (LabEditorAssetSyncPid && ProcessExist(LabEditorAssetSyncPid))
        return
    script := A_ScriptDir "\submacros\lab_assets.ps1"
    if !FileExist(script) {
        StrategyEditorSetStatus("Asset sync helper is missing.", true)
        return
    }
    LabEditorSyncBtn.Enabled := false
    LabEditorSyncBtn.Text := "Syncing..."
    StrategyEditorSetStatus("Syncing lightweight base tower portraits and available top-down references from the TDS Wiki in the background...")
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
        StrategyEditorSetStatus("Asset sync could not start: " err.Message, true)
    }
}

StrategyEditorAssetSyncPoll(*) {
    global LabEditorAssetSyncPid, LabEditorSyncBtn, LabEditorDoc, LabEditorSelectedRow
    if (LabEditorAssetSyncPid && ProcessExist(LabEditorAssetSyncPid))
        return
    SetTimer(StrategyEditorAssetSyncPoll, 0)
    LabEditorAssetSyncPid := 0
    LabEditorSyncBtn.Enabled := true
    LabEditorSyncBtn.Text := "Sync Assets"
    if IsObject(LabEditorDoc) {
        StrategyEditorAutoLoadMap()
        if (LabEditorSelectedRow > 0)
            StrategyEditorShowTower(LabEditorDoc.Placements[LabEditorSelectedRow])
    }
    StrategyEditorRenderBackground()
    StrategyEditorSetStatus("Asset sync finished. Exact coordinate editing prefers the macro-camera capture saved for that map; Wiki top-downs are clearly marked reference-only.")
}
