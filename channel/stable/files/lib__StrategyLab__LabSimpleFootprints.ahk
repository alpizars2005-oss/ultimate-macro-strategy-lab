#Requires AutoHotkey v2.0

; 0.3.9 marker portrait helper.
; Footprint rendering now lives entirely in StrategyEditorPlacements. This module has
; exactly one job: if a placement-limit-1 tower has a real cached portrait, replace the
; existing text marker HWND with one Picture HWND. It never creates a second marker,
; never touches ring geometry and never changes layer state.

global LabSimpleFootprintsTickMs := 750

LabSimpleFootprintsPortraitFor(entry) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc) || !IsObject(entry)
        return ""

    towerName := LabEditorDoc.TowerNameForSlot(entry.placement.slot)
    if (towerName = "")
        return ""

    tower := LabTowerResolve(towerName)
    if (tower.placementLimit != 1)
        return ""

    cached := LabTowerCachedPortraitPath(towerName)
    if (cached = "")
        return ""

    preview := LabTowerPreparePreview(cached, tower.key)
    return preview != "" ? preview : cached
}

LabSimpleFootprintsUpgradeUniqueMarker(index, entry) {
    global MainGui, LabEditorDoc, LabEditorMarkerByHwnd, LabEditorSelectedRow

    if !IsObject(LabEditorDoc) || !IsObject(entry) || !IsObject(entry.ctrl)
        return false

    ready := false
    try ready := entry.labUniquePortraitReady
    if ready
        return false

    notApplicable := false
    try notApplicable := entry.labUniquePortraitNotApplicable
    if notApplicable
        return false

    towerName := LabEditorDoc.TowerNameForSlot(entry.placement.slot)
    if (towerName = "")
        return false

    tower := LabTowerResolve(towerName)
    if (tower.placementLimit != 1) {
        entry.labUniquePortraitNotApplicable := true
        return false
    }

    portrait := LabSimpleFootprintsPortraitFor(entry)
    if (portrait = "")
        return false

    point := StrategyEditorPlacementPoint(entry.placement)
    size := index = LabEditorSelectedRow ? 22 : 18
    wasVisible := false
    oldHwnd := 0
    try wasVisible := entry.ctrl.Visible
    try oldHwnd := entry.ctrl.Hwnd

    marker := ""
    try {
        marker := MainGui.Add("Picture",
            "x" (point.x - Floor(size / 2)) " y" (point.y - Floor(size / 2))
            " w" size " h" size " Hidden BackgroundTrans", portrait)
        StrategyEditorSetCircularRegion(marker, size)
        marker.OnEvent("Click", StrategyEditorMarkerClicked.Bind(index))
    } catch {
        if IsObject(marker) {
            try marker.Visible := false
            try DllCall("DestroyWindow", "Ptr", marker.Hwnd)
        }
        return false
    }

    ; Replace, never stack. Update hit testing before destroying the old HWND.
    if oldHwnd
        try LabEditorMarkerByHwnd.Delete(oldHwnd)
    try entry.ctrl.Visible := false
    if oldHwnd
        try DllCall("DestroyWindow", "Ptr", oldHwnd)

    entry.ctrl := marker
    entry.labUniquePortraitReady := true
    LabEditorMarkerByHwnd[marker.Hwnd] := entry
    marker.Visible := wasVisible
    return true
}

LabSimpleFootprintsApply(*) {
    global LabEditorDoc, LabEditorMarkerCtrls

    if !IsObject(LabEditorDoc) || !IsObject(LabEditorMarkerCtrls)
        return

    changed := false
    for index, entry in LabEditorMarkerCtrls {
        if LabSimpleFootprintsUpgradeUniqueMarker(index, entry)
            changed := true
    }

    if changed {
        try StrategyEditorRefreshMarkerSelection()
        try StrategyEditorApplyLayer()
    }
}

; Lazy cached portraits are cosmetic. A failed/missing Wiki asset never blocks Editor.
SetTimer(LabSimpleFootprintsApply, LabSimpleFootprintsTickMs)
