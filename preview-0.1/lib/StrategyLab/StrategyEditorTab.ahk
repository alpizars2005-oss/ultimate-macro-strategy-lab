#Requires AutoHotkey v2.0

; Integrated Strategy Editor tab for Main_Lab.ahk.

global LabEditorCtrls := []
global LabEditorMarkerCtrls := []
global LabEditorMarkerByHwnd := Map()
global LabEditorDoc := ""
global LabEditorLayer := "All placements"
global LabEditorSelectedRow := 0
global LabEditorDragPlacement := ""
global LabEditorDragMarker := ""
global LabEditorDragOldX := 0
global LabEditorDragOldY := 0

global LabEditorCanvasX := 30
global LabEditorCanvasY := 180
global LabEditorCanvasW := 420
global LabEditorCanvasH := 236

OnMessage(0x0200, StrategyEditorMouseMove)
OnMessage(0x0202, StrategyEditorMouseUp)

StrategyEditorCreateTab(gui) {
    global LabEditorCtrls
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorOpenBtn, LabEditorCurrentBtn, LabEditorSnapshotBtn, LabEditorCaptureBtn
    global LabEditorUndoBtn, LabEditorRedoBtn, LabEditorLayerCtrl, LabEditorCanvasBg, LabEditorSnapshot
    global LabEditorList, LabEditorXCtrl, LabEditorYCtrl, LabEditorApplyBtn, LabEditorSaveBtn
    global LabEditorOverwriteBtn, LabEditorStatus, LabEditorDirty

    gui.SetFont("s10 w600 c3A86FF", "Segoe UI")
    title := gui.Add("Text", "x30 y95 w300 h22 Hidden", "Visual Strategy Editor")
    line := gui.Add("Progress", "x30 y118 w640 h1 Hidden Background333333", 0)

    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabEditorOpenBtn := gui.Add("Button", "x30 y128 w76 h28 Hidden", "Open")
    LabEditorCurrentBtn := gui.Add("Button", "x111 y128 w88 h28 Hidden", "Use Current")
    LabEditorSnapshotBtn := gui.Add("Button", "x204 y128 w82 h28 Hidden", "Snapshot")
    LabEditorCaptureBtn := gui.Add("Button", "x291 y128 w82 h28 Hidden", "Capture")
    LabEditorUndoBtn := gui.Add("Button", "x378 y128 w58 h28 Hidden", "Undo")
    LabEditorRedoBtn := gui.Add("Button", "x441 y128 w58 h28 Hidden", "Redo")

    gui.SetFont("s8 w400 cAAAAAA", "Segoe UI")
    layerLabel := gui.Add("Text", "x510 y133 w38 h20 Hidden", "Layer")
    gui.SetFont("s8 w400 c000000", "Segoe UI")
    LabEditorLayerCtrl := gui.Add("DropDownList", "x548 y128 w122 Hidden", ["All placements"])

    LabEditorCanvasBg := gui.Add("Text", "x" LabEditorCanvasX " y" LabEditorCanvasY
        " w" LabEditorCanvasW " h" LabEditorCanvasH " Hidden +Border Background242424")
    LabEditorSnapshot := gui.Add("Picture", "x" LabEditorCanvasX " y" LabEditorCanvasY
        " w" LabEditorCanvasW " h" LabEditorCanvasH " Hidden")

    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabEditorList := gui.Add("ListView", "x465 y180 w205 h236 Hidden Grid -Multi", ["#", "ID", "Slot", "X", "Y"])
    LabEditorList.ModifyCol(1, 27)
    LabEditorList.ModifyCol(2, 55)
    LabEditorList.ModifyCol(3, 42)
    LabEditorList.ModifyCol(4, 36)
    LabEditorList.ModifyCol(5, 36)

    gui.SetFont("s8 w400 cAAAAAA", "Segoe UI")
    coordLabel := gui.Add("Text", "x30 y425 w150 h20 Hidden", "Selected coordinates:")
    dirtyLabel := gui.Add("Text", "x465 y425 w205 h20 Hidden", "Changes are in-memory until saved.")

    gui.SetFont("s8 w400 c000000", "Segoe UI")
    LabEditorXCtrl := gui.Add("Edit", "x155 y422 w60 h22 Hidden Number")
    LabEditorYCtrl := gui.Add("Edit", "x220 y422 w60 h22 Hidden Number")
    LabEditorApplyBtn := gui.Add("Button", "x285 y420 w78 h26 Hidden", "Apply X/Y")

    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabEditorSaveBtn := gui.Add("Button", "x370 y420 w80 h26 Hidden", "Save Copy")
    LabEditorOverwriteBtn := gui.Add("Button", "x465 y450 w205 h28 Hidden", "Overwrite + automatic backup")
    LabEditorDirty := gui.Add("Text", "x30 y452 w420 h18 Hidden cAAAAAA", "No strategy loaded.")
    LabEditorStatus := gui.Add("Text", "x30 y478 w640 h50 Hidden cAAAAAA", "Open a .strat or use the current Strategy 1.")

    LabEditorOpenBtn.OnEvent("Click", StrategyEditorOpen)
    LabEditorCurrentBtn.OnEvent("Click", StrategyEditorUseCurrent)
    LabEditorSnapshotBtn.OnEvent("Click", StrategyEditorLoadSnapshot)
    LabEditorCaptureBtn.OnEvent("Click", StrategyEditorCaptureRoblox)
    LabEditorUndoBtn.OnEvent("Click", StrategyEditorUndo)
    LabEditorRedoBtn.OnEvent("Click", StrategyEditorRedo)
    LabEditorLayerCtrl.OnEvent("Change", StrategyEditorLayerChanged)
    LabEditorList.OnEvent("ItemSelect", StrategyEditorRowSelected)
    LabEditorApplyBtn.OnEvent("Click", StrategyEditorApplyCoordinates)
    LabEditorSaveBtn.OnEvent("Click", StrategyEditorSaveCopy)
    LabEditorOverwriteBtn.OnEvent("Click", StrategyEditorOverwrite)

    LabEditorCtrls := [
        title, line, LabEditorOpenBtn, LabEditorCurrentBtn, LabEditorSnapshotBtn, LabEditorCaptureBtn,
        LabEditorUndoBtn, LabEditorRedoBtn, layerLabel, LabEditorLayerCtrl, LabEditorCanvasBg,
        LabEditorSnapshot, LabEditorList, coordLabel, dirtyLabel, LabEditorXCtrl, LabEditorYCtrl,
        LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus
    ]
    return LabEditorCtrls
}

