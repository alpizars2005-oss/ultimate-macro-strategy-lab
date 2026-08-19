#Requires AutoHotkey v2.0

; Direct map interaction layer.
; Wheel zooms around the cursor. Dragging empty canvas pans the viewport.
; Dragging a placement continues to move that placement through the existing editor path.
;
; Important: this module intentionally does NOT depend on Main.ahk's CurrentTab
; variable. Some upstream builds assign tab state later in startup, so reading
; CurrentTab from a timer can throw before the Editor has ever been opened.

global LabEditorPanActive := false
global LabEditorPanStartX := 0
global LabEditorPanStartY := 0
global LabEditorPanStartCenterX := 0.5
global LabEditorPanStartCenterY := 0.5
global LabEditorPanLastRender := 0
global LabEditorPanLastMouseX := ""
global LabEditorPanLastMouseY := ""
global LabEditorDirectNavInstallAttempts := 0
global LabEditorWheelLastRender := 0

StrategyEditorIsActive() {
    global LabEditorCanvasBg, LabEditorSnapshot, LabEditorShuttingDown
    if LabEditorShuttingDown
        return false

    ; IsObject() alone is unsafe during updater/ExitApp teardown: AutoHotkey may still
    ; hold a Gui.Control object after Windows has destroyed its HWND. Fail closed.
    return LabEditorControlVisible(LabEditorCanvasBg) || LabEditorControlVisible(LabEditorSnapshot)
}

; Map frames and circular placement markers are sibling controls on MainGui. Freezing
; only the map Picture allowed those siblings to repaint while the map itself was
; intentionally suspended, which exposed the black parent surface and produced torn
; frames. Freeze the whole Strategy Lab window for the tiny commit phase instead.
StrategyEditorRenderBackgroundBuffered(repositionMarkers := true) {
    global MainGui, LabEditorShuttingDown

    if LabEditorShuttingDown
        return false
    if !IsSet(MainGui) || !IsObject(MainGui)
        return StrategyEditorRenderBackground(repositionMarkers)

    hwnd := 0
    try hwnd := MainGui.Hwnd
    if !hwnd
        return StrategyEditorRenderBackground(repositionMarkers)

    result := false
    redrawSuspended := false
    try {
        DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0, "Ptr")
        redrawSuspended := true
        result := StrategyEditorRenderBackground(repositionMarkers)
    } finally {
        if redrawSuspended && DllCall("user32\IsWindow", "Ptr", hwnd, "Int") {
            try DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0, "Ptr")
            try DllCall("user32\RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x181)
        }
    }
    return result
}

StrategyEditorDirectMouseDown(wParam, lParam, msg, hwnd) {
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorPanActive, LabEditorPanStartX, LabEditorPanStartY
    global LabEditorPanStartCenterX, LabEditorPanStartCenterY, LabEditorPanLastRender
    global LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global LabEditorViewport, MainGui

    if !StrategyEditorIsActive()
        return

    ; Marker clicks belong to tower dragging, never map panning.
    if StrategyEditorTryBeginDrag(hwnd)
        return 0

    StrategyEditorGetClientCursor(&mx, &my)
    if (mx < LabEditorCanvasX || mx > LabEditorCanvasX + LabEditorCanvasW
        || my < LabEditorCanvasY || my > LabEditorCanvasY + LabEditorCanvasH)
        return

    LabEditorPanActive := true
    LabEditorPanStartX := mx
    LabEditorPanStartY := my
    LabEditorPanStartCenterX := LabEditorViewport.CenterX
    LabEditorPanStartCenterY := LabEditorViewport.CenterY
    LabEditorPanLastRender := 0
    LabEditorPanLastMouseX := mx
    LabEditorPanLastMouseY := my
    try DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return 0
}

StrategyEditorInteractiveMouseMove(wParam, lParam, msg, hwnd) {
    global LabEditorPanActive, LabEditorViewport
    global LabEditorPanStartX, LabEditorPanStartY, LabEditorPanStartCenterX, LabEditorPanStartCenterY
    global LabEditorPanLastRender, LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global LabEditorCanvasW, LabEditorCanvasH

    if !LabEditorPanActive
        return StrategyEditorMouseMove(wParam, lParam, msg, hwnd)

    if !StrategyEditorIsActive() {
        LabEditorPanActive := false
        try DllCall("ReleaseCapture")
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

    if (!LabEditorPanLastRender || A_TickCount - LabEditorPanLastRender >= 30) {
        LabEditorPanLastRender := A_TickCount
        StrategyEditorRenderBackgroundBuffered()
    }
    return 0
}

StrategyEditorInteractiveMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorPanActive, LabEditorPanLastMouseX, LabEditorPanLastMouseY
    if !LabEditorPanActive
        return StrategyEditorMouseUp(wParam, lParam, msg, hwnd)

    LabEditorPanActive := false
    LabEditorPanLastMouseX := ""
    LabEditorPanLastMouseY := ""
    try DllCall("ReleaseCapture")
    if StrategyEditorIsActive()
        StrategyEditorRenderBackgroundBuffered()
    return 0
}

