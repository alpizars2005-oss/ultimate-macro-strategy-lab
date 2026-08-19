#Requires AutoHotkey v2.0

; Strategy Lab 0.4.3 map/canvas renderer.
; The exact Roblox/macro-camera screenshot is the only coordinate background. Tower
; portraits may be cached from the TDS Wiki, but web map art is never used here.
;
; Critical performance change: the live canvas is now built as a GDI+ bitmap and
; swapped directly into one SS_BITMAP Picture control. Drag/pan/zoom no longer encode,
; write and re-open a JPEG for every mouse-move frame.

StrategyEditorReleaseCanvasBitmap(*) {
    global LabEditorCanvasBitmap, LabEditorSnapshot
    current := LabEditorCanvasBitmap
    LabEditorCanvasBitmap := 0
    if !current
        return

    old := 0
    if LabEditorControlAlive(LabEditorSnapshot) {
        hwnd := 0
        try hwnd := LabEditorSnapshot.Hwnd
        if hwnd
            try old := DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x0172,
                "Ptr", 0, "Ptr", 0, "Ptr") ; STM_SETIMAGE / IMAGE_BITMAP
    }
    if old
        try DllCall("gdi32\DeleteObject", "Ptr", old)
    else
        try DllCall("gdi32\DeleteObject", "Ptr", current)
}
OnExit(StrategyEditorReleaseCanvasBitmap)

StrategyEditorLoadSnapshot(*) {
    path := FileSelect(1, , "Choose Roblox/TDS screenshot", "Images (*.png; *.jpg; *.jpeg; *.bmp)")
    if (path = "")
        return
    StrategyEditorSetBackground(path, "snapshot")
    StrategyEditorSetStatus("Screenshot loaded. True placement footprints are projected over this canvas.")
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
    restoreGui := false
    try {
        if IsSet(MainGui) && IsObject(MainGui) {
            mainHwnd := 0
            try mainHwnd := MainGui.Hwnd
            if (mainHwnd && DllCall("user32\IsWindow", "Ptr", mainHwnd, "Int")
                && DllCall("user32\IsWindowVisible", "Ptr", mainHwnd, "Int")) {
                try MainGui.Hide()
                restoreGui := true
            }
        }
        Sleep(120)
        try WinActivate("ahk_exe RobloxPlayerBeta.exe")
        try WinWaitActive("ahk_exe RobloxPlayerBeta.exe", , 1)
        Sleep(80)

        getRobloxPos(&pX, &pY, &w, &h)
        if (w < 100 || h < 100)
            throw Error("Could not read the Roblox client area.")

        pBitmap := Gdip_BitmapFromScreen(pX "|" pY "|" w "|" h)
        if !pBitmap
            throw Error("Could not capture Roblox.")

        mapName := StrategyEditorMapName()
        if (mapName != "") {
            capturePath := LabMapSaveCameraBitmap(mapName, pBitmap, "manual")
            if (capturePath = "")
                throw Error("Could not save the camera screenshot.")
        } else {
            dir := A_AppData "\Ultimate_Macro\StrategyEditor"
            if !DirExist(dir)
                DirCreate(dir)
            capturePath := dir "\last-capture.jpg"
            Gdip_SaveBitmapToFile(pBitmap, capturePath, 86)
            if !FileExist(capturePath)
                throw Error("Could not save the camera screenshot.")
        }
    } catch Error as err {
        captureError := err.Message
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
        if restoreGui && IsSet(MainGui) && IsObject(MainGui)
            try MainGui.Show("NA")
    }

    if (captureError != "") {
        StrategyEditorSetStatus(captureError, true)
        return
    }

    StrategyEditorSetBackground(capturePath, "camera")
    if LabEditorControlAlive(LabEditorAssetBadge)
        try LabEditorAssetBadge.Text := "Map source: exact screenshot"
    StrategyEditorSetStatus("Captured the exact Roblox view used by the macro" (StrategyEditorMapName() != "" ? " for " StrategyEditorMapName() : "") ".")
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
        return "Exact macro-camera screenshot loaded."
    if (LabEditorBackgroundMode = "snapshot")
        return "Manual screenshot loaded."
    return "Run this strategy once (or press Capture Map) to create its exact camera canvas."
}

