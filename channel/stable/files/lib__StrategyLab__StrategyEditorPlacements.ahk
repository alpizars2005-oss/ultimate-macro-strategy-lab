#Requires AutoHotkey v2.0

; Strategy Lab 0.4.3 placement model.
; Visuals are rendered into the map frame by StrategyEditorMaps.ahk. This file owns
; layers, selection, hit-testing and drag state only. No placement creates a Gui.Control.

global LabEditorDragLastFrame := 0
global LabEditorDragLastStatus := 0
global LabEditorLayerOptions := ["All placements"]
global LabEditorListRowMap := []
global LabEditorLayerChangeBusy := false
global LabEditorRingMode := "all"

StrategyEditorBuildLayers() {
    global LabEditorDoc, LabEditorLayerCtrl, LabEditorLayer, LabEditorLayerOptions
    global LabEditorLayerChangeBusy

    if !IsObject(LabEditorDoc) || !LabEditorControlAlive(LabEditorLayerCtrl)
        return

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

    wanted := LabEditorLayer
    wantedIndex := 1
    for index, option in options {
        if (option = wanted) {
            wantedIndex := index
            break
        }
    }

    LabEditorLayerOptions := options
    LabEditorLayerChangeBusy := true
    try {
        LabEditorLayerCtrl.Delete()
        LabEditorLayerCtrl.Add(options)
        LabEditorLayerCtrl.Choose(wantedIndex)
        LabEditorLayer := options[wantedIndex]
    } finally {
        LabEditorLayerChangeBusy := false
    }
}

StrategyEditorResolveLayerSelection() {
    global LabEditorLayerCtrl, LabEditorLayerOptions
    if !LabEditorControlAlive(LabEditorLayerCtrl)
        return "All placements"

    selectedText := ""
    try selectedText := Trim(LabEditorLayerCtrl.Text)
    if (selectedText != "") {
        for option in LabEditorLayerOptions {
            if (option = selectedText)
                return option
        }
    }

    choice := 0
    try choice := Integer(LabEditorLayerCtrl.Value)
    if (choice >= 1 && choice <= LabEditorLayerOptions.Length)
        return LabEditorLayerOptions[choice]
    return "All placements"
}

StrategyEditorMarkerLabel(placement) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return "?"
    rawTower := LabEditorDoc.TowerNameForSlot(placement.slot)
    if (rawTower = "")
        return String(placement.slot)
    entry := LabTowerResolve(rawTower)
    if (entry.placementLimit = 1)
        return StrUpper(SubStr(entry.name, 1, 1))
    return String(LabTowerOccurrence(LabEditorDoc, placement))
}

StrategyEditorSlotColor(slot, alpha := 255) {
    colors := [0xE45757, 0x4E7DD1, 0x54A76A, 0xB06AC2, 0xD3A64B]
    slotNum := IsNumber(slot) ? Integer(slot) : 1
    rgb := colors[Max(1, Min(colors.Length, slotNum))]
    a := Max(0, Min(255, Integer(alpha)))
    return (a << 24) | rgb
}

StrategyEditorPlacementFootprint(placement) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return 1.5
    return LabFootprintUnitsForPlacement(placement, LabEditorDoc)
}

; Compatibility scalar for older tests/helpers. The live renderer uses the full
; width/height ellipse returned by LabFootprintCanvasEllipse so X/Y projection remains exact.
StrategyEditorFootprintDiameter(placement) {
    global LabEditorDoc, LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    if !IsObject(LabEditorDoc)
        return 1
    ellipse := LabFootprintCanvasEllipse(placement, LabEditorDoc, LabEditorViewport,
        LabEditorCanvasW, LabEditorCanvasH)
    return Max(1, Round((ellipse.w + ellipse.h) / 2.0))
}

StrategyEditorMarkerDiameter(index) {
    global LabEditorSelectedRow
    return LabFootprintMarkerDiameter(index = LabEditorSelectedRow)
}

StrategyEditorRingModeAllows(index) {
    global LabEditorRingMode, LabEditorSelectedRow
    if (LabEditorRingMode = "off")
        return false
    if (LabEditorRingMode = "selected")
        return index = LabEditorSelectedRow
    return true
}

