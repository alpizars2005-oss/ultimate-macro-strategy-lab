#Requires AutoHotkey v2.0

; Lightweight placement presentation layer.
;
; The 0.3.7 experiment resized the marker HWND itself to the tower footprint. That
; made numbered badges turn into huge filled blocks and caused the marker/guide layers
; to visually fight each other during zoom and drag. Keep the responsibilities strict:
;
;   entry.ctrl  = small draggable marker (18 px, 22 px selected)
;   entry.ring  = transparent footprint outline, independently sized by the editor
;
; StrategyEditorPlacements already owns the geometry and drag path for both controls.
; This module only supplies the clean outline asset, defaults to Selected guides, and
; upgrades placement-limit-1 markers to their cached tower portrait when available.

global LabSimpleFootprintsTickMs := 250
global LabSimpleFootprintsLastMode := ""
global LabSimpleFootprintGuidePath := A_ScriptDir "\Resources\StrategyLab\Towers\footprint-guide.png"

; A busy 30+ placement strategy is much easier to read when only the selected
; footprint is visible by default. The existing All / Selected / Off cycle remains.
global LabEditorRingMode
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

    ; Do not use the generic placeholder as a map marker. Wait until Sync Assets has
    ; cached the real tower art, then reuse the already-small square preview cache.
    cached := LabTowerCachedPortraitPath(towerName)
    if (cached = "")
        return ""

    preview := LabTowerPreparePreview(cached, tower.key)
    return preview != "" ? preview : cached
}

LabSimpleFootprintsUpgradeUniqueMarker(index, entry) {
    global MainGui, LabEditorMarkerByHwnd, LabEditorSelectedRow

    ready := false
    try ready := entry.labUniquePortraitReady
    if ready
        return false

    checkedNonUnique := false
    try checkedNonUnique := entry.labUniquePortraitNotApplicable
    if checkedNonUnique
        return false

    towerName := ""
    try towerName := LabEditorDoc.TowerNameForSlot(entry.placement.slot)
    if (towerName = "") {
        try entry.labUniquePortraitNotApplicable := true
        return false
    }

    tower := LabTowerResolve(towerName)
    if (tower.placementLimit != 1) {
        try entry.labUniquePortraitNotApplicable := true
        return false
    }

    portrait := LabSimpleFootprintsPortraitFor(entry)
    if (portrait = "")
        return false

    if !IsObject(entry.ctrl) || !IsObject(MainGui)
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
            " w" size " h" size " Hidden +Border BackgroundTrans", portrait)
        StrategyEditorSetCircularRegion(marker, size)
        marker.OnEvent("Click", StrategyEditorMarkerClicked.Bind(index))
    } catch {
        if IsObject(marker) {
            try marker.Visible := false
            try DllCall("DestroyWindow", "Ptr", marker.Hwnd)
        }
        return false
    }

    ; Replace the old Text badge rather than stacking another control over it. This is
    ; important: entry.ctrl remains the single authoritative draggable marker HWND.
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
            entry.ring.Value := LabSimpleFootprintGuidePath
            entry.labFootprintGuideReady := true
        }
    }
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
    }

    if (changedMarker) {
        ; One layout refresh after replacing marker HWNDs keeps drag hit-testing,
        ; selection sizing and visibility synchronized without a per-frame repaint loop.
        try StrategyEditorRefreshMarkerSelection()
        try StrategyEditorApplyLayer()
    }

    if (LabSimpleFootprintsLastMode != LabEditorRingMode) {
        LabSimpleFootprintsLastMode := LabEditorRingMode
        if IsObject(LabEditorRingsBtn)
            try LabEditorRingsBtn.Text := LabSimpleFootprintButtonText()
    }
}

; Install the neutral guide asset before any strategy is loaded so
; StrategyEditorBuildMarkers() never creates the obsolete cyan template.
LabSimpleFootprintsInstallTemplate()
SetTimer(LabSimpleFootprintsApply, LabSimpleFootprintsTickMs)
