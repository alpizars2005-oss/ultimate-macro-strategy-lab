#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "StrategyEditorCore.ahk"

; Standalone proof of concept. No strategy text is executed.

global BaseW := 1920
global BaseH := 1080
global CanvasX := 20
global CanvasY := 92
global CanvasW := 960
global CanvasH := 540

global EditorDoc := ""
global MarkerByHwnd := Map()
global MarkerControls := [] ; [{ctrl, placement, index}]
global DragPlacement := ""
global DragMarker := ""
global LayerValue := "All placements"

global G := Gui("+Resize", "Ultimate Macro — Visual Strategy Editor Lab")
G.BackColor := "171717"
G.SetFont("s9 cFFFFFF", "Segoe UI")

global OpenBtn := G.Add("Button", "x20 y18 w120 h30", "Open .strat")
global SnapshotBtn := G.Add("Button", "x150 y18 w135 h30", "Load snapshot")
global SaveCopyBtn := G.Add("Button", "x295 y18 w120 h30", "Save Copy")
global OverwriteBtn := G.Add("Button", "x425 y18 w155 h30", "Overwrite + Backup")
global LayerLabel := G.Add("Text", "x610 y24 w45 h20", "Layer:")
global LayerCtrl := G.Add("DropDownList", "x655 y19 w325", ["All placements"])
global StatusCtrl := G.Add("Text", "x20 y58 w960 h24", "Open a strategy to begin.")

global CanvasBg := G.Add("Text", "x" CanvasX " y" CanvasY " w" CanvasW " h" CanvasH " +Border Background242424")
global SnapshotPicture := G.Add("Picture", "x" CanvasX " y" CanvasY " w" CanvasW " h" CanvasH " Hidden")

global PlacementList := G.Add("ListView", "x1000 y92 w340 h540 Grid -Multi", ["#", "ID", "Slot / tower", "X", "Y"])
PlacementList.ModifyCol(1, 35)
PlacementList.ModifyCol(2, 80)
PlacementList.ModifyCol(3, 120)
PlacementList.ModifyCol(4, 45)
PlacementList.ModifyCol(5, 45)

global HelpCtrl := G.Add("Text", "x1000 y18 w340 h62", "Drag any visible marker. Coordinates are scaled back to the macro's 1920×1080 recording plane. Save Copy is the safest default.")

OpenBtn.OnEvent("Click", OpenStrategy)
SnapshotBtn.OnEvent("Click", LoadSnapshot)
SaveCopyBtn.OnEvent("Click", SaveCopy)
OverwriteBtn.OnEvent("Click", OverwriteStrategy)
LayerCtrl.OnEvent("Change", ChangeLayer)
PlacementList.OnEvent("ItemFocus", FocusPlacement)
G.OnEvent("Close", (*) => ExitApp())

OnMessage(0x0201, MarkerMouseDown) ; WM_LBUTTONDOWN
OnMessage(0x0200, MarkerMouseMove) ; WM_MOUSEMOVE
OnMessage(0x0202, MarkerMouseUp)   ; WM_LBUTTONUP

G.Show("w1360 h660")

OpenStrategy(*) {
    global EditorDoc, StatusCtrl
    path := FileSelect(1, , "Open Ultimate Macro strategy", "Strategy (*.strat)")
    if (path = "")
        return
    try {
        EditorDoc := StratDocument(path)
        if (EditorDoc.Placements.Length = 0)
            throw Error("No supported SpawnTower placements were found in [Steps].")
        BuildLayers()
        BuildPlacementControls()
        ApplyLayerVisibility()
        StatusCtrl.Text := "Loaded " EditorDoc.Placements.Length " placements — " path
    } catch Error as err {
        EditorDoc := ""
        HideMarkers()
        StatusCtrl.Text := "Load failed: " err.Message
    }
}

LoadSnapshot(*) {
    global SnapshotPicture, CanvasBg, StatusCtrl
    path := FileSelect(1, , "Choose a Roblox/TDS reference screenshot", "Images (*.png; *.jpg; *.jpeg; *.bmp)")
    if (path = "")
        return
    SnapshotPicture.Value := path
    SnapshotPicture.Visible := true
    CanvasBg.Visible := false
    StatusCtrl.Text := "Snapshot loaded. Marker coordinates still use the 1920×1080 macro plane."
    ApplyLayerVisibility()
}

