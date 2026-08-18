#Requires AutoHotkey v2.0

global LabEditorDragLastFrame := 0
global LabEditorDragLastStatus := 0
global LabEditorDragPreviewX := ""
global LabEditorDragPreviewY := ""

StrategyEditorBuildLayers() {
    global LabEditorDoc, LabEditorLayerCtrl, LabEditorLayer
    options := ["All placements"]
    seen := Map()
    for placement in LabEditorDoc.Placements {
        slot := String(placement.slot)
        tower := LabEditorDoc.TowerNameForSlot(slot)
        label := "Slot " slot (tower != "" ? " - " tower : "")
        key := StrLower(label)
        if !seen.Has(key) {
            seen[key] := true
            options.Push(label)
        }
    }
    LabEditorLayerCtrl.Delete()
    LabEditorLayerCtrl.Add(options)
    LabEditorLayerCtrl.Choose(1)
    LabEditorLayer := "All placements"
}

StrategyEditorMarkerLabel(placement) {
    global LabEditorDoc
    rawTower := LabEditorDoc.TowerNameForSlot(placement.slot)
    if (rawTower = "")
        return String(placement.slot)
    entry := LabTowerResolve(rawTower)
    if (entry.placementLimit = 1)
        return StrUpper(SubStr(entry.name, 1, 1))
    return String(LabTowerOccurrence(LabEditorDoc, placement))
}

StrategyEditorMarkerClicked(index, *) {
    StrategyEditorSelectPlacement(index)
}

StrategyEditorBuildMarkers() {
    global LabEditorDoc, LabEditorList, LabEditorMarkerCtrls, LabEditorMarkerByHwnd, MainGui

    StrategyEditorClearMarkers()
    LabEditorList.Delete()
    LabEditorMarkerCtrls := []
    LabEditorMarkerByHwnd := Map()

    colors := ["B04747", "476FB0", "4A8F59", "9C6CB0", "B08A47"]
    for index, placement in LabEditorDoc.Placements {
        LabEditorList.Add(, index, LabTowerPlacementDisplay(LabEditorDoc, placement), placement.x, placement.y)

        point := StrategyEditorPlacementPoint(placement)
        slotNum := IsNumber(placement.slot) ? Integer(placement.slot) : 1
        color := colors[Max(1, Min(colors.Length, slotNum))]
        marker := MainGui.Add("Text", "x" (point.x - 9) " y" (point.y - 9)
            " w18 h18 Hidden Center +Border Background" color " cFFFFFF", StrategyEditorMarkerLabel(placement))
        marker.SetFont("s7 w700", "Segoe UI")
        marker.OnEvent("Click", StrategyEditorMarkerClicked.Bind(index))
        entry := {ctrl: marker, placement: placement, index: index, color: color}
        LabEditorMarkerCtrls.Push(entry)
        LabEditorMarkerByHwnd[marker.Hwnd] := entry
    }
    StrategyEditorRefreshMarkerSelection()
    StrategyEditorApplyLayer()
}

StrategyEditorClearMarkers() {
    global LabEditorMarkerCtrls, LabEditorMarkerByHwnd
    for entry in LabEditorMarkerCtrls {
        try entry.ctrl.Visible := false
        try DllCall("DestroyWindow", "Ptr", entry.ctrl.Hwnd)
    }
    LabEditorMarkerCtrls := []
    LabEditorMarkerByHwnd := Map()
}

StrategyEditorRefreshMarkerSelection() {
    global LabEditorMarkerCtrls, LabEditorSelectedRow
    for index, entry in LabEditorMarkerCtrls {
        point := StrategyEditorPlacementPoint(entry.placement)
        size := index = LabEditorSelectedRow ? 22 : 18
        entry.ctrl.Move(point.x - Floor(size / 2), point.y - Floor(size / 2), size, size)
        entry.ctrl.SetFont(index = LabEditorSelectedRow ? "s8 w700" : "s7 w700", "Segoe UI")
    }
}