StrategyEditorRingButtonText() {
    global LabEditorRingMode
    if (LabEditorRingMode = "selected")
        return "Footprints: 1"
    if (LabEditorRingMode = "off")
        return "Footprints: Off"
    return "Footprints: All"
}

StrategyEditorToggleRings(*) {
    global LabEditorRingMode, LabEditorRingsBtn
    LabEditorRingMode := LabEditorRingMode = "all" ? "selected" : (LabEditorRingMode = "selected" ? "off" : "all")
    if LabEditorControlAlive(LabEditorRingsBtn)
        try LabEditorRingsBtn.Text := StrategyEditorRingButtonText()
    StrategyEditorRenderBackground()
    label := LabEditorRingMode = "all" ? "all placement footprints" : (LabEditorRingMode = "selected" ? "selected placement footprint" : "placement footprints hidden")
    StrategyEditorSetStatus("Canvas guides: " label ". Red means two reserved placement areas intersect.")
}

; Compatibility name. In 0.4 this does not build Windows controls; it just refreshes
; the ListView and asks the single canvas to render placements.
StrategyEditorBuildMarkers() {
    global LabEditorMarkerCtrls, LabEditorMarkerByHwnd, LabEditorHitRegions
    LabEditorMarkerCtrls := []
    LabEditorMarkerByHwnd := Map()
    LabEditorHitRegions := []
    StrategyEditorRefreshLayerList()
    StrategyEditorRenderBackground()
}

StrategyEditorClearMarkers() {
    global LabEditorMarkerCtrls, LabEditorMarkerByHwnd, LabEditorHitRegions, LabEditorListRowMap
    LabEditorMarkerCtrls := []
    LabEditorMarkerByHwnd := Map()
    LabEditorHitRegions := []
    LabEditorListRowMap := []
}

StrategyEditorRefreshMarkerSelection() {
    StrategyEditorRenderBackground()
}

StrategyEditorRaiseVisibleMarkers() {
    ; No-op by design: placements are pixels in the single canvas, not sibling HWNDs.
}

StrategyEditorRefreshMarkerLayout() {
    StrategyEditorRenderBackground(false)
}

StrategyEditorRefreshLayerList(selectDocIndex := 0) {
    global LabEditorDoc, LabEditorList, LabEditorListRowMap, LabEditorSelectedRow
    if !IsObject(LabEditorDoc) || !LabEditorControlAlive(LabEditorList)
        return

    if (selectDocIndex <= 0)
        selectDocIndex := LabEditorSelectedRow

    try LabEditorList.Delete()
    LabEditorListRowMap := []
    visibleRow := 0

    for index, placement in LabEditorDoc.Placements {
        if !StrategyEditorPlacementVisible(placement)
            continue
        LabEditorList.Add(, index, LabTowerPlacementDisplay(LabEditorDoc, placement), placement.x, placement.y)
        LabEditorListRowMap.Push(index)
        if (index = selectDocIndex)
            visibleRow := LabEditorListRowMap.Length
    }

    if (visibleRow > 0)
        try LabEditorList.Modify(visibleRow, "Vis Select Focus")
}

StrategyEditorRefreshVisuals(rebuildList := true) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return
    if rebuildList
        StrategyEditorRefreshLayerList()
    StrategyEditorRenderBackground()
}

StrategyEditorPlacementVisible(placement) {
    global LabEditorDoc, LabEditorLayer
    if !IsObject(LabEditorDoc)
        return false
    if (LabEditorLayer = "All placements")
        return true
    slot := String(placement.slot)
    tower := LabEditorDoc.TowerNameForSlot(slot)
    return LabEditorLayer = "Slot " slot (tower != "" ? " - " tower : "")
}

StrategyEditorApplyLayer() {
    StrategyEditorRenderBackground()
}

