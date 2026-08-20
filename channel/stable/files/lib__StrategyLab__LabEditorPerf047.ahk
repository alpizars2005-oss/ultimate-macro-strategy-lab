#Requires AutoHotkey v2.0

; Strategy Lab 0.4.7b interaction hotfix.
;
; Goals:
;   - Layer selection is captured from the native ComboBox notification, not a polling timer.
;   - Drag uses a cached terrain + stationary-square bitmap and paints one moving square.
;   - Pan keeps all visible tower squares on screen, but skips marker text while moving.
;   - Lightweight in-memory profiling reports render ms/FPS only when interaction ends.
; No gameplay clicks, strategy coordinates, saves, or footprint rules are changed.

global Lab047LayerIndex := Map()
global Lab047LayerIndexToken := ""
global Lab047DragLastPaint := 0
global Lab047DragLastFieldUpdate := 0
global Lab047PanLastPaint := 0

global Lab047FastDragBitmap := 0
global Lab047FastDragKey := ""
global Lab047FastBrushes := Map()
global Lab047FastBorderBrush := 0
global Lab047FastSelectedBorderBrush := 0

global Lab047ProfileKind := ""
global Lab047ProfileFrames := 0
global Lab047ProfileTotalMs := 0
global Lab047ProfilePeakMs := 0
global Lab047ProfileStarted := 0

Lab047DocumentToken() {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return ""
    towers := ""
    for index, tower in LabEditorDoc.RequiredTowers
        towers .= (index = 1 ? "" : "|") tower
    return LabEditorDoc.Path "|" LabEditorDoc.Placements.Length "|" towers
}

Lab047EnsureLayerIndex(force := false) {
    global LabEditorDoc, Lab047LayerIndex, Lab047LayerIndexToken
    if !IsObject(LabEditorDoc) {
        Lab047LayerIndex := Map()
        Lab047LayerIndexToken := ""
        return false
    }

    token := Lab047DocumentToken()
    if !force && token = Lab047LayerIndexToken && Lab047LayerIndex.Has("all placements")
        return true

    indexMap := Map()
    indexMap["all placements"] := []
    for index, placement in LabEditorDoc.Placements {
        indexMap["all placements"].Push(index)
        slot := String(placement.slot)
        tower := LabEditorDoc.TowerNameForSlot(slot)
        label := "Slot " slot (tower != "" ? " - " tower : "")
        key := StrLower(label)
        if !indexMap.Has(key)
            indexMap[key] := []
        indexMap[key].Push(index)
    }

    Lab047LayerIndex := indexMap
    Lab047LayerIndexToken := token
    return true
}

Lab047VisibleIndices() {
    global LabEditorLayer, Lab047LayerIndex
    if !Lab047EnsureLayerIndex()
        return []
    key := StrLower(Trim(LabEditorLayer))
    return Lab047LayerIndex.Has(key) ? Lab047LayerIndex[key] : Lab047LayerIndex["all placements"]
}

Lab047ArrayContains(values, needle) {
    for value in values {
        if (value = needle)
            return true
    }
    return false
}

Lab047RefreshLayerList(indices, selectedDocIndex := 0) {
    global LabEditorDoc, LabEditorList, LabEditorListRowMap
    if !IsObject(LabEditorDoc) || !LabEditorControlAlive(LabEditorList)
        return 0

    try LabEditorList.Delete()
    LabEditorListRowMap := []
    selectedVisibleRow := 0

    for docIndex in indices {
        if (docIndex < 1 || docIndex > LabEditorDoc.Placements.Length)
            continue
        placement := LabEditorDoc.Placements[docIndex]
        LabEditorList.Add(, docIndex, LabTowerPlacementDisplay(LabEditorDoc, placement), placement.x, placement.y)
        LabEditorListRowMap.Push(docIndex)
        if (docIndex = selectedDocIndex)
            selectedVisibleRow := LabEditorListRowMap.Length
    }

    if (selectedVisibleRow > 0)
        try LabEditorList.Modify(selectedVisibleRow, "Vis Select Focus")
    return selectedVisibleRow
}

