#Requires AutoHotkey v2.0

global LabEditorDragLastFrame := 0
global LabEditorDragLastStatus := 0
global LabEditorDragPreviewX := ""
global LabEditorDragPreviewY := ""
global LabEditorDragRing := ""
global LabEditorLayerOptions := ["All placements"]
global LabEditorListRowMap := []
global LabEditorRingMode := "all"
global LabEditorRingTemplatePath := ""

StrategyEditorBuildLayers() {
    global LabEditorDoc, LabEditorLayerCtrl, LabEditorLayer, LabEditorLayerOptions
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
    LabEditorLayerCtrl.Delete()
    LabEditorLayerCtrl.Add(options)
    LabEditorLayerCtrl.Choose(wantedIndex)
    LabEditorLayer := options[wantedIndex]
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

StrategyEditorSetCircularRegion(ctrl, size) {
    if !IsObject(ctrl) || size <= 0
        return
    region := DllCall("gdi32\CreateEllipticRgn", "Int", 0, "Int", 0, "Int", size + 1, "Int", size + 1, "Ptr")
    if !region
        return
    if !DllCall("user32\SetWindowRgn", "Ptr", ctrl.Hwnd, "Ptr", region, "Int", 1)
        DllCall("gdi32\DeleteObject", "Ptr", region)
}

; One tiny alpha PNG is stretched for every placement footprint. Keeping it in
; AppData avoids shipping another binary asset and keeps the stable package tiny.
StrategyEditorRingImagePath() {
    global LabEditorRingTemplatePath
    if (LabEditorRingTemplatePath != "" && FileExist(LabEditorRingTemplatePath))
        return LabEditorRingTemplatePath

    dir := A_AppData "\Ultimate_Macro\StrategyEditor\ui"
    if !DirExist(dir)
        DirCreate(dir)
    path := dir "\placement-footprint-ring.png"
    if FileExist(path) {
        LabEditorRingTemplatePath := path
        return path
    }

    pBitmap := 0
    graphics := 0
    pen := 0
    try {
        canvas := 256
        inset := 10.0
        pBitmap := Gdip_CreateBitmap(canvas, canvas)
        if !pBitmap
            return ""
        graphics := Gdip_GraphicsFromImage(pBitmap)
        if !graphics
            return ""
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0xD035BFFF, "Float", 7.0, "Int", 2, "Ptr*", &pen)
        if !pen
            return ""
        DllCall("gdiplus\GdipDrawEllipse", "Ptr", graphics, "Ptr", pen,
            "Float", inset, "Float", inset,
            "Float", canvas - (inset * 2), "Float", canvas - (inset * 2))
        Gdip_SaveBitmapToFile(pBitmap, path)
        if FileExist(path) && FileGetSize(path) > 300 {
            LabEditorRingTemplatePath := path
            return path
        }
    } catch {
        return ""
    } finally {
        if pen
            try DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
        if graphics
            try Gdip_DeleteGraphics(graphics)
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
    }
    return ""
}

StrategyEditorPlacementFootprint(placement) {
    global LabEditorDoc
    tower := LabEditorDoc.TowerNameForSlot(placement.slot)
    return tower != "" ? LabTowerPlacementFootprint(tower) : 1.5
}

StrategyEditorFootprintDiameter(placement) {
    global LabEditorViewport
    footprint := StrategyEditorPlacementFootprint(placement)
    ; Average footprint 1.5 is 28px at 100%. Zoom scales the guide with the map.
    diameter := Round(28 * (footprint / 1.5) * LabEditorViewport.Zoom)
    return Max(18, Min(150, diameter))
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
        return "Rings: 1"
    if (LabEditorRingMode = "off")
        return "Rings: Off"
    return "Rings: All"
}

StrategyEditorToggleRings(*) {
    global LabEditorRingMode, LabEditorRingsBtn
    LabEditorRingMode := LabEditorRingMode = "all" ? "selected" : (LabEditorRingMode = "selected" ? "off" : "all")
    if IsObject(LabEditorRingsBtn)
        LabEditorRingsBtn.Text := StrategyEditorRingButtonText()
    StrategyEditorApplyLayer()
    label := LabEditorRingMode = "all" ? "all tower footprints" : (LabEditorRingMode = "selected" ? "selected tower footprint" : "tower footprint rings hidden")
    StrategyEditorSetStatus("Placement guides: " label ".")
}