StrategyEditorLayerChanged(*) {
    global LabEditorLayer, LabEditorDoc, LabEditorSelectedRow
    global LabEditorListRowMap, LabEditorLayerChangeBusy

    if LabEditorLayerChangeBusy || !IsObject(LabEditorDoc)
        return

    LabEditorLayer := StrategyEditorResolveLayerSelection()

    firstVisible := 0
    selectedStillVisible := false
    for index, placement in LabEditorDoc.Placements {
        if !StrategyEditorPlacementVisible(placement)
            continue
        if !firstVisible
            firstVisible := index
        if (index = LabEditorSelectedRow)
            selectedStillVisible := true
    }

    if !selectedStillVisible
        LabEditorSelectedRow := firstVisible

    StrategyEditorRefreshLayerList(LabEditorSelectedRow)
    if (LabEditorSelectedRow > 0) {
        placement := LabEditorDoc.Placements[LabEditorSelectedRow]
        StrategyEditorShowTower(placement)
        visibleRow := StrategyEditorVisibleListRow(LabEditorSelectedRow)
        if (visibleRow > 0)
            try LabEditorList.Modify(visibleRow, "Vis Select Focus")
    }
    StrategyEditorRenderBackground()

    count := LabEditorListRowMap.Length
    StrategyEditorSetStatus("Layer: " LabEditorLayer " • " count " placement" (count = 1 ? "" : "s") ".")
}

StrategyEditorRowSelected(ctrl, row, selected) {
    global LabEditorListRowMap
    if !selected || row < 1 || row > LabEditorListRowMap.Length
        return
    StrategyEditorSelectPlacement(LabEditorListRowMap[row])
}

StrategyEditorVisibleListRow(docIndex) {
    global LabEditorListRowMap
    for row, mappedIndex in LabEditorListRowMap {
        if (mappedIndex = docIndex)
            return row
    }
    return 0
}

StrategyEditorSelectPlacement(row) {
    global LabEditorDoc, LabEditorSelectedRow, LabEditorList, LabEditorXCtrl, LabEditorYCtrl
    if !IsObject(LabEditorDoc) || row < 1 || row > LabEditorDoc.Placements.Length
        return
    LabEditorSelectedRow := row
    placement := LabEditorDoc.Placements[row]
    if LabEditorControlAlive(LabEditorXCtrl)
        try LabEditorXCtrl.Text := placement.x
    if LabEditorControlAlive(LabEditorYCtrl)
        try LabEditorYCtrl.Text := placement.y
    StrategyEditorShowTower(placement)
    visibleRow := StrategyEditorVisibleListRow(row)
    if (visibleRow > 0 && LabEditorControlAlive(LabEditorList))
        try LabEditorList.Modify(visibleRow, "Vis Select Focus")
    StrategyEditorRenderBackground()
}

StrategyEditorApplyCoordinates(*) {
    global LabEditorDoc, LabEditorSelectedRow, LabEditorXCtrl, LabEditorYCtrl
    if !IsObject(LabEditorDoc) || LabEditorSelectedRow < 1 {
        StrategyEditorSetStatus("Select a placement first.", true)
        return
    }
    if !LabEditorControlAlive(LabEditorXCtrl) || !LabEditorControlAlive(LabEditorYCtrl)
        return
    if !IsNumber(LabEditorXCtrl.Text) || !IsNumber(LabEditorYCtrl.Text) {
        StrategyEditorSetStatus("X and Y must be numbers.", true)
        return
    }
    placement := LabEditorDoc.Placements[LabEditorSelectedRow]
    LabEditorDoc.MovePlacement(placement, LabEditorXCtrl.Text, LabEditorYCtrl.Text)
    StrategyEditorRefreshVisuals()
    StrategyEditorSelectPlacement(LabEditorSelectedRow)
    collisions := LabFootprintCollisionMap(LabEditorDoc)
    if collisions.Has(LabEditorSelectedRow)
        StrategyEditorSetStatus("Updated " placement.towerId " to (" placement.x ", " placement.y "). WARNING: placement footprint intersects another tower.", true)
    else
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
    if !IsObject(LabEditorDoc)
        return 0
    for index, candidate in LabEditorDoc.Placements {
        if (candidate = placement)
            return index
    }
    return 0
}