StrategyEditorClearBackground() {
    global LabEditorSourceImage, LabEditorBackgroundMode, LabEditorViewport, LabEditorHitRegions
    LabEditorSourceImage := ""
    LabEditorBackgroundMode := "none"
    LabEditorHitRegions := []
    LabEditorViewport.Reset()
    StrategyEditorReleaseCanvasBitmap()
    StrategyEditorRenderBackground()
}

StrategyEditorAutoLoadMap() {
    global LabEditorMapLabel, LabEditorCurrentMap, LabEditorAssetBadge
    mapName := StrategyEditorMapName()
    LabEditorCurrentMap := mapName
    if LabEditorControlAlive(LabEditorMapLabel)
        try LabEditorMapLabel.Text := mapName != "" ? "Map: " mapName : "Map: unknown"

    if (mapName = "") {
        StrategyEditorClearBackground()
        if LabEditorControlAlive(LabEditorAssetBadge)
            try LabEditorAssetBadge.Text := "Map source: unknown"
        return
    }

    camera := LabMapCameraPath(mapName)
    if (camera != "") {
        StrategyEditorSetBackground(camera, "camera")
        if LabEditorControlAlive(LabEditorAssetBadge)
            try LabEditorAssetBadge.Text := LabMapCameraCaptureStage(mapName) = "" ? "Map source: legacy • refresh pending" : "Map source: exact screenshot"
    } else {
        StrategyEditorClearBackground()
        if LabEditorControlAlive(LabEditorAssetBadge)
            try LabEditorAssetBadge.Text := "Map source: capture pending"
    }

    ; Portrait sync is strategy-scoped (at most the towers this strat uses), never a
    ; catalog crawl and never a web map download.
    SetTimer(StrategyEditorMaybeAutoSyncAssets, -120)
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

StrategyEditorPreviewPlacement(index, placement) {
    return LabFootprintLogicalPoint(index, placement)
}

; Pure geometry stage shared by rendering and CI runtime tests. This remains the single
; source of truth for layer filtering + coordinate projection.
StrategyEditorCanvasPlacements() {
    global LabEditorDoc, LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    result := []
    if !IsObject(LabEditorDoc)
        return result

    for index, placement in LabEditorDoc.Placements {
        if !StrategyEditorPlacementVisible(placement)
            continue
        logical := StrategyEditorPreviewPlacement(index, placement)
        point := LabEditorViewport.StrategyToViewport(
            logical.x, logical.y,
            LabEditorDoc.StrategyWidth, LabEditorDoc.StrategyHeight,
            LabEditorCanvasW, LabEditorCanvasH)
        if !point.visible
            continue
        result.Push({index: index, placement: placement, point: point})
    }
    return result
}

StrategyEditorRebuildHitRegions(items) {
    global LabEditorHitRegions, LabEditorCanvasX, LabEditorCanvasY
    LabEditorHitRegions := []
    for item in items {
        ; Exact footprint visuals can be only 5-14px at 100% compact view. Keep a 12px
        ; click radius so selection/drag stays comfortable without lying about footprint size.
        LabEditorHitRegions.Push({
            index: item.index,
            x: item.point.x + LabEditorCanvasX,
            y: item.point.y + LabEditorCanvasY,
            radius: 12
        })
    }
    return LabEditorHitRegions
}

StrategyEditorDrawPlacement(graphics, index, placement, point, collisions, fast := false) {
    global LabEditorSelectedRow, LabEditorDoc, LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH

    selected := index = LabEditorSelectedRow
    colliding := IsObject(collisions) && collisions.Has(index)
    ellipse := LabFootprintCanvasEllipse(placement, LabEditorDoc, LabEditorViewport,
        LabEditorCanvasW, LabEditorCanvasH)
    footprintW := Max(2.0, ellipse.w)
    footprintH := Max(2.0, ellipse.h)
    halfW := footprintW / 2.0
    halfH := footprintH / 2.0

    if StrategyEditorRingModeAllows(index) {
        if colliding {
            ringColor := selected ? 0xFFFF5151 : 0xE8FF4343
            fillColor := selected ? 0x45FF3131 : 0x2AFF3131
        } else {
            ringColor := StrategyEditorSlotColor(placement.slot, selected ? 245 : 205)
            fillColor := StrategyEditorSlotColor(placement.slot, selected ? 45 : 22)
        }
        pen := 0
        brush := 0
        try {
            brush := Gdip_BrushCreateSolid(fillColor)
            if brush
                Gdip_FillEllipse(graphics, brush, point.x - halfW, point.y - halfH,
                    footprintW, footprintH)
            pen := Gdip_CreatePen(ringColor, selected ? 1.8 : 1.15)
            if pen
                Gdip_DrawEllipse(graphics, pen, point.x - halfW, point.y - halfH,
                    footprintW, footprintH)
        } finally {
            if pen
                try Gdip_DeletePen(pen)
            if brush
                try Gdip_DeleteBrush(brush)
        }
    }

    markerDiameter := LabFootprintMarkerDiameter(selected)
    markerRadius := markerDiameter / 2.0
    markerBrush := 0
    try {
        markerBrush := Gdip_BrushCreateSolid(colliding ? 0xFFFF4040 : (selected ? 0xFFFFFFFF : StrategyEditorSlotColor(placement.slot, 255)))
        if markerBrush
            Gdip_FillEllipse(graphics, markerBrush, point.x - markerRadius, point.y - markerRadius,
                markerDiameter, markerDiameter)
    } finally {
        if markerBrush
            try Gdip_DeleteBrush(markerBrush)
    }

    ; Labels are intentionally skipped during interaction. This is both faster and much
    ; less visually noisy; the exact footprint remains visible while dragging.
    if !fast {
        label := StrategyEditorMarkerLabel(placement)
        labelW := Max(16, StrLen(label) * 7)
        options := "x" (point.x + LabFootprintLabelOffset(selected)) " y" (point.y - 8)
            . " w" labelW " h16 vCenter cFFFFFFFF s7 " (selected ? "Bold" : "")
        try Gdip_TextToGraphics(graphics, label, options, "Segoe UI")
    }
}

StrategyEditorBuildCompositeBitmap() {
    global LabEditorSourceImage, LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorPanActive, LabEditorDragPlacement, LabEditorDoc

    pSource := LabMapAcquireRenderBitmap(LabEditorSourceImage, &sourceW, &sourceH)
    if !pSource || sourceW <= 0 || sourceH <= 0
        return 0

    pOut := 0
    graphics := 0
    success := false
    try {
        rect := LabEditorViewport.SourceRect(sourceW, sourceH)
        pOut := Gdip_CreateBitmap(LabEditorCanvasW, LabEditorCanvasH)
        if !pOut
            return 0
        graphics := Gdip_GraphicsFromImage(pOut)
        if !graphics
            return 0

        fast := false
        if IsSet(LabEditorPanActive)
            fast := !!LabEditorPanActive
        if IsObject(LabEditorDragPlacement)
            fast := true

        ; Nearest-quality bicubic is enough while moving. Final idle frames use the
        ; high-quality interpolation mode.
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", fast ? 5 : 7)
        try DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", fast ? 3 : 4)
        Gdip_DrawImage(graphics, pSource, 0, 0, LabEditorCanvasW, LabEditorCanvasH,
            rect.x, rect.y, rect.w, rect.h)

        items := StrategyEditorCanvasPlacements()
        StrategyEditorRebuildHitRegions(items)
        collisions := IsObject(LabEditorDoc) ? LabFootprintCollisionMap(LabEditorDoc) : Map()

        for item in items
            StrategyEditorDrawPlacement(graphics, item.index, item.placement, item.point, collisions, fast)

        success := true
        return pOut
    } finally {
        if graphics
            try Gdip_DeleteGraphics(graphics)
        if !success && pOut
            try Gdip_DisposeImage(pOut)
    }
}

; Compatibility/export helper. The live Editor NEVER calls this function; it exists for
; diagnostics that explicitly request a JPEG/PNG snapshot of the rendered canvas.
StrategyEditorRenderCompositeFrame(outputPath) {
    pOut := StrategyEditorBuildCompositeBitmap()
    if !pOut
        return false
    try {
        Gdip_SaveBitmapToFile(pOut, outputPath, 88)
        return FileExist(outputPath) && FileGetSize(outputPath) > 500
    } finally {
        try Gdip_DisposeImage(pOut)
    }
}

StrategyEditorBitmapToHBITMAP(pBitmap) {
    if !pBitmap
        return 0
    hBitmap := 0
    status := 1
    try status := DllCall("gdiplus\GdipCreateHBITMAPFromBitmap",
        "Ptr", pBitmap, "Ptr*", &hBitmap, "UInt", 0xFF171717, "Int")
    return (status = 0 && hBitmap) ? hBitmap : 0
}

StrategyEditorSwapCanvasBitmap(hBitmap) {
    global LabEditorSnapshot, LabEditorCanvasBitmap
    if !hBitmap || !LabEditorControlAlive(LabEditorSnapshot)
        return false

    hwnd := 0
    try hwnd := LabEditorSnapshot.Hwnd
    if !hwnd
        return false

    old := 0
    try old := DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x0172,
        "Ptr", 0, "Ptr", hBitmap, "Ptr") ; STM_SETIMAGE / IMAGE_BITMAP
    LabEditorCanvasBitmap := hBitmap
    if old && old != hBitmap
        try DllCall("gdi32\DeleteObject", "Ptr", old)
    try DllCall("user32\InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", true)
    return true
}