StrategyEditorInteractiveWheel(wParam, lParam, msg, hwnd) {
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorViewport, LabEditorWheelLastRender

    if !StrategyEditorIsActive()
        return
    StrategyEditorGetClientCursor(&mx, &my)
    if (mx < LabEditorCanvasX || mx > LabEditorCanvasX + LabEditorCanvasW
        || my < LabEditorCanvasY || my > LabEditorCanvasY + LabEditorCanvasH)
        return

    delta := (wParam >> 16) & 0xFFFF
    if (delta > 32767)
        delta -= 65536
    if (delta = 0)
        return 0

    oldZoom := LabEditorViewport.Zoom
    zoomDelta := (delta / 120.0) * 0.15
    newZoom := Max(1.0, Min(4.0, oldZoom + zoomDelta))
    if (Abs(newZoom - oldZoom) < 0.001)
        return 0

    fx := (mx - LabEditorCanvasX) / Max(1, LabEditorCanvasW)
    fy := (my - LabEditorCanvasY) / Max(1, LabEditorCanvasH)
    oldVisibleW := 1.0 / oldZoom
    oldVisibleH := 1.0 / oldZoom
    oldLeft := LabEditorViewport.CenterX - oldVisibleW / 2
    oldTop := LabEditorViewport.CenterY - oldVisibleH / 2
    anchorX := oldLeft + fx * oldVisibleW
    anchorY := oldTop + fy * oldVisibleH

    LabEditorViewport.Zoom := newZoom
    newVisibleW := 1.0 / newZoom
    newVisibleH := 1.0 / newZoom
    LabEditorViewport.CenterX := anchorX - fx * newVisibleW + newVisibleW / 2
    LabEditorViewport.CenterY := anchorY - fy * newVisibleH + newVisibleH / 2
    LabEditorViewport.ClampCenter()

    now := A_TickCount
    if (!LabEditorWheelLastRender || now - LabEditorWheelLastRender >= 24) {
        LabEditorWheelLastRender := now
        StrategyEditorRenderBackgroundBuffered()
    } else {
        SetTimer(StrategyEditorWheelFlush, -24)
    }
    return 0
}

StrategyEditorWheelFlush(*) {
    global LabEditorWheelLastRender
    if !StrategyEditorIsActive()
        return
    LabEditorWheelLastRender := A_TickCount
    StrategyEditorRenderBackgroundBuffered()
}

StrategyEditorInstallDirectNavigation(*) {
    global LabEditorDirectNavInstallAttempts
    global LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn, LabEditorSyncBtn
    global LabEditorShuttingDown

    if LabEditorShuttingDown
        return
    LabEditorDirectNavInstallAttempts += 1
    if !LabEditorControlAlive(LabEditorPanLeftBtn) {
        if (LabEditorDirectNavInstallAttempts < 20)
            SetTimer(StrategyEditorInstallDirectNavigation, -250)
        return
    }

    StrategyEditorHideLegacyPanButtons()
    if LabEditorControlAlive(LabEditorSyncBtn)
        try LabEditorSyncBtn.Move(228, 174, 86, 24)
}

StrategyEditorHideLegacyPanButtons() {
    global LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn
    if !LabEditorControlAlive(LabEditorPanLeftBtn)
        return
    for ctrl in [LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn] {
        if !LabEditorControlAlive(ctrl)
            continue
        try ctrl.Enabled := false
        try ctrl.Visible := false
        try ctrl.Move(-1000, -1000, 1, 1)
    }
}

StrategyEditorInteractiveStateGuard(*) {
    global LabEditorDoc, LabEditorSelectedRow, LabEditorDirty, LabEditorShuttingDown
    if LabEditorShuttingDown || !StrategyEditorIsActive()
        return

    StrategyEditorHideLegacyPanButtons()

    if !IsObject(LabEditorDoc)
        return

    if (LabEditorSelectedRow < 1 && LabEditorDoc.Placements.Length > 0)
        StrategyEditorSelectPlacement(1)

    dirtyText := ""
    if LabEditorControlAlive(LabEditorDirty)
        try dirtyText := LabEditorDirty.Text
    if (dirtyText = "No strategy loaded.")
        StrategyEditorRefreshDirty()
}

SetTimer(StrategyEditorInstallDirectNavigation, -250)
SetTimer(StrategyEditorInteractiveStateGuard, 400)
