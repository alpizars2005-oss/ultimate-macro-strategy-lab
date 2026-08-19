#Requires AutoHotkey v2.0

; Strategy Lab 0.4.6 single-canvas renderer.
;
; Coordinate truth:
;   - background = exact Roblox CLIENT screenshot (no title bar)
;   - bottom hotbar is excluded from the editable viewport
;   - placement centers keep Ultimate Macro's strategy coordinates
;   - optional post-run calibration adds only a small map offset + px/unit correction
;
; Performance truth:
;   - idle: one full composite
;   - pan: background only until mouse-up
;   - drag: cached 438x238 static base + ONE moving footprint
; No per-placement HWNDs and no JPEG encode/decode on the mouse hot path.

global LabEditorFastBaseBitmap := 0
global LabEditorFastBaseKey := ""

StrategyEditorReleaseFastBase(*) {
    global LabEditorFastBaseBitmap, LabEditorFastBaseKey
    if LabEditorFastBaseBitmap
        try Gdip_DisposeImage(LabEditorFastBaseBitmap)
    LabEditorFastBaseBitmap := 0
    LabEditorFastBaseKey := ""
}
OnExit(StrategyEditorReleaseFastBase)

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
                "Ptr", 0, "Ptr", 0, "Ptr")
    }
    if old {
        try DllCall("gdi32\DeleteObject", "Ptr", old)
    } else {
        try DllCall("gdi32\DeleteObject", "Ptr", current)
    }
}
OnExit(StrategyEditorReleaseCanvasBitmap)

StrategyEditorLoadSnapshot(*) {
    path := FileSelect(1, , "Choose Roblox/TDS screenshot", "Images (*.png; *.jpg; *.jpeg; *.bmp)")
    if (path = "")
        return
    StrategyEditorSetBackground(path, "snapshot")
    StrategyEditorSetStatus("Screenshot loaded. Placement boundaries use the playable area above the hotbar.")
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

        if !LabMapGetRobloxClientRect(&pX, &pY, &w, &h)
            throw Error("Could not read the Roblox client screen rectangle.")

        pBitmap := Gdip_BitmapFromScreen(pX "|" pY "|" w "|" h)
        if !pBitmap
            throw Error("Could not capture the Roblox client.")

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
        try LabEditorAssetBadge.Text := "Map exact • client aligned"
    StrategyEditorSetStatus("Captured the exact Roblox client. Hotbar pixels are excluded from editing.")
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
        return "Exact Roblox client screenshot; hotbar excluded."
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
    StrategyEditorReleaseFastBase()
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
        if LabEditorControlAlive(LabEditorAssetBadge) {
            state := LabMapCameraNeedsRefresh(mapName) ? "legacy • refresh next run" : "client aligned"
            calibration := LabMapCalibration(mapName)
            suffix := calibration.samples > 0 ? " • calibrated " calibration.samples : ""
            try LabEditorAssetBadge.Text := "Map exact • " state suffix
        }
    } else {
        StrategyEditorClearBackground()
        if LabEditorControlAlive(LabEditorAssetBadge)
            try LabEditorAssetBadge.Text := "Map source: capture pending"
    }

    SetTimer(StrategyEditorMaybeAutoSyncAssets, -120)
}

StrategyEditorSetBackground(path, mode := "snapshot") {
    global LabEditorSourceImage, LabEditorBackgroundMode, LabEditorViewport
    if (path = "" || !FileExist(path))
        return false
    LabEditorSourceImage := path
    LabEditorBackgroundMode := mode
    LabEditorViewport.Reset()
    StrategyEditorReleaseFastBase()
    StrategyEditorRenderBackground()
    return true
}

StrategyEditorPreviewPlacement(index, placement) {
    return LabFootprintLogicalPoint(index, placement)
}

StrategyEditorAlignedLogicalPoint(index, placement) {
    global LabEditorDoc
    raw := StrategyEditorPreviewPlacement(index, placement)
    mapName := StrategyEditorMapName()
    return mapName != "" ? LabMapApplyCalibrationPoint(mapName, raw.x, raw.y) : raw
}

