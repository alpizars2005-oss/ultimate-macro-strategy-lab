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
    global LabEditorCanvasBg, LabEditorSnapshot
    if !IsSet(LabEditorCanvasBg) || !IsObject(LabEditorCanvasBg)
        return false
    if LabEditorCanvasBg.Visible
        return true
    return IsSet(LabEditorSnapshot) && IsObject(LabEditorSnapshot) && LabEditorSnapshot.Visible
}

; Map frames, circular placement markers and footprint-ring Pictures are sibling
; controls on MainGui. Freezing only the map Picture allowed those siblings to repaint
; while the map itself was intentionally suspended, which exposed the black parent
; surface and produced the large torn/blank frames seen in live 0.2.15 testing.
;
; Freeze the whole Strategy Lab window for the tiny commit phase instead. The next
; viewport is fully generated first, every child is repositioned while painting is
; disabled, and Windows receives exactly one all-children redraw at the end. This is a
; real atomic presentation boundary rather than several independently repainting HWNDs.
StrategyEditorRenderBackgroundBuffered(repositionMarkers := true) {
    global MainGui

    if !IsSet(MainGui) || !IsObject(MainGui)
        return StrategyEditorRenderBackground(repositionMarkers)

    hwnd := 0
    try hwnd := MainGui.Hwnd
    if !hwnd
        return StrategyEditorRenderBackground(repositionMarkers)

    result := false
    redrawSuspended := false
    try {
        DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0, "Ptr") ; WM_SETREDRAW false
        redrawSuspended := true
        result := StrategyEditorRenderBackground(repositionMarkers)
    } finally {
        if redrawSuspended {
            try DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0, "Ptr") ; WM_SETREDRAW true
            ; RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW. One complete paint keeps
            ; the map, markers and placement rings on the exact same presented frame.
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
    DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return 0
}

StrategyEditorInteractiveMouseMove(wParam, lParam, msg, hwnd) {
    global LabEditorPanActive, LabEditorViewport
    global LabEditorPanStartX, LabEditorPanStartY, LabEditorPanStartCenterX, LabEditorPanStartCenterY
    global LabEditorPanLastRender, LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global LabEditorCanvasW, LabEditorCanvasH

    if !LabEditorPanActive
        return StrategyEditorMouseMove(wParam, lParam, msg, hwnd)

    StrategyEditorGetClientCursor(&mx, &my)
    if (LabEditorPanLastMouseX != "" && mx = LabEditorPanLastMouseX && my = LabEditorPanLastMouseY)
        return 0
    LabEditorPanLastMouseX := mx
    LabEditorPanLastMouseY := my

    visibleW := 1.0 / LabEditorViewport.Zoom
    visibleH := 1.0 / LabEditorViewport.Zoom
    dx := mx - LabEditorPanStartX
    dy := my - LabEditorPanStartY

    ; Dragging the picture right moves the visible world right, so the camera center moves left.
    LabEditorViewport.CenterX := LabEditorPanStartCenterX - (dx / Max(1, LabEditorCanvasW)) * visibleW
    LabEditorViewport.CenterY := LabEditorPanStartCenterY - (dy / Max(1, LabEditorCanvasH)) * visibleH
    LabEditorViewport.ClampCenter()

    ; A complete atomic workspace repaint is a little more expensive than updating one
    ; Picture HWND, so target ~33 FPS. In practice this feels smoother than presenting
    ; partially torn 42 FPS frames and leaves more time for GDI+ JPEG generation.
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
    ; Smaller proportional steps make mouse wheels and precision touchpads feel less jumpy.
    zoomDelta := (delta / 120.0) * 0.15
    newZoom := Max(1.0, Min(4.0, oldZoom + zoomDelta))
    if (Abs(newZoom - oldZoom) < 0.001)
        return 0

    ; Keep the point under the mouse anchored while zooming.
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

    ; Wheel events are discrete, but touchpads can burst. Coalesce impossible-to-see
    ; intermediate states, then perform one atomic swap for the latest viewport.
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

    LabEditorDirectNavInstallAttempts += 1
    if !IsSet(LabEditorPanLeftBtn) || !IsObject(LabEditorPanLeftBtn) {
        if (LabEditorDirectNavInstallAttempts < 20)
            SetTimer(StrategyEditorInstallDirectNavigation, -250)
        return
    }

    StrategyEditorHideLegacyPanButtons()
    try LabEditorSyncBtn.Move(228, 174, 86, 24)
}

StrategyEditorHideLegacyPanButtons() {
    global LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn
    if !IsSet(LabEditorPanLeftBtn) || !IsObject(LabEditorPanLeftBtn)
        return
    ; Keep the old controls alive for compatibility, but direct manipulation replaces them.
    for ctrl in [LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn] {
        ctrl.Enabled := false
        ctrl.Visible := false
        ctrl.Move(-1000, -1000, 1, 1)
    }
}

StrategyEditorInteractiveStateGuard(*) {
    global LabEditorDoc, LabEditorSelectedRow, LabEditorDirty
    if !StrategyEditorIsActive()
        return

    ; StrategyEditorShow() can make all legacy controls visible again.
    StrategyEditorHideLegacyPanButtons()

    if !IsObject(LabEditorDoc)
        return

    if (LabEditorSelectedRow < 1 && LabEditorDoc.Placements.Length > 0)
        StrategyEditorSelectPlacement(1)

    ; Recover from stale empty-state text after asynchronous asset/UI refreshes.
    if IsSet(LabEditorDirty) && IsObject(LabEditorDirty) && LabEditorDirty.Text = "No strategy loaded."
        StrategyEditorRefreshDirty()
}

SetTimer(StrategyEditorInstallDirectNavigation, -250)
SetTimer(StrategyEditorInteractiveStateGuard, 400)