Lab047ApplyLayerChoice(choice) {
    global LabEditorLayer, LabEditorLayerOptions, LabEditorLayerChangeBusy
    global LabEditorDoc, LabEditorSelectedRow, LabEditorXCtrl, LabEditorYCtrl

    if LabEditorLayerChangeBusy || !IsObject(LabEditorDoc)
        return
    if (choice < 1 || choice > LabEditorLayerOptions.Length)
        return

    wanted := LabEditorLayerOptions[choice]
    if (wanted = "")
        return

    LabEditorLayer := wanted
    Lab047EnsureLayerIndex(true)
    indices := Lab047VisibleIndices()

    if !Lab047ArrayContains(indices, LabEditorSelectedRow)
        LabEditorSelectedRow := indices.Length > 0 ? indices[1] : 0

    Lab047RefreshLayerList(indices, LabEditorSelectedRow)

    if (LabEditorSelectedRow > 0 && LabEditorSelectedRow <= LabEditorDoc.Placements.Length) {
        placement := LabEditorDoc.Placements[LabEditorSelectedRow]
        if LabEditorControlAlive(LabEditorXCtrl)
            try LabEditorXCtrl.Text := placement.x
        if LabEditorControlAlive(LabEditorYCtrl)
            try LabEditorYCtrl.Text := placement.y
        StrategyEditorShowTower(placement)
    }

    Lab047ReleaseFastDragBase()
    StrategyEditorReleaseFastBase()
    StrategyEditorRenderBackground()
    StrategyEditorSetStatus("Layer: " LabEditorLayer " • " indices.Length " placement"
        (indices.Length = 1 ? "" : "s") ".")
}

Lab047Command(wParam, lParam, msg, hwnd) {
    global LabEditorLayerCtrl, LabEditorLayerOptions, LabEditorLayerChangeBusy
    if LabEditorLayerChangeBusy || !LabEditorControlAlive(LabEditorLayerCtrl)
        return

    ctrlHwnd := 0
    try ctrlHwnd := LabEditorLayerCtrl.Hwnd
    if !ctrlHwnd || lParam != ctrlHwnd
        return

    ; WM_COMMAND / CBN_SELCHANGE. Read the native ComboBox selection directly so the
    ; result cannot be lost through a stale AHK DropDownList Text/Value snapshot.
    notify := (wParam >> 16) & 0xFFFF
    if (notify != 1)
        return

    selectedZero := -1
    try selectedZero := DllCall("user32\SendMessageW", "Ptr", ctrlHwnd, "UInt", 0x0147,
        "Ptr", 0, "Ptr", 0, "Ptr")
    choice := selectedZero + 1
    if (choice < 1 || choice > LabEditorLayerOptions.Length)
        return

    ; Defer one turn of the message loop so the native control finishes committing the
    ; selection before ListView/canvas work begins.
    SetTimer(Lab047ApplyLayerChoice.Bind(choice), -1)
}

Lab047GetSlotBrush(slot) {
    global Lab047FastBrushes
    key := String(slot)
    if Lab047FastBrushes.Has(key)
        return Lab047FastBrushes[key]
    brush := Gdip_BrushCreateSolid(StrategyEditorSlotColor(slot, 255))
    if brush
        Lab047FastBrushes[key] := brush
    return brush
}

Lab047EnsureBorderBrushes() {
    global Lab047FastBorderBrush, Lab047FastSelectedBorderBrush
    if !Lab047FastBorderBrush
        Lab047FastBorderBrush := Gdip_BrushCreateSolid(0xFF20252B)
    if !Lab047FastSelectedBorderBrush
        Lab047FastSelectedBorderBrush := Gdip_BrushCreateSolid(0xFFFFFFFF)
}

Lab047DrawFastMarker(graphics, placement, point, selected := false) {
    global Lab047FastBorderBrush, Lab047FastSelectedBorderBrush
    Lab047EnsureBorderBrushes()
    fillBrush := Lab047GetSlotBrush(placement.slot)
    borderBrush := selected ? Lab047FastSelectedBorderBrush : Lab047FastBorderBrush
    markerSize := selected ? 22 : 18
    half := markerSize / 2.0
    border := selected ? 2 : 1

    if borderBrush
        Gdip_FillRectangle(graphics, borderBrush, point.x - half, point.y - half, markerSize, markerSize)
    if fillBrush
        Gdip_FillRectangle(graphics, fillBrush, point.x - half + border, point.y - half + border,
            markerSize - (border * 2), markerSize - (border * 2))
}

