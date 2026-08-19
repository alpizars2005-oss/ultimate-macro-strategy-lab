#Requires AutoHotkey v2.0

; Strategy Lab 0.4 direct canvas interaction.
; Placement selection/drag uses geometric hit regions painted into the single bitmap;
; no message routing depends on per-placement child HWNDs.

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
    return LabEditorControlVisible(LabEditorCanvasBg) || LabEditorControlVisible(LabEditorSnapshot)
}

StrategyEditorRenderBackgroundBuffered(repositionMarkers := true) {
    ; A single Picture control already gives us the stable composition boundary. The
    ; renderer double-buffers its files, so freezing the whole GUI is unnecessary.
    return StrategyEditorRenderBackground(repositionMarkers)
}

StrategyEditorDirectMouseDown(wParam, lParam, msg, hwnd) {
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorPanActive, LabEditorPanStartX, LabEditorPanStartY
    global LabEditorPanStartCenterX, LabEditorPanStartCenterY, LabEditorPanLastRender
    global LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global LabEditorViewport, MainGui

    if !StrategyEditorIsActive()
        return

    StrategyEditorGetClientCursor(&mx, &my)
    if (mx < LabEditorCanvasX || mx > LabEditorCanvasX + LabEditorCanvasW
        || my < LabEditorCanvasY || my > LabEditorCanvasY + LabEditorCanvasH)
        return

    hitIndex := StrategyEditorHitTestPlacement(mx, my)
    if (hitIndex > 0) {
        if StrategyEditorBeginDrag(hitIndex)
            return 0
    }

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
    global LabEditorPanActive, LabEditorViewport, LabEditorDragPlacement
    global LabEditorPanStartX, LabEditorPanStartY, LabEditorPanStartCenterX, LabEditorPanStartCenterY
    global LabEditorPanLastRender, LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global LabEditorCanvasW, LabEditorCanvasH

    if IsObject(LabEditorDragPlacement)
        return StrategyEditorMouseMove(wParam, lParam, msg, hwnd)
    if !LabEditorPanActive
        return

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
        StrategyEditorRenderBackgroundBuffered(false)
    }
    return 0
}

StrategyEditorInteractiveMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorPanActive, LabEditorPanLastMouseX, LabEditorPanLastMouseY, LabEditorDragPlacement

    if IsObject(LabEditorDragPlacement)
        return StrategyEditorMouseUp(wParam, lParam, msg, hwnd)
    if !LabEditorPanActive
        return

    LabEditorPanActive := false
    LabEditorPanLastMouseX := ""
    LabEditorPanLastMouseY := ""
    try DllCall("ReleaseCapture")
    if StrategyEditorIsActive()
        StrategyEditorRenderBackgroundBuffered(false)
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
        StrategyEditorRenderBackgroundBuffered(false)
    } else {
        SetTimer(StrategyEditorWheelFlush, -28)
    }
    return 0
}

StrategyEditorWheelFlush(*) {
    global LabEditorWheelLastRender
    if !StrategyEditorIsActive()
        return
    LabEditorWheelLastRender := A_TickCount
    StrategyEditorRenderBackgroundBuffered(false)
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
        try LabEditorSyncBtn.Move(298, 177, 104, 24)
}

StrategyEditorHideLegacyPanButtons() {
    global LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn
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