StrategyEditorHitTestPlacement(mx, my) {
    global LabEditorHitRegions
    bestIndex := 0
    bestDistance := 0x7FFFFFFF
    for region in LabEditorHitRegions {
        dx := mx - region.x
        dy := my - region.y
        distance := (dx * dx) + (dy * dy)
        limit := region.radius * region.radius
        if (distance <= limit && distance < bestDistance) {
            bestDistance := distance
            bestIndex := region.index
        }
    }
    return bestIndex
}

StrategyEditorBeginDrag(index) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragIndex
    global LabEditorDragOldX, LabEditorDragOldY, LabEditorDragPreviewX, LabEditorDragPreviewY, MainGui

    if !IsObject(LabEditorDoc) || index < 1 || index > LabEditorDoc.Placements.Length
        return false

    placement := LabEditorDoc.Placements[index]
    LabEditorDragPlacement := placement
    LabEditorDragIndex := index
    LabEditorDragOldX := placement.x
    LabEditorDragOldY := placement.y
    LabEditorDragPreviewX := placement.x
    LabEditorDragPreviewY := placement.y
    StrategyEditorSelectPlacement(index)
    try DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return true
}

StrategyEditorMouseMove(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragIndex
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragLastFrame, LabEditorDragLastStatus, LabEditorDragPreviewX, LabEditorDragPreviewY
    global LabEditorXCtrl, LabEditorYCtrl

    if !IsObject(LabEditorDoc) || !IsObject(LabEditorDragPlacement) || LabEditorDragIndex < 1
        return

    now := A_TickCount
    if (LabEditorDragLastFrame && now - LabEditorDragLastFrame < 20)
        return 0

    StrategyEditorGetClientCursor(&mx, &my)
    mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
    my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
    logical := StrategyEditorViewportToStrategy(mx, my)
    if (logical.x = LabEditorDragPreviewX && logical.y = LabEditorDragPreviewY)
        return 0

    LabEditorDragLastFrame := now
    LabEditorDragPreviewX := logical.x
    LabEditorDragPreviewY := logical.y

    if (!LabEditorDragLastStatus || now - LabEditorDragLastStatus >= 75) {
        LabEditorDragLastStatus := now
        if LabEditorControlAlive(LabEditorXCtrl)
            try LabEditorXCtrl.Text := LabEditorDragPreviewX
        if LabEditorControlAlive(LabEditorYCtrl)
            try LabEditorYCtrl.Text := LabEditorDragPreviewY
        collisions := LabFootprintCollisionMap(LabEditorDoc)
        StrategyEditorSetStatus("Preview " LabEditorDragPlacement.towerId " → (" LabEditorDragPreviewX ", " LabEditorDragPreviewY ")"
            (collisions.Has(LabEditorDragIndex) ? " • footprint collision" : ""), collisions.Has(LabEditorDragIndex))
    }

    StrategyEditorRenderBackground(false)
    return 0
}

StrategyEditorMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragIndex
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragLastFrame, LabEditorDragLastStatus, LabEditorDragPreviewX, LabEditorDragPreviewY

    if !IsObject(LabEditorDoc) || !IsObject(LabEditorDragPlacement) || LabEditorDragIndex < 1
        return

    StrategyEditorGetClientCursor(&mx, &my)
    mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
    my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
    logical := StrategyEditorViewportToStrategy(mx, my)

    placement := LabEditorDragPlacement
    changed := LabEditorDoc.MovePlacement(placement, logical.x, logical.y)
    try DllCall("ReleaseCapture")

    row := LabEditorDragIndex
    LabEditorDragPlacement := ""
    LabEditorDragIndex := 0
    LabEditorDragLastFrame := 0
    LabEditorDragLastStatus := 0
    LabEditorDragPreviewX := ""
    LabEditorDragPreviewY := ""

    StrategyEditorRefreshVisuals()
    StrategyEditorSelectPlacement(row)
    if changed {
        collisions := LabFootprintCollisionMap(LabEditorDoc)
        if collisions.Has(row)
            StrategyEditorSetStatus("Moved " placement.towerId " to (" placement.x ", " placement.y "). WARNING: placement footprint intersects another tower.", true)
        else
            StrategyEditorSetStatus("Moved " placement.towerId " to (" placement.x ", " placement.y "). Not saved yet.")
    }
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