StrategyEditorCanvasPlacements() {
    global LabEditorDoc, LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    result := []
    if !IsObject(LabEditorDoc)
        return result

    playableH := LabMapPlayableStrategyHeight(LabEditorDoc.StrategyHeight)
    for index, placement in LabEditorDoc.Placements {
        if !StrategyEditorPlacementVisible(placement)
            continue
        raw := StrategyEditorPreviewPlacement(index, placement)
        if (raw.y > playableH)
            continue
        logical := StrategyEditorAlignedLogicalPoint(index, placement)
        point := LabEditorViewport.StrategyToViewport(
            logical.x, logical.y,
            LabEditorDoc.StrategyWidth, playableH,
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
        ; Cyan deliberately mirrors TDS' placed-tower boundary. Red means the reserved
        ; placement spaces intersect according to the same logical footprint model.
        ringColor := colliding ? (selected ? 0xFFFF5A5A : 0xEAFF4545)
            : (selected ? 0xFF48E8FF : 0xDC20CFF2)
        fillColor := colliding ? 0x28FF3131 : (selected ? 0x2415D9F4 : 0x1015D9F4)
        pen := 0
        brush := 0
        try {
            brush := Gdip_BrushCreateSolid(fillColor)
            if brush
                Gdip_FillEllipse(graphics, brush, point.x - halfW, point.y - halfH, footprintW, footprintH)
            pen := Gdip_CreatePen(ringColor, selected ? 1.8 : 1.15)
            if pen
                Gdip_DrawEllipse(graphics, pen, point.x - halfW, point.y - halfH, footprintW, footprintH)
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

    if !fast {
        label := StrategyEditorMarkerLabel(placement)
        labelW := Max(16, StrLen(label) * 7)
        options := "x" (point.x + LabFootprintLabelOffset(selected)) " y" (point.y - 8)
            . " w" labelW " h16 vCenter cFFFFFFFF s7 " (selected ? "Bold" : "")
        try Gdip_TextToGraphics(graphics, label, options, "Segoe UI")
    }
}

StrategyEditorDrawSource(graphics, pSource, sourceW, sourceH, fast := false) {
    global LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    rect := LabEditorViewport.SourceRect(sourceW, sourceH, LabMapPlayableRatio())
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", fast ? 5 : 7)
    try DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", fast ? 3 : 4)
    Gdip_DrawImage(graphics, pSource, 0, 0, LabEditorCanvasW, LabEditorCanvasH,
        rect.x, rect.y, rect.w, rect.h)
}

StrategyEditorFastBaseCacheKey(dragIndex) {
    global LabEditorSourceImage, LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorLayer, LabEditorRingMode, LabEditorDoc
    stamp := "", size := 0
    try stamp := FileGetTime(LabEditorSourceImage, "M")
    try size := FileGetSize(LabEditorSourceImage)
    mapName := StrategyEditorMapName()
    c := mapName != "" ? LabMapCalibration(mapName) : {pixelsPerUnit: 26, offsetX: 0, offsetY: 0}
    return LabEditorSourceImage "|" stamp "|" size "|" dragIndex "|" LabEditorLayer "|" LabEditorRingMode
        . "|" Round(LabEditorViewport.Zoom, 3) "|" Round(LabEditorViewport.CenterX, 4) "|" Round(LabEditorViewport.CenterY, 4)
        . "|" LabEditorCanvasW "x" LabEditorCanvasH "|" c.pixelsPerUnit "|" c.offsetX "|" c.offsetY
}

StrategyEditorBuildFastDragBase(pSource, sourceW, sourceH, dragIndex) {
    global LabEditorFastBaseBitmap, LabEditorFastBaseKey, LabEditorCanvasW, LabEditorCanvasH
    key := StrategyEditorFastBaseCacheKey(dragIndex)
    if (LabEditorFastBaseBitmap && LabEditorFastBaseKey = key)
        return LabEditorFastBaseBitmap

    StrategyEditorReleaseFastBase()
    pBase := Gdip_CreateBitmap(LabEditorCanvasW, LabEditorCanvasH)
    if !pBase
        return 0
    graphics := Gdip_GraphicsFromImage(pBase)
    if !graphics {
        try Gdip_DisposeImage(pBase)
        return 0
    }
    try {
        StrategyEditorDrawSource(graphics, pSource, sourceW, sourceH, true)
        items := StrategyEditorCanvasPlacements()
        ; No O(n^2) collision map and no text on the cached interaction base.
        empty := Map()
        for item in items {
            if (item.index = dragIndex)
                continue
            StrategyEditorDrawPlacement(graphics, item.index, item.placement, item.point, empty, true)
        }
    } finally {
        try Gdip_DeleteGraphics(graphics)
    }
    LabEditorFastBaseBitmap := pBase
    LabEditorFastBaseKey := key
    return pBase
}

StrategyEditorCopySmallBitmap(pBitmap) {
    global LabEditorCanvasW, LabEditorCanvasH
    pOut := Gdip_CreateBitmap(LabEditorCanvasW, LabEditorCanvasH)
    if !pOut
        return 0
    g := Gdip_GraphicsFromImage(pOut)
    if !g {
        try Gdip_DisposeImage(pOut)
        return 0
    }
    try {
        Gdip_DrawImage(g, pBitmap, 0, 0, LabEditorCanvasW, LabEditorCanvasH, 0, 0, LabEditorCanvasW, LabEditorCanvasH)
    } finally {
        try Gdip_DeleteGraphics(g)
    }
    return pOut
}

StrategyEditorBuildCompositeBitmap() {
    global LabEditorSourceImage, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorPanActive, LabEditorDragPlacement, LabEditorDragIndex, LabEditorDoc

    pSource := LabMapAcquireRenderBitmap(LabEditorSourceImage, &sourceW, &sourceH)
    if !pSource || sourceW <= 0 || sourceH <= 0
        return 0

    ; Panning needs only the terrain. Footprints return on the guaranteed final mouse-up
    ; repaint, which turns dozens of ellipse/text operations into one DrawImage call.
    if LabEditorPanActive {
        pPan := Gdip_CreateBitmap(LabEditorCanvasW, LabEditorCanvasH)
        if !pPan
            return 0
        gPan := Gdip_GraphicsFromImage(pPan)
        if !gPan {
            try Gdip_DisposeImage(pPan)
            return 0
        }
        try {
            StrategyEditorDrawSource(gPan, pSource, sourceW, sourceH, true)
        } finally {
            try Gdip_DeleteGraphics(gPan)
        }
        return pPan
    }

    drag := LabEditorDragPlacement
    dragIndex := LabEditorDragIndex
    if IsObject(drag) && dragIndex > 0 && IsObject(LabEditorDoc) {
        pBase := StrategyEditorBuildFastDragBase(pSource, sourceW, sourceH, dragIndex)
        if !pBase
            return 0
        pOut := StrategyEditorCopySmallBitmap(pBase)
        if !pOut
            return 0
        g := Gdip_GraphicsFromImage(pOut)
        if !g {
            try Gdip_DisposeImage(pOut)
            return 0
        }
        try {
            for item in StrategyEditorCanvasPlacements() {
                if (item.index != dragIndex)
                    continue
                collision := Map()
                if LabFootprintPlacementCollides(dragIndex, LabEditorDoc)
                    collision[dragIndex] := true
                StrategyEditorDrawPlacement(g, dragIndex, item.placement, item.point, collision, true)
                break
            }
        } finally {
            try Gdip_DeleteGraphics(g)
        }
        return pOut
    }

    StrategyEditorReleaseFastBase()
    pOut := Gdip_CreateBitmap(LabEditorCanvasW, LabEditorCanvasH)
    if !pOut
        return 0
    graphics := Gdip_GraphicsFromImage(pOut)
    if !graphics {
        try Gdip_DisposeImage(pOut)
        return 0
    }
    success := false
    try {
        StrategyEditorDrawSource(graphics, pSource, sourceW, sourceH, false)
        items := StrategyEditorCanvasPlacements()
        StrategyEditorRebuildHitRegions(items)
        collisions := IsObject(LabEditorDoc) ? LabFootprintCollisionMap(LabEditorDoc) : Map()
        for item in items
            StrategyEditorDrawPlacement(graphics, item.index, item.placement, item.point, collisions, false)
        success := true
        return pOut
    } finally {
        try Gdip_DeleteGraphics(graphics)
        if !success && pOut
            try Gdip_DisposeImage(pOut)
    }
}

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
        "Ptr", 0, "Ptr", hBitmap, "Ptr")
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
        StrategyEditorReleaseFastBase()
        StrategyEditorReleaseCanvasBitmap()
        try LabEditorSnapshot.Visible := false
        try LabEditorCanvasBg.Visible := true
        if LabEditorControlAlive(LabEditorCanvasHint) {
            try LabEditorCanvasHint.Text := "No exact client screenshot for this map yet.`nRun the strategy once or press Capture Map."
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
        try {
            hBitmap := StrategyEditorBitmapToHBITMAP(pOut)
        } finally {
            try Gdip_DisposeImage(pOut)
        }

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
    mapName := StrategyEditorMapName()
    logical := mapName != "" ? LabMapApplyCalibrationPoint(mapName, placement.x, placement.y)
        : {x: placement.x, y: placement.y}
    playableH := LabMapPlayableStrategyHeight(LabEditorDoc.StrategyHeight)
    point := LabEditorViewport.StrategyToViewport(
        logical.x, logical.y, LabEditorDoc.StrategyWidth, playableH,
        LabEditorCanvasW, LabEditorCanvasH)
    point.x += LabEditorCanvasX
    point.y += LabEditorCanvasY
    return point
}

StrategyEditorViewportToStrategy(mx, my) {
    global LabEditorDoc, LabEditorViewport
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    playableH := LabMapPlayableStrategyHeight(LabEditorDoc.StrategyHeight)
    logical := LabEditorViewport.ViewportToStrategy(
        mx - LabEditorCanvasX, my - LabEditorCanvasY,
        LabEditorDoc.StrategyWidth, playableH,
        LabEditorCanvasW, LabEditorCanvasH)
    mapName := StrategyEditorMapName()
    raw := mapName != "" ? LabMapRemoveCalibrationPoint(mapName, logical.x, logical.y) : logical
    return {
        x: Round(Max(0, Min(Number(LabEditorDoc.StrategyWidth), raw.x))),
        y: Round(Max(0, Min(playableH, raw.y)))
    }
}

StrategyEditorZoom(delta) {
    global LabEditorViewport
    StrategyEditorReleaseFastBase()
    LabEditorViewport.ZoomBy(delta)
    StrategyEditorRenderBackground()
}

StrategyEditorZoomReset(*) {
    global LabEditorViewport
    StrategyEditorReleaseFastBase()
    LabEditorViewport.Reset()
    StrategyEditorRenderBackground()
}

StrategyEditorPan(dx, dy) {
    global LabEditorViewport
    if (LabEditorViewport.Zoom <= 1)
        return
    StrategyEditorReleaseFastBase()
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
        mapName := StrategyEditorMapName()
        c := mapName != "" ? LabMapCalibration(mapName) : {samples: 0, pixelsPerUnit: 26}
        calibrationText := c.samples > 0 ? " • calibrated " c.samples : ""
        try LabEditorTowerMeta.Text := LabTowerPlacementMeta(LabEditorDoc, placement)
            . calibrationText "`nX " placement.x "  •  Y " placement.y
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
    SetTimer(StrategyEditorSyncAssets, -120)
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
            try LabEditorAssetBadge.Text := "Map exact • portraits pending"
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
    towers := 0, misses := 0, errors := 0
    statusPath := A_AppData "\Ultimate_Macro\StrategyEditor\tower-asset-status.ini"
    if FileExist(statusPath) {
        try towers := Integer(IniRead(statusPath, "Sync", "Towers", 0))
        try misses := Integer(IniRead(statusPath, "Sync", "Misses", 0))
        try errors := Integer(IniRead(statusPath, "Sync", "Errors", 0))
    }
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