; Fast path for pan/zoom/layout changes. It deliberately avoids rebuilding the
; native ListView, which is one of the most expensive operations in the editor.
StrategyEditorRefreshMarkerLayout() {
    StrategyEditorRefreshMarkerSelection()
    StrategyEditorApplyLayer()
}

StrategyEditorRefreshVisuals(rebuildList := true) {
    global LabEditorDoc, LabEditorList, LabEditorMarkerCtrls
    if !IsObject(LabEditorDoc)
        return

    if rebuildList {
        LabEditorList.Delete()
        for index, placement in LabEditorDoc.Placements {
            LabEditorList.Add(, index, LabTowerPlacementDisplay(LabEditorDoc, placement), placement.x, placement.y)
            if (index > LabEditorMarkerCtrls.Length)
                continue
            entry := LabEditorMarkerCtrls[index]
            entry.placement := placement
            entry.index := index
        }
    }
    StrategyEditorRefreshMarkerLayout()
}

StrategyEditorPlacementVisible(placement) {
    global LabEditorDoc, LabEditorLayer
    if (LabEditorLayer = "All placements")
        return true
    slot := String(placement.slot)
    tower := LabEditorDoc.TowerNameForSlot(slot)
    return LabEditorLayer = "Slot " slot (tower != "" ? " - " tower : "")
}

StrategyEditorApplyLayer() {
    global LabEditorMarkerCtrls, CurrentTab
    for entry in LabEditorMarkerCtrls {
        point := StrategyEditorPlacementPoint(entry.placement)
        entry.ctrl.Visible := (CurrentTab = "Tab7") && point.visible && StrategyEditorPlacementVisible(entry.placement)
    }
}

StrategyEditorLayerChanged(*) {
    global LabEditorLayerCtrl, LabEditorLayer
    LabEditorLayer := LabEditorLayerCtrl.Text
    StrategyEditorApplyLayer()
}

StrategyEditorRowSelected(ctrl, row, selected) {
    if selected
        StrategyEditorSelectPlacement(row)
}

StrategyEditorSelectPlacement(row) {
    global LabEditorDoc, LabEditorSelectedRow, LabEditorList, LabEditorXCtrl, LabEditorYCtrl
    if !IsObject(LabEditorDoc) || row < 1 || row > LabEditorDoc.Placements.Length
        return
    LabEditorSelectedRow := row
    placement := LabEditorDoc.Placements[row]
    LabEditorXCtrl.Text := placement.x
    LabEditorYCtrl.Text := placement.y
    StrategyEditorShowTower(placement)
    StrategyEditorRefreshMarkerSelection()
    try LabEditorList.Modify(row, "Vis Select Focus")
}

StrategyEditorApplyCoordinates(*) {
    global LabEditorDoc, LabEditorSelectedRow, LabEditorXCtrl, LabEditorYCtrl
    if !IsObject(LabEditorDoc) || LabEditorSelectedRow < 1 {
        StrategyEditorSetStatus("Select a placement first.", true)
        return
    }
    if !IsNumber(LabEditorXCtrl.Text) || !IsNumber(LabEditorYCtrl.Text) {
        StrategyEditorSetStatus("X and Y must be numbers.", true)
        return
    }
    placement := LabEditorDoc.Placements[LabEditorSelectedRow]
    LabEditorDoc.MovePlacement(placement, LabEditorXCtrl.Text, LabEditorYCtrl.Text)
    StrategyEditorRefreshVisuals()
    StrategyEditorSelectPlacement(LabEditorSelectedRow)
    StrategyEditorSetStatus("Updated " placement.towerId " to (" placement.x ", " placement.y "). Not saved yet.")
    StrategyEditorRefreshButtons()
    StrategyEditorRefreshDirty()
}

StrategyEditorUndo(*) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return
    placement := LabEditorDoc.Undo()
    if placement {
        row := StrategyEditorFindPlacementRow(placement)
        StrategyEditorRefreshVisuals()
        StrategyEditorSelectPlacement(row)
        StrategyEditorSetStatus("Undo: " placement.towerId " is back at (" placement.x ", " placement.y ").")
    }
    StrategyEditorRefreshButtons()
    StrategyEditorRefreshDirty()
}