StrategyEditorShow() {
    global LabEditorCtrls, LabEditorDoc, LabEditorCanvasBg, LabEditorSnapshot
    for ctrl in LabEditorCtrls
        ctrl.Visible := true
    if (LabEditorSnapshot.Value != "")
        LabEditorCanvasBg.Visible := false
    StrategyEditorApplyLayer()
    StrategyEditorRefreshButtons()
}

StrategyEditorTryBeginDrag(hwnd) {
    global LabEditorMarkerByHwnd, LabEditorDragPlacement, LabEditorDragMarker
    global LabEditorDragOldX, LabEditorDragOldY, MainGui
    if !LabEditorMarkerByHwnd.Has(hwnd)
        return false

    entry := LabEditorMarkerByHwnd[hwnd]
    LabEditorDragPlacement := entry.placement
    LabEditorDragMarker := entry.ctrl
    LabEditorDragOldX := entry.placement.x
    LabEditorDragOldY := entry.placement.y
    StrategyEditorSelectPlacement(entry.index)
    DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return true
}

StrategyEditorOpen(*) {
    path := FileSelect(1, , "Open Ultimate Macro strategy", "Strategy (*.strat)")
    if (path != "")
        StrategyEditorLoadPath(path)
}

StrategyEditorUseCurrent(*) {
    global Strategy1Ctrl, Strategy1Path
    path := ""
    try path := Trim(Strategy1Ctrl.Text)
    if (path = "")
        path := Strategy1Path
    if (path = "" || !FileExist(path)) {
        StrategyEditorSetStatus("Strategy 1 is empty or the file no longer exists.", true)
        return
    }
    StrategyEditorLoadPath(path)
}

StrategyEditorLoadPath(path) {
    global LabEditorDoc, LabEditorLayer, LabEditorSelectedRow
    try {
        LabEditorDoc := LabStratDocument(path)
        if (LabEditorDoc.Placements.Length = 0)
            throw Error("No SpawnTower placements were found in [Steps].")
        LabEditorLayer := "All placements"
        LabEditorSelectedRow := 0
        StrategyEditorBuildLayers()
        StrategyEditorBuildMarkers()
        StrategyEditorSetStatus("Loaded " LabEditorDoc.Placements.Length " placements from " path)
        StrategyEditorRefreshButtons()
        StrategyEditorRefreshDirty()
    } catch Error as err {
        LabEditorDoc := ""
        StrategyEditorClearMarkers()
        StrategyEditorSetStatus("Could not load strategy: " err.Message, true)
    }
}

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