StrategyEditorBuildMarkers() {
    global LabEditorDoc, LabEditorMarkerCtrls, LabEditorMarkerByHwnd, MainGui

    StrategyEditorClearMarkers()
    LabEditorMarkerCtrls := []
    LabEditorMarkerByHwnd := Map()
    ringPath := StrategyEditorRingImagePath()

    colors := ["B04747", "476FB0", "4A8F59", "9C6CB0", "B08A47"]
    for index, placement in LabEditorDoc.Placements {
        point := StrategyEditorPlacementPoint(placement)
        slotNum := IsNumber(placement.slot) ? Integer(placement.slot) : 1
        color := colors[Max(1, Min(colors.Length, slotNum))]
        ring := ""
        if (ringPath != "") {
            diameter := StrategyEditorFootprintDiameter(placement)
            ring := MainGui.Add("Picture", "x" (point.x - Floor(diameter / 2)) " y" (point.y - Floor(diameter / 2))
                " w" diameter " h" diameter " Hidden Disabled BackgroundTrans", ringPath)
        }
        marker := MainGui.Add("Text", "x" (point.x - 9) " y" (point.y - 9)
            " w18 h18 Hidden Center Background" color " cFFFFFF", StrategyEditorMarkerLabel(placement))
        marker.SetFont("s7 w700", "Segoe UI")
        StrategyEditorSetCircularRegion(marker, 18)
        marker.OnEvent("Click", StrategyEditorMarkerClicked.Bind(index))
        entry := {ctrl: marker, ring: ring, placement: placement, index: index, color: color}
        LabEditorMarkerCtrls.Push(entry)
        LabEditorMarkerByHwnd[marker.Hwnd] := entry
    }

    ; Rings are created before/among markers. Raise all marker HWNDs once so labels
    ; always remain readable even where multiple footprint guides overlap.
    for entry in LabEditorMarkerCtrls {
        try DllCall("user32\SetWindowPos", "Ptr", entry.ctrl.Hwnd, "Ptr", 0,
            "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    }

    StrategyEditorRefreshLayerList()
    StrategyEditorRefreshMarkerSelection()
    StrategyEditorApplyLayer()
}

StrategyEditorClearMarkers() {
    global LabEditorMarkerCtrls, LabEditorMarkerByHwnd, LabEditorListRowMap
    for entry in LabEditorMarkerCtrls {
        if IsObject(entry.ring) {
            try entry.ring.Visible := false
            try DllCall("DestroyWindow", "Ptr", entry.ring.Hwnd)
        }
        try entry.ctrl.Visible := false
        try DllCall("DestroyWindow", "Ptr", entry.ctrl.Hwnd)
    }
    LabEditorMarkerCtrls := []
    LabEditorMarkerByHwnd := Map()
    LabEditorListRowMap := []
}

StrategyEditorRefreshMarkerSelection() {
    global LabEditorMarkerCtrls, LabEditorSelectedRow
    for index, entry in LabEditorMarkerCtrls {
        point := StrategyEditorPlacementPoint(entry.placement)
        size := index = LabEditorSelectedRow ? 22 : 18
        entry.ctrl.Move(point.x - Floor(size / 2), point.y - Floor(size / 2), size, size)
        StrategyEditorSetCircularRegion(entry.ctrl, size)
        entry.ctrl.SetFont(index = LabEditorSelectedRow ? "s8 w700" : "s7 w700", "Segoe UI")
        if IsObject(entry.ring) {
            diameter := StrategyEditorFootprintDiameter(entry.placement)
            entry.ring.Move(point.x - Floor(diameter / 2), point.y - Floor(diameter / 2), diameter, diameter)
        }
    }
}

StrategyEditorRefreshMarkerLayout() {
    StrategyEditorRefreshMarkerSelection()
    StrategyEditorApplyLayer()
}

StrategyEditorRefreshLayerList(selectDocIndex := 0) {
    global LabEditorDoc, LabEditorList, LabEditorListRowMap, LabEditorSelectedRow
    if !IsObject(LabEditorDoc)
        return

    if (selectDocIndex <= 0)
        selectDocIndex := LabEditorSelectedRow

    LabEditorList.Delete()
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
    global LabEditorDoc, LabEditorMarkerCtrls
    if !IsObject(LabEditorDoc)
        return

    for index, placement in LabEditorDoc.Placements {
        if (index > LabEditorMarkerCtrls.Length)
            continue
        entry := LabEditorMarkerCtrls[index]
        entry.placement := placement
        entry.index := index
    }
    if rebuildList
        StrategyEditorRefreshLayerList()
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
        showPlacement := (CurrentTab = "Tab7") && point.visible && StrategyEditorPlacementVisible(entry.placement)
        entry.ctrl.Visible := showPlacement
        if IsObject(entry.ring)
            entry.ring.Visible := showPlacement && StrategyEditorRingModeAllows(entry.index)
    }
}

StrategyEditorLayerChanged(*) {
    global LabEditorLayerCtrl, LabEditorLayer, LabEditorLayerOptions, LabEditorDoc, LabEditorSelectedRow
    global LabEditorListRowMap
    if !IsObject(LabEditorDoc)
        return

    choice := LabEditorLayerCtrl.Value
    if (choice < 1 || choice > LabEditorLayerOptions.Length)
        choice := 1
    LabEditorLayer := LabEditorLayerOptions[choice]

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

    if !selectedStillVisible && firstVisible
        LabEditorSelectedRow := firstVisible

    StrategyEditorRefreshLayerList(LabEditorSelectedRow)
    StrategyEditorRefreshMarkerLayout()
    if LabEditorSelectedRow > 0
        StrategyEditorSelectPlacement(LabEditorSelectedRow)

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
    LabEditorXCtrl.Text := placement.x
    LabEditorYCtrl.Text := placement.y
    StrategyEditorShowTower(placement)
    StrategyEditorRefreshMarkerSelection()
    StrategyEditorApplyLayer()
    visibleRow := StrategyEditorVisibleListRow(row)
    if visibleRow > 0
        try LabEditorList.Modify(visibleRow, "Vis Select Focus")
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
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragMarker, LabEditorDragRing
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragLastFrame, LabEditorDragLastStatus, LabEditorDragPreviewX, LabEditorDragPreviewY
    global LabEditorXCtrl, LabEditorYCtrl

    if !IsObject(LabEditorDoc) || !IsObject(LabEditorDragPlacement) || !IsObject(LabEditorDragMarker)
        return

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

    LabEditorDragMarker.Move(mx - 11, my - 11, 22, 22)
    StrategyEditorSetCircularRegion(LabEditorDragMarker, 22)
    if IsObject(LabEditorDragRing) {
        diameter := StrategyEditorFootprintDiameter(LabEditorDragPlacement)
        LabEditorDragRing.Move(mx - Floor(diameter / 2), my - Floor(diameter / 2), diameter, diameter)
    }

    if (!LabEditorDragLastStatus || now - LabEditorDragLastStatus >= 75) {
        LabEditorDragLastStatus := now
        try LabEditorXCtrl.Text := LabEditorDragPreviewX
        try LabEditorYCtrl.Text := LabEditorDragPreviewY
        StrategyEditorSetStatus("Preview " LabEditorDragPlacement.towerId " → (" LabEditorDragPreviewX ", " LabEditorDragPreviewY ")")
    }
    return 0
}

StrategyEditorMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragMarker, LabEditorDragRing
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragLastFrame, LabEditorDragLastStatus, LabEditorDragPreviewX, LabEditorDragPreviewY

    if !IsObject(LabEditorDoc) || !IsObject(LabEditorDragPlacement) || !IsObject(LabEditorDragMarker)
        return

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
    LabEditorDragRing := ""
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
