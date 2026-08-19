#Requires AutoHotkey v2.0

; Strategy Lab 0.4 map/canvas renderer.
; The Editor uses only an exact Roblox/macro-camera screenshot (or a manually selected
; screenshot) as its map source. No wiki/top-down map or tower portrait is required.
; Placement radii + markers are composited into the SAME bitmap before Windows sees it.

StrategyEditorLoadSnapshot(*) {
    path := FileSelect(1, , "Choose Roblox/TDS screenshot", "Images (*.png; *.jpg; *.jpeg; *.bmp)")
    if (path = "")
        return
    StrategyEditorSetBackground(path, "snapshot")
    StrategyEditorSetStatus("Screenshot loaded. Placements are drawn directly into this canvas.")
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
    if IsObject(MainGui)
        try MainGui.Hide()
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
        if IsObject(MainGui)
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
    if LabEditorControlAlive(LabEditorAssetBadge)
        try LabEditorAssetBadge.Text := "Map source: exact screenshot"
    StrategyEditorSetStatus("Captured the exact Roblox view used by the macro" (mapName != "" ? " for " mapName : "") ".")
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
    return "Capture Roblox once on this map to create the editor canvas."
}

StrategyEditorClearBackground() {
    global LabEditorSourceImage, LabEditorBackgroundMode, LabEditorSnapshot, LabEditorViewport, LabEditorHitRegions
    LabEditorSourceImage := ""
    LabEditorBackgroundMode := "none"
    LabEditorHitRegions := []
    if LabEditorControlAlive(LabEditorSnapshot)
        try LabEditorSnapshot.Value := ""
    LabEditorViewport.Reset()
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

    ; Screenshot-only editor: never fall back to a wiki/top-down image.
    camera := LabMapCameraPath(mapName)
    if (camera != "") {
        StrategyEditorSetBackground(camera, "camera")
        if LabEditorControlAlive(LabEditorAssetBadge)
            try LabEditorAssetBadge.Text := "Map source: exact screenshot"
    } else {
        StrategyEditorClearBackground()
        if LabEditorControlAlive(LabEditorAssetBadge)
            try LabEditorAssetBadge.Text := "Map source: capture required"
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

StrategyEditorPreviewPlacement(index, placement) {
    global LabEditorDragIndex, LabEditorDragPreviewX, LabEditorDragPreviewY
    if (index = LabEditorDragIndex && LabEditorDragPreviewX != "" && LabEditorDragPreviewY != "")
        return {x: LabEditorDragPreviewX, y: LabEditorDragPreviewY}
    return {x: placement.x, y: placement.y}
}

StrategyEditorDrawPlacement(graphics, index, placement, point, fast := false) {
    global LabEditorSelectedRow, LabEditorHitRegions

    selected := index = LabEditorSelectedRow
    markerDiameter := StrategyEditorMarkerDiameter(index)
    markerRadius := markerDiameter / 2.0
    slotColor := StrategyEditorSlotColor(placement.slot, 255)

    if StrategyEditorRingModeAllows(index) {
        footprintDiameter := StrategyEditorFootprintDiameter(placement)
        footprintRadius := footprintDiameter / 2.0
        ringAlpha := selected ? 220 : 105
        fillAlpha := selected ? 34 : 14
        ringColor := StrategyEditorSlotColor(placement.slot, ringAlpha)
        fillColor := StrategyEditorSlotColor(placement.slot, fillAlpha)
        pen := 0
        brush := 0
        try {
            brush := Gdip_BrushCreateSolid(fillColor)
            if brush
                Gdip_FillEllipse(graphics, brush, point.x - footprintRadius, point.y - footprintRadius,
                    footprintDiameter, footprintDiameter)
            pen := Gdip_CreatePen(ringColor, selected ? 2.2 : 1.25)
            if pen
                Gdip_DrawEllipse(graphics, pen, point.x - footprintRadius, point.y - footprintRadius,
                    footprintDiameter, footprintDiameter)
        } finally {
            if pen
                try Gdip_DeletePen(pen)
            if brush
                try Gdip_DeleteBrush(brush)
        }
    }

    ; Small center badge. It is painted into the frame, not a child control.
    markerBrush := 0
    outlinePen := 0
    try {
        markerBrush := Gdip_BrushCreateSolid(slotColor)
        if markerBrush
            Gdip_FillEllipse(graphics, markerBrush, point.x - markerRadius, point.y - markerRadius,
                markerDiameter, markerDiameter)
        outlinePen := Gdip_CreatePen(selected ? 0xFFFFFFFF : 0xCCF4F7FA, selected ? 2.0 : 1.0)
        if outlinePen
            Gdip_DrawEllipse(graphics, outlinePen, point.x - markerRadius, point.y - markerRadius,
                markerDiameter, markerDiameter)
    } finally {
        if outlinePen
            try Gdip_DeletePen(outlinePen)
        if markerBrush
            try Gdip_DeleteBrush(markerBrush)
    }

    ; During continuous pan/drag, skipping most text keeps redraws smooth. The selected
    ; marker stays labelled; the final settled frame restores every number immediately.
    if (!fast || selected) {
        label := StrategyEditorMarkerLabel(placement)
        size := selected ? 8 : 7
        options := "x" (point.x - markerRadius) " y" (point.y - markerRadius - 1)
            . " w" markerDiameter " h" markerDiameter " Center vCenter cFFFFFFFF s" size " Bold"
        try Gdip_TextToGraphics(graphics, label, options, "Segoe UI")
    }

    LabEditorHitRegions.Push({
        index: index,
        x: point.x + LabEditorCanvasX,
        y: point.y + LabEditorCanvasY,
        radius: Max(12, markerRadius + 5)
    })
}

StrategyEditorRenderCompositeFrame(outputPath) {
    global LabEditorSourceImage, LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDoc, LabEditorHitRegions, LabEditorPanActive, LabEditorDragPlacement

    LabEditorHitRegions := []
    pSource := LabMapAcquireRenderBitmap(LabEditorSourceImage, &sourceW, &sourceH)
    if !pSource || sourceW <= 0 || sourceH <= 0
        return false

    pOut := 0
    graphics := 0
    try {
        rect := LabEditorViewport.SourceRect(sourceW, sourceH)
        pOut := Gdip_CreateBitmap(LabEditorCanvasW, LabEditorCanvasH)
        if !pOut
            return false
        graphics := Gdip_GraphicsFromImage(pOut)
        if !graphics
            return false

        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
        try DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
        Gdip_DrawImage(graphics, pSource, 0, 0, LabEditorCanvasW, LabEditorCanvasH,
            rect.x, rect.y, rect.w, rect.h)

        fast := false
        if IsSet(LabEditorPanActive)
            fast := !!LabEditorPanActive
        if IsObject(LabEditorDragPlacement)
            fast := true

        if IsObject(LabEditorDoc) {
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
                StrategyEditorDrawPlacement(graphics, index, placement, point, fast)
            }
        }

        Gdip_SaveBitmapToFile(pOut, outputPath, 90)
        return FileExist(outputPath) && FileGetSize(outputPath) > 500
    } finally {
        if graphics
            try Gdip_DeleteGraphics(graphics)
        if pOut
            try Gdip_DisposeImage(pOut)
    }
}

StrategyEditorRenderBackground(repositionMarkers := true) {
    global LabEditorSourceImage, LabEditorViewport, LabEditorViewportPath, LabEditorViewportAltPath, LabEditorViewportFrame
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorSnapshot, LabEditorCanvasBg, LabEditorCanvasHint, LabEditorZoomLabel, LabEditorHitRegions

    if !LabEditorControlAlive(LabEditorSnapshot) || !LabEditorControlAlive(LabEditorCanvasBg)
        return false

    if (LabEditorSourceImage = "" || !FileExist(LabEditorSourceImage)) {
        LabEditorHitRegions := []
        try LabEditorSnapshot.Visible := false
        try LabEditorCanvasBg.Visible := true
        if LabEditorControlAlive(LabEditorCanvasHint) {
            try LabEditorCanvasHint.Text := "No camera screenshot for this map yet.`nOpen Roblox on the map and press Capture Map."
            try LabEditorCanvasHint.Move(LabEditorCanvasX + 44, LabEditorCanvasY + Floor(LabEditorCanvasH / 2) - 26,
                Max(220, LabEditorCanvasW - 88), 52)
            try LabEditorCanvasHint.Visible := true
        }
        if LabEditorControlAlive(LabEditorZoomLabel)
            try LabEditorZoomLabel.Text := "100%"
        return false
    }

    dir := A_AppData "\Ultimate_Macro\StrategyEditor"
    if !DirExist(dir)
        DirCreate(dir)
    renderPath := Mod(LabEditorViewportFrame, 2) = 0 ? LabEditorViewportPath : LabEditorViewportAltPath
    LabEditorViewportFrame += 1

    if StrategyEditorRenderCompositeFrame(renderPath) {
        try LabEditorSnapshot.Value := renderPath
        try LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
        try LabEditorSnapshot.Visible := true
        try LabEditorCanvasBg.Visible := false
        if LabEditorControlAlive(LabEditorCanvasHint)
            try LabEditorCanvasHint.Visible := false
        if LabEditorControlAlive(LabEditorZoomLabel)
            try LabEditorZoomLabel.Text := Round(LabEditorViewport.Zoom * 100) "%"
        return true
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
    ; Legacy compatibility entry point. The 0.4 interaction module owns wheel routing.
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

    ; No website portrait. The selected-unit vanity badge uses the same label as the
    ; in-map marker, keeping the Editor entirely local/screenshot based.
    if LabEditorControlAlive(LabEditorTowerPortrait) {
        try LabEditorTowerPortrait.Text := StrategyEditorMarkerLabel(placement)
        try LabEditorTowerPortrait.SetFont("s17 w700 cFFFFFF", "Segoe UI")
        try StrategyEditorSetCircularRegion(LabEditorTowerPortrait, 62)
    }
    if LabEditorControlAlive(LabEditorTowerName)
        try LabEditorTowerName.Text := LabTowerPlacementDisplay(LabEditorDoc, placement)
    if LabEditorControlAlive(LabEditorTowerMeta)
        try LabEditorTowerMeta.Text := LabTowerPlacementMeta(LabEditorDoc, placement) "`nX " placement.x "  •  Y " placement.y
}

StrategyEditorAssetsMissing() {
    mapName := StrategyEditorMapName()
    return mapName != "" && LabMapCameraPath(mapName) = ""
}

StrategyEditorMaybeAutoSyncAssets() {
    global LabEditorAssetBadge
    mapName := StrategyEditorMapName()
    if !LabEditorControlAlive(LabEditorAssetBadge)
        return

    badgeText := mapName = ""
        ? "Map source: unknown"
        : (LabMapCameraPath(mapName) != "" ? "Map source: exact screenshot" : "Map source: capture required")
    try LabEditorAssetBadge.Text := badgeText
}

; Kept under the old name because the UI/workspace already references LabEditorSyncBtn.
; In 0.4 it never touches the network; it simply captures the exact Roblox camera.
StrategyEditorSyncAssets(*) {
    StrategyEditorCaptureRoblox()
}

StrategyEditorAssetSyncPoll(*) {
    ; No web asset worker exists in the 0.4 Editor.
}