BuildLayers() {
    global EditorDoc, LayerCtrl, LayerValue
    options := ["All placements"]
    seen := Map()
    for placement in EditorDoc.Placements {
        slot := String(placement.slot)
        name := EditorDoc.TowerNameForSlot(slot)
        label := "Slot " slot (name != "" ? " — " name : "")
        key := StrLower(label)
        if !seen.Has(key) {
            seen[key] := true
            options.Push(label)
        }
    }
    LayerCtrl.Delete()
    LayerCtrl.Add(options)
    LayerCtrl.Choose(1)
    LayerValue := "All placements"
}

ChangeLayer(*) {
    global LayerCtrl, LayerValue
    LayerValue := LayerCtrl.Text
    ApplyLayerVisibility()
}

PlacementVisible(placement) {
    global LayerValue, EditorDoc
    if (LayerValue = "All placements")
        return true
    slot := String(placement.slot)
    tower := EditorDoc.TowerNameForSlot(slot)
    return LayerValue = "Slot " slot (tower != "" ? " — " tower : "")
}

BuildPlacementControls() {
    global EditorDoc, PlacementList, MarkerControls, MarkerByHwnd
    if !IsObject(EditorDoc)
        return
    HideMarkers()
    PlacementList.Delete()
    MarkerByHwnd := Map()
    MarkerControls := []
    for index, placement in EditorDoc.Placements {
        tower := EditorDoc.TowerNameForSlot(placement.slot)
        slotLabel := placement.slot (tower != "" ? " / " tower : "")
        PlacementList.Add(, index, placement.towerId, slotLabel, placement.x, placement.y)
        cx := CanvasX + Round((placement.x / BaseW) * CanvasW)
        cy := CanvasY + Round((placement.y / BaseH) * CanvasH)
        cx := Max(CanvasX + 9, Min(CanvasX + CanvasW - 9, cx))
        cy := Max(CanvasY + 9, Min(CanvasY + CanvasH - 9, cy))
        marker := G.Add("Text", "x" (cx - 9) " y" (cy - 9) " w18 h18 Center +Border BackgroundD84A4A cFFFFFF", index)
        marker.SetFont("s7 w700", "Segoe UI")
        entry := {ctrl: marker, placement: placement, index: index}
        MarkerControls.Push(entry)
        MarkerByHwnd[marker.Hwnd] := entry
    }
}

HideMarkers() {
    global MarkerControls
    for entry in MarkerControls {
        try entry.ctrl.Visible := false
    }
}

ApplyLayerVisibility() {
    global MarkerControls
    for entry in MarkerControls
        entry.ctrl.Visible := PlacementVisible(entry.placement)
}

UpdatePlacementRow(placement) {
    global EditorDoc, PlacementList
    for index, candidate in EditorDoc.Placements {
        if (candidate = placement) {
            tower := EditorDoc.TowerNameForSlot(candidate.slot)
            slotLabel := candidate.slot (tower != "" ? " / " tower : "")
            PlacementList.Modify(index, , index, candidate.towerId, slotLabel, candidate.x, candidate.y)
            return
        }
    }
}

MarkerMouseDown(wParam, lParam, msg, hwnd) {
    global MarkerByHwnd, DragPlacement, DragMarker
    if !MarkerByHwnd.Has(hwnd)
        return
    entry := MarkerByHwnd[hwnd]
    DragPlacement := entry.placement
    DragMarker := entry.ctrl
    DllCall("SetCapture", "Ptr", G.Hwnd)
    return 0
}