StrategyEditorRenderBackground(repositionMarkers := true) {
    global LabEditorSourceImage, LabEditorViewport
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorSnapshot, LabEditorCanvasBg, LabEditorCanvasHint, LabEditorZoomLabel, LabEditorHitRegions

    if !LabEditorControlAlive(LabEditorSnapshot) || !LabEditorControlAlive(LabEditorCanvasBg)
        return false

    if (LabEditorSourceImage = "" || !FileExist(LabEditorSourceImage)) {
        LabEditorHitRegions := []
        StrategyEditorReleaseCanvasBitmap()
        try LabEditorSnapshot.Visible := false
        try LabEditorCanvasBg.Visible := true
        if LabEditorControlAlive(LabEditorCanvasHint) {
            try LabEditorCanvasHint.Text := "No exact camera screenshot for this map yet.`nRun the strategy once or press Capture Map."
            try LabEditorCanvasHint.Move(LabEditorCanvasX + 44, LabEditorCanvasY + Floor(LabEditorCanvasH / 2) - 26,
                Max(220, LabEditorCanvasW - 88), 52)
            try LabEditorCanvasHint.Visible := true
        }
        if LabEditorControlAlive(LabEditorZoomLabel)
            try LabEditorZoomLabel.Text := "100%"
        return false
    }

    pOut := StrategyEditorBuildCompositeBitmap()
    if pOut {
        hBitmap := 0
        try hBitmap := StrategyEditorBitmapToHBITMAP(pOut)
        finally
            try Gdip_DisposeImage(pOut)

        if hBitmap && StrategyEditorSwapCanvasBitmap(hBitmap) {
            try LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
            try LabEditorSnapshot.Visible := true
            try LabEditorCanvasBg.Visible := false
            if LabEditorControlAlive(LabEditorCanvasHint)
                try LabEditorCanvasHint.Visible := false
            if LabEditorControlAlive(LabEditorZoomLabel)
                try LabEditorZoomLabel.Text := Round(LabEditorViewport.Zoom * 100) "%"
            return true
        }
        if hBitmap
            try DllCall("gdi32\DeleteObject", "Ptr", hBitmap)
    }

    LabEditorHitRegions := []
    try LabEditorSnapshot.Visible := false
    try LabEditorCanvasBg.Visible := true
    if LabEditorControlAlive(LabEditorCanvasHint) {
        try LabEditorCanvasHint.Text := "The camera screenshot could not be rendered.`nCapture Map again or choose Snapshot."
        try LabEditorCanvasHint.Visible := true
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
}

StrategyEditorZoomReset(*) {
    global LabEditorViewport
    LabEditorViewport.Reset()
    StrategyEditorRenderBackground()
}

StrategyEditorPan(dx, dy) {
    global LabEditorViewport
    if (LabEditorViewport.Zoom <= 1)
        return
    LabEditorViewport.Pan(dx, dy)
    StrategyEditorRenderBackground()
}

StrategyEditorMouseWheel(wParam, lParam, msg, hwnd) {
    return StrategyEditorInteractiveWheel(wParam, lParam, msg, hwnd)
}

StrategyEditorToggleExpanded(*) {
    global LabEditorExpanded, LabEditorExpandBtn
    global LabEditorInfoPanel, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList
    global LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn
    global LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus

    LabEditorExpanded := !LabEditorExpanded
    if LabEditorControlAlive(LabEditorExpandBtn)
        try LabEditorExpandBtn.Text := LabEditorExpanded ? "Compact" : "Expand"

    details := [LabEditorInfoPanel, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList,
        LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn,
        LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus]
    for ctrl in details {
        if LabEditorControlAlive(ctrl)
            try ctrl.Visible := !LabEditorExpanded
    }

    try StrategyEditorWorkspaceApply(true)
    catch
        StrategyEditorRenderBackground()
}

StrategyEditorShowTower(placement) {
    global LabEditorDoc, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta
    if !IsObject(LabEditorDoc)
        return
    towerName := LabEditorDoc.TowerNameForSlot(placement.slot)
    if (towerName = "")
        towerName := "Slot " placement.slot

    if LabEditorControlAlive(LabEditorTowerPortrait) {
        portrait := LabTowerPortraitPath(towerName)
        try LabEditorTowerPortrait.Value := portrait
    }
    if LabEditorControlAlive(LabEditorTowerName)
        try LabEditorTowerName.Text := LabTowerPlacementDisplay(LabEditorDoc, placement)
    if LabEditorControlAlive(LabEditorTowerMeta) {
        footprint := LabTowerPlacementFootprint(towerName)
        try LabEditorTowerMeta.Text := LabTowerPlacementMeta(LabEditorDoc, placement)
            . "`nX " placement.x "  •  Y " placement.y
    }
}

StrategyEditorAssetsMissing() {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return false
    for tower in LabEditorDoc.RequiredTowers {
        if (LabTowerCachedPortraitPath(tower) = "")
            return true
    }
    return false
}

StrategyEditorMaybeAutoSyncAssets(*) {
    global LabEditorAssetsRequested, LabEditorDoc, LabEditorAssetBadge
    if LabEditorAssetsRequested || !IsObject(LabEditorDoc)
        return
    if !StrategyEditorAssetsMissing()
        return
    LabEditorAssetsRequested := true
    if LabEditorControlAlive(LabEditorAssetBadge)
        try LabEditorAssetBadge.Text := "Map exact • portraits queued"
    SetTimer(StrategyEditorSyncAssets, -180)
}

StrategyEditorSyncAssets(*) {
    global LabEditorSyncBtn, LabEditorAssetSyncPid, LabEditorDoc, LabEditorAssetBadge
    if !IsObject(LabEditorDoc)
        return
    if (LabEditorAssetSyncPid && ProcessExist(LabEditorAssetSyncPid))
        return

    script := A_ScriptDir "\submacros\lab_tower_assets.ps1"
    if !FileExist(script) {
        StrategyEditorSetStatus("Tower portrait sync helper is missing.", true)
        return
    }

    towerNames := ""
    for tower in LabEditorDoc.RequiredTowers {
        entry := LabTowerResolve(tower)
        towerNames .= (towerNames != "" ? "|" : "") entry.name
    }
    if (towerNames = "")
        return

    if LabEditorControlAlive(LabEditorSyncBtn) {
        try LabEditorSyncBtn.Enabled := false
        try LabEditorSyncBtn.Text := "Syncing..."
    }
    if LabEditorControlAlive(LabEditorAssetBadge)
        try LabEditorAssetBadge.Text := "Map exact • portraits syncing"
    StrategyEditorSetStatus("Caching small tower portraits for this strategy. Map imagery stays local.")

    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' script
        . '" -InstallDir "' A_ScriptDir '" -TowerNames "' StrReplace(towerNames, '"', '') '"'
    try {
        Run(cmd, , "Hide", &LabEditorAssetSyncPid)
        SetTimer(StrategyEditorAssetSyncPoll, 500)
    } catch Error as err {
        LabEditorAssetSyncPid := 0
        if LabEditorControlAlive(LabEditorSyncBtn) {
            try LabEditorSyncBtn.Enabled := true
            try LabEditorSyncBtn.Text := "Sync Portraits"
        }
        if LabEditorControlAlive(LabEditorAssetBadge)
            try LabEditorAssetBadge.Text := "Map source: exact screenshot"
        StrategyEditorSetStatus("Tower portrait sync could not start: " err.Message, true)
    }
}

StrategyEditorAssetSyncPoll(*) {
    global LabEditorAssetSyncPid, LabEditorSyncBtn, LabEditorDoc, LabEditorSelectedRow, LabEditorAssetBadge
    global LabTowerResolvedPortraitCache
    if (LabEditorAssetSyncPid && ProcessExist(LabEditorAssetSyncPid))
        return
    SetTimer(StrategyEditorAssetSyncPoll, 0)
    LabEditorAssetSyncPid := 0

    if LabEditorControlAlive(LabEditorSyncBtn) {
        try LabEditorSyncBtn.Enabled := true
        try LabEditorSyncBtn.Text := "Sync Portraits"
    }

    towers := 0
    misses := 0
    errors := 0
    statusPath := A_AppData "\Ultimate_Macro\StrategyEditor\tower-asset-status.ini"
    if FileExist(statusPath) {
        try towers := Integer(IniRead(statusPath, "Sync", "Towers", 0))
        try misses := Integer(IniRead(statusPath, "Sync", "Misses", 0))
        try errors := Integer(IniRead(statusPath, "Sync", "Errors", 0))
    }

    ; Clear path memoization so freshly downloaded portraits are visible immediately.
    LabTowerResolvedPortraitCache := Map()
    if IsObject(LabEditorDoc) && LabEditorSelectedRow > 0
        StrategyEditorShowTower(LabEditorDoc.Placements[LabEditorSelectedRow])

    if LabEditorControlAlive(LabEditorAssetBadge) {
        mapName := StrategyEditorMapName()
        mapState := mapName != "" && LabMapCameraPath(mapName) != "" ? "Map exact" : "Map pending"
        try LabEditorAssetBadge.Text := mapState " • portraits " towers
    }

    StrategyEditorSetStatus("Portrait sync complete: " towers " cached, " misses " miss(es), " errors " error(s). Map imagery was not downloaded.", errors > 0)
}
