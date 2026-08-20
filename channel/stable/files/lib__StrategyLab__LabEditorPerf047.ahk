#Requires AutoHotkey v2.0

; Strategy Lab 0.4.7 layer + interaction performance hotfix.
;
; This file stays deliberately small: it reuses the 0.4.6 single-canvas renderer and
; its cached drag base, but fixes Layer event ownership and raises interaction cadence
; now that the expensive static canvas is already cached.

global Lab047LayerIndex := Map()
global Lab047LayerIndexToken := ""
global Lab047LayerHookHwnd := 0
global Lab047DragLastPaint := 0
global Lab047DragLastFieldUpdate := 0
global Lab047PanLastPaint := 0

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

Lab047LayerChanged(ctrl, info) {
    global LabEditorLayer, LabEditorLayerOptions, LabEditorLayerChangeBusy
    global LabEditorDoc, LabEditorSelectedRow, LabEditorXCtrl, LabEditorYCtrl

    if LabEditorLayerChangeBusy || !IsObject(LabEditorDoc)
        return

    choice := 0
    try choice := Integer(ctrl.Value)
    if (choice < 1 || choice > LabEditorLayerOptions.Length)
        return

    LabEditorLayer := LabEditorLayerOptions[choice]
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

    ; Layer is part of the renderer cache key, but release immediately so the next
    ; interaction cannot display even one stale frame.
    StrategyEditorReleaseFastBase()
    StrategyEditorRenderBackground()
    StrategyEditorSetStatus("Layer: " LabEditorLayer " • " indices.Length " placement"
        (indices.Length = 1 ? "" : "s") ".")
}

Lab047EnsureLayerHook(*) {
    global LabEditorLayerCtrl, Lab047LayerHookHwnd
    if !LabEditorControlAlive(LabEditorLayerCtrl)
        return

    hwnd := 0
    try hwnd := LabEditorLayerCtrl.Hwnd
    if !hwnd || Lab047LayerHookHwnd = hwnd
        return

    ; Remove the legacy callback and install one deterministic owner. This avoids the
    ; old silent ListView-scope failure and keeps ListView row mapping tied to doc indices.
    try LabEditorLayerCtrl.OnEvent("Change", StrategyEditorLayerChanged, 0)
    LabEditorLayerCtrl.OnEvent("Change", Lab047LayerChanged, 1)
    Lab047LayerHookHwnd := hwnd
    Lab047EnsureLayerIndex(true)
}

Lab047CanvasMouseDown(wParam, lParam, msg, hwnd) {
    global Lab047DragLastPaint, Lab047DragLastFieldUpdate, Lab047PanLastPaint
    StrategyEditorReleaseFastBase()
    Lab047DragLastPaint := 0
    Lab047DragLastFieldUpdate := 0
    Lab047PanLastPaint := 0
    return Lab044CanvasMouseDown(wParam, lParam, msg, hwnd)
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

        ; Native Edit controls update at 10 Hz; the pointer preview stays much faster.
        if (!Lab047DragLastFieldUpdate || now - Lab047DragLastFieldUpdate >= 100) {
            Lab047DragLastFieldUpdate := now
            if LabEditorControlAlive(LabEditorXCtrl)
                try LabEditorXCtrl.Text := logical.x
            if LabEditorControlAlive(LabEditorYCtrl)
                try LabEditorYCtrl.Text := logical.y
        }

        ; 0.4.6 already caches terrain + every stationary marker during a drag. The old
        ; 80 ms cap made that optimization feel sluggish; ~30 fps is a better target.
        if (!Lab047DragLastPaint || now - Lab047DragLastPaint >= 33) {
            Lab047DragLastPaint := now
            StrategyEditorRenderBackground(false)
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

    ; Pan renders terrain only in the existing compositor, so ~22 fps is inexpensive
    ; and noticeably smoother than the previous ~12 fps cap.
    now := A_TickCount
    if (!Lab047PanLastPaint || now - Lab047PanLastPaint >= 45) {
        Lab047PanLastPaint := now
        StrategyEditorRenderBackground(false)
    }
    return 0
}

Lab047CanvasMouseUp(wParam, lParam, msg, hwnd) {
    result := Lab044CanvasMouseUp(wParam, lParam, msg, hwnd)
    StrategyEditorReleaseFastBase()
    return result
}

Lab047CanvasWheel(wParam, lParam, msg, hwnd) {
    StrategyEditorReleaseFastBase()
    return Lab044CanvasWheel(wParam, lParam, msg, hwnd)
}

Lab047LayerHookPoll(*) {
    global Lab047LayerHookHwnd
    Lab047EnsureLayerHook()
    if Lab047LayerHookHwnd
        SetTimer(Lab047LayerHookPoll, 0)
}
SetTimer(Lab047LayerHookPoll, 250)

; Editor-only housekeeping does not need to wake the GUI thread 10+ times a second.
; The dedicated Lab044GameplayUiGuard intentionally stays at 120 ms for click safety.
try SetTimer(StrategyEditorWorkspaceMonitor, 180)
try SetTimer(StrategyEditorInteractiveStateGuard, 900)