StrategyEditorBuildMarkers() {
    global LabEditorDoc, LabEditorList, LabEditorMarkerCtrls, LabEditorMarkerByHwnd, MainGui
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH

    StrategyEditorClearMarkers()
    LabEditorList.Delete()
    LabEditorMarkerCtrls := []
    LabEditorMarkerByHwnd := Map()

    colors := ["B04747", "476FB0", "4A8F59", "9C6CB0", "B08A47"]
    for index, placement in LabEditorDoc.Placements {
        tower := LabEditorDoc.TowerNameForSlot(placement.slot)
        LabEditorList.Add(, index, placement.towerId, placement.slot, placement.x, placement.y)

        px := LabEditorCanvasX + Round((placement.x / LabEditorDoc.StrategyWidth) * LabEditorCanvasW)
        py := LabEditorCanvasY + Round((placement.y / LabEditorDoc.StrategyHeight) * LabEditorCanvasH)
        px := Max(LabEditorCanvasX + 8, Min(LabEditorCanvasX + LabEditorCanvasW - 8, px))
        py := Max(LabEditorCanvasY + 8, Min(LabEditorCanvasY + LabEditorCanvasH - 8, py))

        slotNum := IsNumber(placement.slot) ? Integer(placement.slot) : 1
        color := colors[Max(1, Min(colors.Length, slotNum))]
        marker := MainGui.Add("Text", "x" (px - 8) " y" (py - 8)
            " w16 h16 Hidden Center +Border Background" color " cFFFFFF", index)
        marker.SetFont("s6 w700", "Segoe UI")
        entry := {ctrl: marker, placement: placement, index: index}
        LabEditorMarkerCtrls.Push(entry)
        LabEditorMarkerByHwnd[marker.Hwnd] := entry
    }
    StrategyEditorApplyLayer()
}

StrategyEditorClearMarkers() {
    global LabEditorMarkerCtrls
    for entry in LabEditorMarkerCtrls {
        try entry.ctrl.Visible := false
        try entry.ctrl.Destroy()
    }
    LabEditorMarkerCtrls := []
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
    for entry in LabEditorMarkerCtrls
        entry.ctrl.Visible := (CurrentTab = "Tab7") && StrategyEditorPlacementVisible(entry.placement)
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
    StrategyEditorBuildMarkers()
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
        StrategyEditorBuildMarkers()
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
        StrategyEditorBuildMarkers()
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
    if !IsObject(LabEditorDoc) || !IsObject(LabEditorDragPlacement) || !IsObject(LabEditorDragMarker)
        return

    StrategyEditorGetClientCursor(&mx, &my)
    mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
    my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
    newX := Max(0, Min(LabEditorDoc.StrategyWidth,
        Round(((mx - LabEditorCanvasX) / LabEditorCanvasW) * LabEditorDoc.StrategyWidth)))
    newY := Max(0, Min(LabEditorDoc.StrategyHeight,
        Round(((my - LabEditorCanvasY) / LabEditorCanvasH) * LabEditorDoc.StrategyHeight)))
    LabEditorDragMarker.Move(mx - 8, my - 8)
    StrategyEditorSetStatus("Preview " LabEditorDragPlacement.towerId " -> (" newX ", " newY ")")
    return 0
}

StrategyEditorMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragMarker
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    if !IsObject(LabEditorDoc) || !IsObject(LabEditorDragPlacement) || !IsObject(LabEditorDragMarker)
        return

    StrategyEditorGetClientCursor(&mx, &my)
    mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
    my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
    newX := Max(0, Min(LabEditorDoc.StrategyWidth,
        Round(((mx - LabEditorCanvasX) / LabEditorCanvasW) * LabEditorDoc.StrategyWidth)))
    newY := Max(0, Min(LabEditorDoc.StrategyHeight,
        Round(((my - LabEditorCanvasY) / LabEditorCanvasH) * LabEditorDoc.StrategyHeight)))

    placement := LabEditorDragPlacement
    changed := LabEditorDoc.MovePlacement(placement, newX, newY)
    DllCall("ReleaseCapture")
    LabEditorDragPlacement := ""
    LabEditorDragMarker := ""

    row := StrategyEditorFindPlacementRow(placement)
    StrategyEditorBuildMarkers()
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