Lab047SwapRenderedBitmap(pOut) {
    if !pOut
        return false
    hBitmap := 0
    try {
        hBitmap := StrategyEditorBitmapToHBITMAP(pOut)
    } finally {
        try Gdip_DisposeImage(pOut)
    }
    if !hBitmap
        return false
    if StrategyEditorSwapCanvasBitmap(hBitmap)
        return true
    try DllCall("gdi32\DeleteObject", "Ptr", hBitmap)
    return false
}

Lab047ReleaseFastDragBase(*) {
    global Lab047FastDragBitmap, Lab047FastDragKey
    if Lab047FastDragBitmap
        try Gdip_DisposeImage(Lab047FastDragBitmap)
    Lab047FastDragBitmap := 0
    Lab047FastDragKey := ""
}

Lab047BuildFastDragBase(dragIndex) {
    global Lab047FastDragBitmap, Lab047FastDragKey
    global LabEditorSourceImage, LabEditorCanvasW, LabEditorCanvasH

    if (LabEditorSourceImage = "" || !FileExist(LabEditorSourceImage))
        return 0

    key := "047|" StrategyEditorFastBaseCacheKey(dragIndex)
    if (Lab047FastDragBitmap && Lab047FastDragKey = key)
        return Lab047FastDragBitmap

    Lab047ReleaseFastDragBase()
    pSource := LabMapAcquireRenderBitmap(LabEditorSourceImage, &sourceW, &sourceH)
    if !pSource || sourceW <= 0 || sourceH <= 0
        return 0

    pBase := Gdip_CreateBitmap(LabEditorCanvasW, LabEditorCanvasH)
    if !pBase
        return 0
    g := Gdip_GraphicsFromImage(pBase)
    if !g {
        try Gdip_DisposeImage(pBase)
        return 0
    }

    success := false
    try {
        StrategyEditorDrawSource(g, pSource, sourceW, sourceH, true)
        for item in StrategyEditorCanvasPlacements() {
            if (item.index = dragIndex)
                continue
            Lab047DrawFastMarker(g, item.placement, item.point, false)
        }
        success := true
    } finally {
        try Gdip_DeleteGraphics(g)
        if !success
            try Gdip_DisposeImage(pBase)
    }
    if !success
        return 0

    Lab047FastDragBitmap := pBase
    Lab047FastDragKey := key
    return pBase
}

Lab047RenderDragFrame(dragIndex) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return false

    pBase := Lab047BuildFastDragBase(dragIndex)
    if !pBase
        return false
    pOut := StrategyEditorCopySmallBitmap(pBase)
    if !pOut
        return false

    g := Gdip_GraphicsFromImage(pOut)
    if !g {
        try Gdip_DisposeImage(pOut)
        return false
    }

    try {
        for item in StrategyEditorCanvasPlacements() {
            if (item.index != dragIndex)
                continue
            Lab047DrawFastMarker(g, item.placement, item.point, true)
            break
        }
    } finally {
        try Gdip_DeleteGraphics(g)
    }
    return Lab047SwapRenderedBitmap(pOut)
}

Lab047RenderPanFrame() {
    global LabEditorSourceImage, LabEditorCanvasW, LabEditorCanvasH
    if (LabEditorSourceImage = "" || !FileExist(LabEditorSourceImage))
        return false

    pSource := LabMapAcquireRenderBitmap(LabEditorSourceImage, &sourceW, &sourceH)
    if !pSource || sourceW <= 0 || sourceH <= 0
        return false

    pOut := Gdip_CreateBitmap(LabEditorCanvasW, LabEditorCanvasH)
    if !pOut
        return false
    g := Gdip_GraphicsFromImage(pOut)
    if !g {
        try Gdip_DisposeImage(pOut)
        return false
    }

    success := false
    try {
        StrategyEditorDrawSource(g, pSource, sourceW, sourceH, true)
        for item in StrategyEditorCanvasPlacements()
            Lab047DrawFastMarker(g, item.placement, item.point, false)
        success := true
    } finally {
        try Gdip_DeleteGraphics(g)
        if !success
            try Gdip_DisposeImage(pOut)
    }
    return success ? Lab047SwapRenderedBitmap(pOut) : false
}

