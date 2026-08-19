#Requires AutoHotkey v2.0

; Strategy Lab 0.4.4 runtime isolation hotfix.
;
; 0.4.3 proved that even an in-memory composite can saturate the GUI thread when every
; WM_MOUSEMOVE redraws dozens of footprints. It also exposed a re-entrancy race where
; LabEditorDragPlacement could be cleared between the initial IsObject() guard and a
; later .towerId read. This module owns the four canvas mouse messages and deliberately
; keeps gameplay and editor work separated.

global Lab044DragLastPaint := 0
global Lab044DragLastFieldUpdate := 0
global Lab044PanLastPaint := 0
global Lab044WheelPending := false
global Lab044GameplayWasRunning := false

Lab044StrategyRunning() {
    global RunningStrategy
    if !IsSet(RunningStrategy)
        return false
    try return !!RunningStrategy
    catch
        return false
}

Lab044ReleasePointerCapture(clearDrag := false) {
    global LabEditorPanActive, LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global LabEditorDragPlacement, LabEditorDragIndex, LabEditorDragPreviewX, LabEditorDragPreviewY
    global LabEditorDragLastFrame, LabEditorDragLastStatus

    LabEditorPanActive := false
    LabEditorPanLastMouseX := ""
    LabEditorPanLastMouseY := ""
    if clearDrag {
        LabEditorDragPlacement := ""
        LabEditorDragIndex := 0
        LabEditorDragPreviewX := ""
        LabEditorDragPreviewY := ""
        LabEditorDragLastFrame := 0
        LabEditorDragLastStatus := 0
    }
    try DllCall("ReleaseCapture")
}

; Ultimate Macro uses absolute screen clicks. A visible AlwaysOnTop Strategy Lab window
; can physically sit on those coordinates and consume the clicks even though Roblox is
; active underneath. During a strategy run the editor therefore yields completely and
; MainGui is kept hidden. The original macro remains responsible for showing it again
; when RunStrategy finishes.
Lab044GameplayUiGuard(*) {
    global MainGui, Lab044GameplayWasRunning

    running := Lab044StrategyRunning()
    if !running {
        Lab044GameplayWasRunning := false
        return
    }

    if !Lab044GameplayWasRunning {
        Lab044GameplayWasRunning := true
        Lab044ReleasePointerCapture(true)
    }

    if !IsSet(MainGui) || !IsObject(MainGui)
        return
    hwnd := 0
    try hwnd := MainGui.Hwnd
    if !hwnd || !DllCall("user32\\IsWindow", "Ptr", hwnd, "Int")
        return
    if DllCall("user32\\IsWindowVisible", "Ptr", hwnd, "Int")
        try MainGui.Hide()
}
SetTimer(Lab044GameplayUiGuard, 120)

Lab044CanvasMouseDown(wParam, lParam, msg, hwnd) {
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorPanActive, LabEditorPanStartX, LabEditorPanStartY
    global LabEditorPanStartCenterX, LabEditorPanStartCenterY
    global LabEditorPanLastMouseX, LabEditorPanLastMouseY, LabEditorViewport, MainGui
    global Lab044PanLastPaint

    if Lab044StrategyRunning()
        return
    if !StrategyEditorIsActive()
        return

    StrategyEditorGetClientCursor(&mx, &my)
    if (mx < LabEditorCanvasX || mx > LabEditorCanvasX + LabEditorCanvasW
        || my < LabEditorCanvasY || my > LabEditorCanvasY + LabEditorCanvasH)
        return

    hitIndex := StrategyEditorHitTestPlacement(mx, my)
    if (hitIndex > 0) {
        if StrategyEditorBeginDrag(hitIndex) {
            Lab044DragLastPaint := 0
            Lab044DragLastFieldUpdate := 0
            return 0
        }
    }

    LabEditorPanActive := true
    LabEditorPanStartX := mx
    LabEditorPanStartY := my
    LabEditorPanStartCenterX := LabEditorViewport.CenterX
    LabEditorPanStartCenterY := LabEditorViewport.CenterY
    LabEditorPanLastMouseX := mx
    LabEditorPanLastMouseY := my
    Lab044PanLastPaint := 0
    try DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return 0
}