StrategyEditorLoadSnapshot(*) {
    global LabEditorSnapshot, LabEditorCanvasBg
    path := FileSelect(1, , "Choose Roblox/TDS screenshot", "Images (*.png; *.jpg; *.jpeg; *.bmp)")
    if (path = "")
        return
    LabEditorSnapshot.Value := path
    LabEditorSnapshot.Visible := true
    LabEditorCanvasBg.Visible := false
    StrategyEditorApplyLayer()
    StrategyEditorSetStatus("Reference snapshot loaded. Coordinates still use the strategy recording plane.")
}

StrategyEditorCaptureRoblox(*) {
    global LabEditorSnapshot, LabEditorCanvasBg
    if !WinExist("ahk_exe RobloxPlayerBeta.exe") {
        StrategyEditorSetStatus("Roblox is not running.", true)
        return
    }
    getRobloxPos(&pX, &pY, &w, &h)
    if (w < 100 || h < 100) {
        StrategyEditorSetStatus("Could not read the Roblox client area.", true)
        return
    }
    dir := A_AppData "\Ultimate_Macro\StrategyEditor"
    if !DirExist(dir)
        DirCreate(dir)
    path := dir "\last-capture.png"
    pBitmap := Gdip_BitmapFromScreen(pX "|" pY "|" w "|" h)
    if !pBitmap {
        StrategyEditorSetStatus("Could not capture Roblox.", true)
        return
    }
    try {
        Gdip_SaveBitmapToFile(pBitmap, path, 95)
        LabEditorSnapshot.Value := path
        LabEditorSnapshot.Visible := true
        LabEditorCanvasBg.Visible := false
        StrategyEditorApplyLayer()
        StrategyEditorSetStatus("Captured current Roblox client as the editor background.")
    } finally {
        Gdip_DisposeImage(pBitmap)
    }
}

StrategyEditorSaveCopy(*) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc) {
        StrategyEditorSetStatus("Open a strategy first.", true)
        return
    }
    SplitPath(LabEditorDoc.Path, &name, &dir, &ext, &nameNoExt)
    suggested := dir "\" nameNoExt "_edited.strat"
    path := FileSelect("S16", suggested, "Save edited strategy copy", "Strategy (*.strat)")
    if (path = "")
        return
    if !RegExMatch(path, "i)\.strat$")
        path .= ".strat"
    try {
        LabEditorDoc.SaveCopy(path)
        StrategyEditorSetStatus("Saved edited copy: " path)
    } catch Error as err {
        StrategyEditorSetStatus("Save failed: " err.Message, true)
    }
}

StrategyEditorOverwrite(*) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc) {
        StrategyEditorSetStatus("Open a strategy first.", true)
        return
    }
    answer := MsgBox(
        "Overwrite the original strategy?`n`nA timestamped .backup file will be created first.",
        "Strategy Lab", "YesNo Icon!"
    )
    if (answer != "Yes")
        return
    try {
        backup := LabEditorDoc.OverwriteWithBackup()
        StrategyEditorSetStatus("Original updated safely. Backup: " backup)
        StrategyEditorRefreshDirty()
    } catch Error as err {
        StrategyEditorSetStatus("Overwrite failed: " err.Message, true)
    }
}

StrategyEditorRefreshButtons() {
    global LabEditorDoc, LabEditorUndoBtn, LabEditorRedoBtn, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn
    loaded := IsObject(LabEditorDoc)
    LabEditorUndoBtn.Enabled := loaded && LabEditorDoc.CanUndo()
    LabEditorRedoBtn.Enabled := loaded && LabEditorDoc.CanRedo()
    LabEditorApplyBtn.Enabled := loaded
    LabEditorSaveBtn.Enabled := loaded
    LabEditorOverwriteBtn.Enabled := loaded
}

StrategyEditorRefreshDirty() {
    global LabEditorDoc, LabEditorDirty
    if !IsObject(LabEditorDoc) {
        LabEditorDirty.Text := "No strategy loaded."
        return
    }
    LabEditorDirty.Text := (LabEditorDoc.Dirty ? "UNSAVED CHANGES - " : "Saved state - ")
        . LabEditorDoc.StrategyWidth "x" LabEditorDoc.StrategyHeight
        . " - " LabEditorDoc.Placements.Length " placements"
}

StrategyEditorSetStatus(text, isError := false) {
    global LabEditorStatus
    LabEditorStatus.SetFont("c" (isError ? "FF7777" : "AAAAAA"))
    LabEditorStatus.Text := text
}
