#Requires AutoHotkey v2.0

; Direct map interaction layer.
; Wheel zooms around the cursor. Dragging empty canvas pans the viewport.
; Dragging a placement continues to move that placement through the existing editor path.

global LabEditorPanActive := false
global LabEditorPanStartX := 0
global LabEditorPanStartY := 0
global LabEditorPanStartCenterX := 0.5
global LabEditorPanStartCenterY := 0.5
global LabEditorPanLastRender := 0
global LabEditorDirectNavInstallAttempts := 0

StrategyEditorDirectMouseDown(wParam, lParam, msg, hwnd) {
    global CurrentTab, LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorPanActive, LabEditorPanStartX, LabEditorPanStartY
    global LabEditorPanStartCenterX, LabEditorPanStartCenterY, LabEditorPanLastRender
    global LabEditorViewport, MainGui

    if (CurrentTab != "Tab7")
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
    DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return 0
}

StrategyEditorInteractiveMouseMove(wParam, lParam, msg, hwnd) {
    global LabEditorPanActive, LabEditorViewport
    global LabEditorPanStartX, LabEditorPanStartY, LabEditorPanStartCenterX, LabEditorPanStartCenterY
    global LabEditorPanLastRender, LabEditorCanvasW, LabEditorCanvasH

    if !LabEditorPanActive
        return StrategyEditorMouseMove(wParam, lParam, msg, hwnd)

    StrategyEditorGetClientCursor(&mx, &my)
    visibleW := 1.0 / LabEditorViewport.Zoom
    visibleH := 1.0 / LabEditorViewport.Zoom
    dx := mx - LabEditorPanStartX
    dy := my - LabEditorPanStartY

    ; Dragging the picture right moves the visible world right, so the camera center moves left.
    LabEditorViewport.CenterX := LabEditorPanStartCenterX - (dx / Max(1, LabEditorCanvasW)) * visibleW
    LabEditorViewport.CenterY := LabEditorPanStartCenterY - (dy / Max(1, LabEditorCanvasH)) * visibleH
    LabEditorViewport.ClampCenter()

    ; Rendering a viewport involves GDI+, so cap live pan redraw to roughly 30 FPS.
    if (!LabEditorPanLastRender || A_TickCount - LabEditorPanLastRender >= 33) {
        LabEditorPanLastRender := A_TickCount
        StrategyEditorRenderBackground()
        StrategyEditorRefreshVisuals()
    }
    return 0
}

StrategyEditorInteractiveMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorPanActive
    if !LabEditorPanActive
        return StrategyEditorMouseUp(wParam, lParam, msg, hwnd)

    LabEditorPanActive := false
    try DllCall("ReleaseCapture")
    StrategyEditorRenderBackground()
    StrategyEditorRefreshVisuals()
    return 0
}

StrategyEditorInteractiveWheel(wParam, lParam, msg, hwnd) {
    global CurrentTab, LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorViewport

    if (CurrentTab != "Tab7")
        return
    StrategyEditorGetClientCursor(&mx, &my)
    if (mx < LabEditorCanvasX || mx > LabEditorCanvasX + LabEditorCanvasW
        || my < LabEditorCanvasY || my > LabEditorCanvasY + LabEditorCanvasH)
        return

    delta := (wParam >> 16) & 0xFFFF
    if (delta > 32767)
        delta -= 65536

    oldZoom := LabEditorViewport.Zoom
    newZoom := Max(1.0, Min(4.0, oldZoom + (delta > 0 ? 0.25 : -0.25)))
    if (newZoom = oldZoom)
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

    StrategyEditorRenderBackground()
    StrategyEditorRefreshVisuals()
    return 0
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

    ; Keep legacy controls alive for compatibility but move/disable them permanently.
    for ctrl in [LabEditorPanLeftBtn, LabEditorPanUpBtn, LabEditorPanDownBtn, LabEditorPanRightBtn] {
        ctrl.Enabled := false
        ctrl.Move(-1000, -1000, 1, 1)
    }

    ; Reclaim the toolbar space for the useful action.
    try LabEditorSyncBtn.Move(228, 174, 86, 24)
}

SetTimer(StrategyEditorInstallDirectNavigation, -250)