Lab044CanvasMouseMove(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragIndex
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragPreviewX, LabEditorDragPreviewY, LabEditorXCtrl, LabEditorYCtrl
    global LabEditorPanActive, LabEditorViewport
    global LabEditorPanStartX, LabEditorPanStartY, LabEditorPanStartCenterX, LabEditorPanStartCenterY
    global LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global Lab044DragLastPaint, Lab044DragLastFieldUpdate, Lab044PanLastPaint

    if Lab044StrategyRunning() {
        Lab044ReleasePointerCapture(true)
        return
    }

    ; Snapshot the object/index exactly once. Never dereference the mutable global after
    ; this point: GUI timers and mouse-up messages are allowed to clear it re-entrantly.
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

        ; Text controls are cheap but still native HWND traffic. 10 Hz is plenty while
        ; the pointer itself remains full-speed.
        if (!Lab044DragLastFieldUpdate || now - Lab044DragLastFieldUpdate >= 100) {
            Lab044DragLastFieldUpdate := now
            if LabEditorControlAlive(LabEditorXCtrl)
                try LabEditorXCtrl.Text := logical.x
            if LabEditorControlAlive(LabEditorYCtrl)
                try LabEditorYCtrl.Text := logical.y
        }

        ; 0.4.3 attempted ~50 full composites/sec. Cap live preview at ~12.5 fps; final
        ; mouse-up always renders immediately at full quality. This keeps the UI thread
        ; responsive even with 30-50 placements.
        if (!Lab044DragLastPaint || now - Lab044DragLastPaint >= 80) {
            Lab044DragLastPaint := now
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

    now := A_TickCount
    if (!Lab044PanLastPaint || now - Lab044PanLastPaint >= 85) {
        Lab044PanLastPaint := now
        StrategyEditorRenderBackground(false)
    }
    return 0
}

Lab044CanvasMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragIndex
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragPreviewX, LabEditorDragPreviewY
    global LabEditorPanActive, LabEditorPanLastMouseX, LabEditorPanLastMouseY

    drag := LabEditorDragPlacement
    dragIndex := LabEditorDragIndex
    if IsObject(drag) && dragIndex > 0 && IsObject(LabEditorDoc) {
        StrategyEditorGetClientCursor(&mx, &my)
        mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
        my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
        logical := StrategyEditorViewportToStrategy(mx, my)

        changed := LabEditorDoc.MovePlacement(drag, logical.x, logical.y)
        Lab044ReleasePointerCapture(true)
        StrategyEditorRefreshLayerList(dragIndex)
        StrategyEditorSelectPlacement(dragIndex)

        if changed {
            collisions := LabFootprintCollisionMap(LabEditorDoc)
            if collisions.Has(dragIndex)
                StrategyEditorSetStatus("Moved " drag.towerId " to (" drag.x ", " drag.y "). WARNING: placement footprint intersects another tower.", true)
            else
                StrategyEditorSetStatus("Moved " drag.towerId " to (" drag.x ", " drag.y "). Not saved yet.")
        }
        StrategyEditorRefreshButtons()
        StrategyEditorRefreshDirty()
        return 0
    }

    if !LabEditorPanActive
        return
    LabEditorPanActive := false
    LabEditorPanLastMouseX := ""
    LabEditorPanLastMouseY := ""
    try DllCall("ReleaseCapture")
    if StrategyEditorIsActive()
        StrategyEditorRenderBackground(false)
    return 0
}

Lab044CanvasWheel(wParam, lParam, msg, hwnd) {
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorViewport, Lab044WheelPending

    if Lab044StrategyRunning() || !StrategyEditorIsActive()
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
    newZoom := Max(1.0, Min(4.0, oldZoom + (delta / 120.0) * 0.15))
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

    Lab044WheelPending := true
    SetTimer(Lab044WheelFlush, -90)
    return 0
}

Lab044WheelFlush(*) {
    global Lab044WheelPending
    if !Lab044WheelPending || Lab044StrategyRunning() || !StrategyEditorIsActive()
        return
    Lab044WheelPending := false
    StrategyEditorRenderBackground(false)
}
