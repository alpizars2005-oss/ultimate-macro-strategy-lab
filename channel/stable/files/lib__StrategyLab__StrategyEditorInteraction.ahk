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

; StrategyEditorRenderBackground swaps the Picture source after generating each
; viewport JPEG. Native Static controls otherwise repaint the empty state between
; those assignments, which is the flash visible while panning. WM_SETREDRAW lets us
; finish the whole swap off-screen and invalidate exactly once at the end.
StrategyEditorRenderBackgroundBuffered(repositionMarkers := true) {
    global LabEditorSnapshot, LabEditorCanvasBg
    suspended := []

    for ctrl in [LabEditorSnapshot, LabEditorCanvasBg] {
        if !IsObject(ctrl)
            continue
        hwnd := 0
        try hwnd := ctrl.Hwnd
        if !hwnd
            continue
        try {
            DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0, "Ptr") ; WM_SETREDRAW false
            suspended.Push(hwnd)
        }
    }

    result := false
    try result := StrategyEditorRenderBackground(repositionMarkers)
    finally {
        for hwnd in suspended {
            try DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0, "Ptr") ; WM_SETREDRAW true
            try DllCall("user32\RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x181) ; invalidate + all children + update now
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

    ; Keep live navigation near 42 FPS. The important difference is that each frame
    ; is now committed atomically instead of visibly clearing/reloading the Picture.
    if (!LabEditorPanLastRender || A_TickCount - LabEditorPanLastRender >= 24) {
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
    ; intermediate states, then perform one buffered swap for the latest viewport.
    now := A_TickCount
    if (!LabEditorWheelLastRender || now - LabEditorWheelLastRender >= 16) {
        LabEditorWheelLastRender := now
        StrategyEditorRenderBackgroundBuffered()
    } else {
        SetTimer(StrategyEditorWheelFlush, -16)
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