Lab047ProfileReset(kind) {
    global Lab047ProfileKind, Lab047ProfileFrames, Lab047ProfileTotalMs
    global Lab047ProfilePeakMs, Lab047ProfileStarted
    Lab047ProfileKind := kind
    Lab047ProfileFrames := 0
    Lab047ProfileTotalMs := 0
    Lab047ProfilePeakMs := 0
    Lab047ProfileStarted := A_TickCount
}

Lab047ProfileAdd(elapsedMs) {
    global Lab047ProfileFrames, Lab047ProfileTotalMs, Lab047ProfilePeakMs
    Lab047ProfileFrames += 1
    Lab047ProfileTotalMs += elapsedMs
    Lab047ProfilePeakMs := Max(Lab047ProfilePeakMs, elapsedMs)
}

Lab047ProfileAppend(kind) {
    global Lab047ProfileKind, Lab047ProfileFrames, Lab047ProfileTotalMs
    global Lab047ProfilePeakMs, Lab047ProfileStarted, LabEditorStatus

    if (Lab047ProfileKind != kind || Lab047ProfileFrames < 1)
        return
    elapsed := Max(1, A_TickCount - Lab047ProfileStarted)
    avg := Round(Lab047ProfileTotalMs / Lab047ProfileFrames, 1)
    fps := Round((Lab047ProfileFrames * 1000.0) / elapsed, 1)
    suffix := "Perf " kind ": " avg " ms avg • " Lab047ProfilePeakMs " ms peak • ~" fps " FPS"

    if LabEditorControlAlive(LabEditorStatus) {
        current := ""
        try current := Trim(LabEditorStatus.Text)
        try LabEditorStatus.Text := (current != "" ? current "  |  " : "") suffix
    }
    Lab047ProfileKind := ""
}

Lab047ReleaseResources(*) {
    global Lab047FastBrushes, Lab047FastBorderBrush, Lab047FastSelectedBorderBrush
    Lab047ReleaseFastDragBase()
    for key, brush in Lab047FastBrushes {
        if brush
            try Gdip_DeleteBrush(brush)
    }
    Lab047FastBrushes := Map()
    if Lab047FastBorderBrush
        try Gdip_DeleteBrush(Lab047FastBorderBrush)
    if Lab047FastSelectedBorderBrush
        try Gdip_DeleteBrush(Lab047FastSelectedBorderBrush)
    Lab047FastBorderBrush := 0
    Lab047FastSelectedBorderBrush := 0
}

Lab047CanvasMouseDown(wParam, lParam, msg, hwnd) {
    global LabEditorDragPlacement, LabEditorPanActive
    global Lab047DragLastPaint, Lab047DragLastFieldUpdate, Lab047PanLastPaint

    Lab047ReleaseFastDragBase()
    StrategyEditorReleaseFastBase()
    Lab047DragLastPaint := 0
    Lab047DragLastFieldUpdate := 0
    Lab047PanLastPaint := 0

    result := Lab044CanvasMouseDown(wParam, lParam, msg, hwnd)
    if IsObject(LabEditorDragPlacement)
        Lab047ProfileReset("Drag")
    else if LabEditorPanActive
        Lab047ProfileReset("Pan")
    return result
}