StrategyEditorRedo(*) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return
    placement := LabEditorDoc.Redo()
    if placement {
        row := StrategyEditorFindPlacementRow(placement)
        StrategyEditorRefreshVisuals()
        StrategyEditorSelectPlacement(row)
        StrategyEditorSetStatus("Redo: " placement.towerId " moved to (" placement.x ", " placement.y ").")
    }
    StrategyEditorRefreshButtons()
    StrategyEditorRefreshDirty()
}

StrategyEditorFindPlacementRow(placement) {
    global LabEditorDoc
    for index, candidate in LabEditorDoc.Placements {
        if (candidate = placement)
            return index
    }
    return 0
}

StrategyEditorMouseMove(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragMarker
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragLastFrame, LabEditorDragLastStatus, LabEditorDragPreviewX, LabEditorDragPreviewY
    global LabEditorXCtrl, LabEditorYCtrl

    if !IsObject(LabEditorDoc) || !IsObject(LabEditorDragPlacement) || !IsObject(LabEditorDragMarker)
        return

    ; Coalesce the very noisy WM_MOUSEMOVE stream to about 60 FPS. Windows can
    ; otherwise deliver hundreds of move messages per second and make AHK repaint
    ; text/status controls far more often than the monitor can display.
    now := A_TickCount
    if (LabEditorDragLastFrame && now - LabEditorDragLastFrame < 16)
        return 0
    LabEditorDragLastFrame := now

    StrategyEditorGetClientCursor(&mx, &my)
    mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
    my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
    logical := StrategyEditorViewportToStrategy(mx, my)
    LabEditorDragPreviewX := logical.x
    LabEditorDragPreviewY := logical.y

    ; Moving one tiny marker is cheap; rebuilding the placement list is not.
    LabEditorDragMarker.Move(mx - 11, my - 11, 22, 22)

    ; Coordinate/status text updates are intentionally slower than marker motion.
    ; This keeps dragging visually attached to the cursor while still giving live feedback.
    if (!LabEditorDragLastStatus || now - LabEditorDragLastStatus >= 75) {
        LabEditorDragLastStatus := now
        try LabEditorXCtrl.Text := LabEditorDragPreviewX
        try LabEditorYCtrl.Text := LabEditorDragPreviewY
        StrategyEditorSetStatus("Preview " LabEditorDragPlacement.towerId " → (" LabEditorDragPreviewX ", " LabEditorDragPreviewY ")")
    }
    return 0
}

StrategyEditorMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragMarker
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragLastFrame, LabEditorDragLastStatus, LabEditorDragPreviewX, LabEditorDragPreviewY

    if !IsObject(LabEditorDoc) || !IsObject(LabEditorDragPlacement) || !IsObject(LabEditorDragMarker)
        return

    ; Always sample the final cursor position rather than trusting the last throttled frame.
    StrategyEditorGetClientCursor(&mx, &my)
    mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
    my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
    logical := StrategyEditorViewportToStrategy(mx, my)
    newX := logical.x
    newY := logical.y

    placement := LabEditorDragPlacement
    changed := LabEditorDoc.MovePlacement(placement, newX, newY)
    try DllCall("ReleaseCapture")
    LabEditorDragPlacement := ""
    LabEditorDragMarker := ""
    LabEditorDragLastFrame := 0
    LabEditorDragLastStatus := 0
    LabEditorDragPreviewX := ""
    LabEditorDragPreviewY := ""

    row := StrategyEditorFindPlacementRow(placement)
    StrategyEditorRefreshVisuals()
    StrategyEditorSelectPlacement(row)
    if changed
        StrategyEditorSetStatus("Moved " placement.towerId " to (" placement.x ", " placement.y "). Not saved yet.")
    StrategyEditorRefreshButtons()
    StrategyEditorRefreshDirty()
    return 0
}

StrategyEditorGetClientCursor(&x, &y) {
    global MainGui
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    DllCall("ScreenToClient", "Ptr", MainGui.Hwnd, "Ptr", pt)
    x := NumGet(pt, 0, "Int")
    y := NumGet(pt, 4, "Int")
}