MarkerMouseMove(wParam, lParam, msg, hwnd) {
    global DragPlacement, DragMarker, StatusCtrl
    if !IsObject(DragPlacement) || !IsObject(DragMarker)
        return
    GetClientMouse(&mx, &my)
    mx := Max(CanvasX, Min(CanvasX + CanvasW, mx))
    my := Max(CanvasY, Min(CanvasY + CanvasH, my))
    newX := Round(((mx - CanvasX) / CanvasW) * BaseW)
    newY := Round(((my - CanvasY) / CanvasH) * BaseH)
    newX := Max(0, Min(BaseW, newX))
    newY := Max(0, Min(BaseH, newY))
    DragMarker.Move(mx - 9, my - 9)
    StatusCtrl.Text := "Preview: " DragPlacement.towerId " → (" newX ", " newY ")"
    return 0
}

MarkerMouseUp(wParam, lParam, msg, hwnd) {
    global DragPlacement, DragMarker, EditorDoc, StatusCtrl
    if !IsObject(DragPlacement) || !IsObject(DragMarker)
        return
    GetClientMouse(&mx, &my)
    mx := Max(CanvasX, Min(CanvasX + CanvasW, mx))
    my := Max(CanvasY, Min(CanvasY + CanvasH, my))
    newX := Max(0, Min(BaseW, Round(((mx - CanvasX) / CanvasW) * BaseW)))
    newY := Max(0, Min(BaseH, Round(((my - CanvasY) / CanvasH) * BaseH)))
    try {
        EditorDoc.UpdatePlacement(DragPlacement, newX, newY)
        StatusCtrl.Text := "Updated " DragPlacement.towerId " to (" newX ", " newY "). Nothing has been saved yet."
    } catch Error as err {
        StatusCtrl.Text := "Edit failed: " err.Message
    }
    DllCall("ReleaseCapture")
    editedPlacement := DragPlacement
    DragPlacement := ""
    DragMarker := ""
    UpdatePlacementRow(editedPlacement)
    ApplyLayerVisibility()
    return 0
}

GetClientMouse(&x, &y) {
    MouseGetPos(&sx, &sy)
    pt := Buffer(8, 0)
    NumPut("Int", sx, pt, 0)
    NumPut("Int", sy, pt, 4)
    DllCall("ScreenToClient", "Ptr", G.Hwnd, "Ptr", pt)
    x := NumGet(pt, 0, "Int")
    y := NumGet(pt, 4, "Int")
}

FocusPlacement(ctrl, row) {
    global EditorDoc, LayerCtrl, LayerValue
    if !IsObject(EditorDoc) || row < 1 || row > EditorDoc.Placements.Length
        return
    placement := EditorDoc.Placements[row]
    tower := EditorDoc.TowerNameForSlot(placement.slot)
    wanted := "Slot " placement.slot (tower != "" ? " — " tower : "")
    if (LayerValue != "All placements" && LayerValue != wanted) {
        ; Keep the user's current layer; list selection still provides coordinates.
        return
    }
}

SaveCopy(*) {
    global EditorDoc, StatusCtrl
    if !IsObject(EditorDoc) {
        StatusCtrl.Text := "Open a strategy first."
        return
    }
    SplitPath(EditorDoc.Path, &name, &dir, &ext, &nameNoExt)
    suggested := dir "\\" nameNoExt "_edited.strat"
    path := FileSelect("S16", suggested, "Save edited strategy copy", "Strategy (*.strat)")
    if (path = "")
        return
    if !RegExMatch(path, "i)\.strat$")
        path .= ".strat"
    try {
        EditorDoc.SaveCopy(path)
        StatusCtrl.Text := "Saved copy: " path
    } catch Error as err {
        StatusCtrl.Text := "Save failed: " err.Message
    }
}

OverwriteStrategy(*) {
    global EditorDoc, StatusCtrl
    if !IsObject(EditorDoc) {
        StatusCtrl.Text := "Open a strategy first."
        return
    }
    answer := MsgBox("Overwrite the original strategy? A timestamped backup will be created first.", "Strategy Editor", "YesNo Icon!")
    if (answer != "Yes")
        return
    try {
        backup := EditorDoc.OverwriteWithBackup()
        StatusCtrl.Text := "Original updated. Backup: " backup
    } catch Error as err {
        StatusCtrl.Text := "Overwrite failed: " err.Message
    }
}