Lab047CanvasMouseMove(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragIndex
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragPreviewX, LabEditorDragPreviewY, LabEditorXCtrl, LabEditorYCtrl
    global LabEditorPanActive, LabEditorViewport
    global LabEditorPanStartX, LabEditorPanStartY, LabEditorPanStartCenterX, LabEditorPanStartCenterY
    global LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global Lab047DragLastPaint, Lab047DragLastFieldUpdate, Lab047PanLastPaint

    if Lab044StrategyRunning() {
        Lab044ReleasePointerCapture(true)
        Lab047ReleaseFastDragBase()
        return
    }

    drag := LabEditorDragPlacement
    dragIndex := LabEditorDragIndex
    if IsObject(drag) && dragIndex > 0 && IsObject(LabEditorDoc) {
        StrategyEditorGetClientCursor(&mx, &my)
        mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
        my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
        logical := StrategyEditorViewportToStrategy(mx, my)
        if (logical.x = LabEditorDragPreviewX && logical.y = LabEditorDragPreviewY)
            return 0

        LabEditorDragPreviewX := logical.x
        LabEditorDragPreviewY := logical.y
        now := A_TickCount

        if (!Lab047DragLastFieldUpdate || now - Lab047DragLastFieldUpdate >= 100) {
            Lab047DragLastFieldUpdate := now
            if LabEditorControlAlive(LabEditorXCtrl)
                try LabEditorXCtrl.Text := logical.x
            if LabEditorControlAlive(LabEditorYCtrl)
                try LabEditorYCtrl.Text := logical.y
        }

        ; The cached interaction base contains no marker text. Target ~40 fps but let
        ; actual render time naturally determine the achievable cadence.
        if (!Lab047DragLastPaint || now - Lab047DragLastPaint >= 25) {
            Lab047DragLastPaint := now
            started := A_TickCount
            if Lab047RenderDragFrame(dragIndex)
                Lab047ProfileAdd(Max(0, A_TickCount - started))
        }
        return 0
    }

    if !LabEditorPanActive
        return
    if !StrategyEditorIsActive() {
        Lab044ReleasePointerCapture(false)
        return 0
    }

    StrategyEditorGetClientCursor(&mx, &my)
    if (LabEditorPanLastMouseX != "" && mx = LabEditorPanLastMouseX && my = LabEditorPanLastMouseY)
        return 0
    LabEditorPanLastMouseX := mx
    LabEditorPanLastMouseY := my

    visibleW := 1.0 / LabEditorViewport.Zoom
    visibleH := 1.0 / LabEditorViewport.Zoom
    dx := mx - LabEditorPanStartX
    dy := my - LabEditorPanStartY
    LabEditorViewport.CenterX := LabEditorPanStartCenterX - (dx / Max(1, LabEditorCanvasW)) * visibleW
    LabEditorViewport.CenterY := LabEditorPanStartCenterY - (dy / Max(1, LabEditorCanvasH)) * visibleH
    LabEditorViewport.ClampCenter()

    ; Keep tower squares visible while panning. Text is deliberately omitted until
    ; mouse-up, which is much cheaper than a full-quality composite on every move.
    now := A_TickCount
    if (!Lab047PanLastPaint || now - Lab047PanLastPaint >= 33) {
        Lab047PanLastPaint := now
        started := A_TickCount
        if Lab047RenderPanFrame()
            Lab047ProfileAdd(Max(0, A_TickCount - started))
    }
    return 0
}

Lab047CanvasMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorDragPlacement, LabEditorPanActive
    kind := IsObject(LabEditorDragPlacement) ? "Drag" : (LabEditorPanActive ? "Pan" : "")
    result := Lab044CanvasMouseUp(wParam, lParam, msg, hwnd)
    Lab047ReleaseFastDragBase()
    StrategyEditorReleaseFastBase()
    if (kind != "")
        Lab047ProfileAppend(kind)
    return result
}

Lab047CanvasWheel(wParam, lParam, msg, hwnd) {
    Lab047ReleaseFastDragBase()
    StrategyEditorReleaseFastBase()
    return Lab044CanvasWheel(wParam, lParam, msg, hwnd)
}

; Native ComboBox ownership: no polling timer and no extra GUI wakeups.
OnMessage(0x0111, Lab047Command)
OnExit(Lab047ReleaseResources)

; Editor-only housekeeping does not need to wake the GUI thread 10+ times a second.
; The dedicated Lab044GameplayUiGuard intentionally stays at 120 ms for click safety.
try SetTimer(StrategyEditorWorkspaceMonitor, 220)
try SetTimer(StrategyEditorInteractiveStateGuard, 1200)
