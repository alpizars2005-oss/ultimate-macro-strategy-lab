#Requires AutoHotkey v2.0

; Stable placement presentation layer.
;
; Rules:
;   entry.ctrl = one small draggable marker HWND. Never resize it to footprint size.
;   entry.ring = one transparent outline HWND sized to the placement footprint.
;   unique placement-limit-1 towers may replace the text marker with ONE tiny portrait.
;
; This deliberately avoids stacking duplicate markers or creating live-game style cyan
; halos. The neutral outline is a tiny shipped asset and the default mode is Selected.

global LabSimpleFootprintsTickMs := 750
global LabSimpleFootprintsLastMode := ""
global LabSimpleFootprintGuidePath := A_ScriptDir "\Resources\StrategyLab\Towers\footprint-guide.png"

; Top-level assignment is global in AHK v2. StrategyEditorPlacements initializes this
; to "all" earlier in the include order; override it once here before a strategy loads.
LabEditorRingMode := "selected"

LabSimpleFootprintsInstallTemplate() {
    global LabEditorRingTemplatePath, LabSimpleFootprintGuidePath
    if FileExist(LabSimpleFootprintGuidePath)
        LabEditorRingTemplatePath := LabSimpleFootprintGuidePath
}

LabSimpleFootprintButtonText() {
    global LabEditorRingMode
    if (LabEditorRingMode = "selected")
        return "Footprint: 1"
    if (LabEditorRingMode = "off")
        return "Footprint: Off"
    return "Footprint: All"
}

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

    ; Never use the generic placeholder as an in-map marker. Wait for Sync Assets to
    ; cache the real tower art, then reuse the square preview already made for the
    ; selected-unit panel. That keeps these marker images tiny and local.
    cached := LabTowerCachedPortraitPath(towerName)
    if (cached = "")
        return ""

    preview := LabTowerPreparePreview(cached, tower.key)
    return preview != "" ? preview : cached
}

LabSimpleFootprintsUpgradeUniqueMarker(index, entry) {
    global MainGui, LabEditorDoc, LabEditorMarkerByHwnd, LabEditorSelectedRow

    if !IsObject(LabEditorDoc) || !IsObject(entry)
        return false

    ready := false
    try ready := entry.labUniquePortraitReady
    if ready
        return false

    checkedNonUnique := false
    try checkedNonUnique := entry.labUniquePortraitNotApplicable
    if checkedNonUnique
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

    if !IsObject(entry.ctrl) || !IsObject(MainGui)
        return false

    point := StrategyEditorPlacementPoint(entry.placement)
    ; Slightly larger than numbered badges so the cached portrait is actually useful,
    ; while still staying far smaller than any footprint guide.
    size := index = LabEditorSelectedRow ? 30 : 24
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

    ; Replace, never stack. entry.ctrl remains the single authoritative marker HWND
    ; used by click/drag hit-testing.
    try entry.ctrl.Visible := false
    if oldHwnd {
        try LabEditorMarkerByHwnd.Delete(oldHwnd)
        try DllCall("DestroyWindow", "Ptr", oldHwnd)
    }

    entry.ctrl := marker
    entry.labUniquePortraitReady := true
    LabEditorMarkerByHwnd[marker.Hwnd] := entry
    marker.Visible := wasVisible
    return true
}

LabSimpleFootprintsStyleEntry(entry) {
    global LabSimpleFootprintGuidePath
    if !IsObject(entry)
        return

    guideReady := false
    try guideReady := entry.labFootprintGuideReady
    if !guideReady && IsObject(entry.ring) && FileExist(LabSimpleFootprintGuidePath) {
        try {
            ; Replace the old cyan GDI template in-place. The ring remains the same HWND,
            ; so drag/zoom never creates another layer on top of the existing guide.
            entry.ring.Value := LabSimpleFootprintGuidePath
            entry.labFootprintGuideReady := true
        }
    }
}

LabSimpleFootprintsKeepUniqueMarkerSize(index, entry) {
    global LabEditorSelectedRow
    ready := false
    try ready := entry.labUniquePortraitReady
    if !ready || !IsObject(entry.ctrl)
        return

    point := StrategyEditorPlacementPoint(entry.placement)
    size := index = LabEditorSelectedRow ? 30 : 24
    try entry.ctrl.Move(point.x - Floor(size / 2), point.y - Floor(size / 2), size, size)
    try StrategyEditorSetCircularRegion(entry.ctrl, size)
}

LabSimpleFootprintsApply(*) {
    global LabEditorDoc, LabEditorMarkerCtrls, LabEditorRingsBtn
    global LabEditorRingMode, LabSimpleFootprintsLastMode

    if !IsObject(LabEditorDoc) || !IsObject(LabEditorMarkerCtrls)
        return

    changedMarker := false
    for index, entry in LabEditorMarkerCtrls {
        if !IsObject(entry)
            continue
        LabSimpleFootprintsStyleEntry(entry)
        if LabSimpleFootprintsUpgradeUniqueMarker(index, entry)
            changedMarker := true
        LabSimpleFootprintsKeepUniqueMarkerSize(index, entry)
    }

    if changedMarker {
        ; One synchronization pass after an HWND replacement. No per-frame rebuilds.
        try StrategyEditorApplyLayer()
    }

    if (LabSimpleFootprintsLastMode != LabEditorRingMode) {
        LabSimpleFootprintsLastMode := LabEditorRingMode
        if IsObject(LabEditorRingsBtn)
            try LabEditorRingsBtn.Text := LabSimpleFootprintButtonText()
    }
}

; Install before any strategy is loaded so BuildMarkers uses the neutral guide from its
; very first frame. The timer only handles lazy unique portraits and does no rendering.
LabSimpleFootprintsInstallTemplate()
SetTimer(LabSimpleFootprintsApply, LabSimpleFootprintsTickMs)
