#Requires AutoHotkey v2.0

; Simplified placement visualization.
;
; Older Strategy Lab builds created a second transparent cyan Picture control for
; every tower. That looked similar to TDS' blue placement halo, but doubled the HWND
; count and added clutter/flicker. This compatibility layer removes those legacy halo
; controls and uses the placement marker itself as the footprint circle.
;
; Ring modes are preserved for convenience:
;   all      -> every marker uses its footprint diameter
;   selected -> selected marker uses footprint diameter, others stay compact
;   off      -> every marker stays compact (18 px)

global LabSimpleFootprintsLastCount := -1

global LabSimpleFootprintsTickMs := 40

LabSimpleFootprintDesiredSize(index, placement) {
    global LabEditorRingMode, LabEditorSelectedRow
    if (LabEditorRingMode = "off")
        return 18
    if (LabEditorRingMode = "selected" && index != LabEditorSelectedRow)
        return 18
    return StrategyEditorFootprintDiameter(placement)
}

LabSimpleFootprintButtonText() {
    global LabEditorRingMode
    if (LabEditorRingMode = "selected")
        return "Footprint: 1"
    if (LabEditorRingMode = "off")
        return "Footprint: Compact"
    return "Footprint: All"
}

LabSimpleFootprintsRemoveLegacyHalo(entry) {
    if !IsObject(entry)
        return
    try {
        if IsObject(entry.ring) {
            try entry.ring.Visible := false
            try DllCall("DestroyWindow", "Ptr", entry.ring.Hwnd)
            entry.ring := ""
        }
    }
}

LabSimpleFootprintsApply(*) {
    global LabEditorDoc, LabEditorMarkerCtrls, LabEditorSelectedRow
    global LabEditorRingsBtn, CurrentTab

    if !IsObject(LabEditorDoc)
        return
    if !IsObject(LabEditorMarkerCtrls)
        return

    for index, entry in LabEditorMarkerCtrls {
        if !IsObject(entry)
            continue
        LabSimpleFootprintsRemoveLegacyHalo(entry)

        if !IsObject(entry.ctrl)
            continue

        point := StrategyEditorPlacementPoint(entry.placement)
        size := LabSimpleFootprintDesiredSize(index, entry.placement)
        size := Max(18, Min(150, Integer(size)))

        ; Keep the footprint geometrically centered on the same strategy coordinate.
        try entry.ctrl.Move(point.x - Floor(size / 2), point.y - Floor(size / 2), size, size)
        try StrategyEditorSetCircularRegion(entry.ctrl, size)

        ; A slightly larger label remains readable without changing the footprint size.
        try entry.ctrl.SetFont(index = LabEditorSelectedRow ? "s8 w700" : "s7 w700", "Segoe UI")
    }

    if IsObject(LabEditorRingsBtn)
        try LabEditorRingsBtn.Text := LabSimpleFootprintButtonText()
}

; Run after the editor's own refresh path. Forty milliseconds is responsive enough to
; make newly-created legacy halo controls disappear before they become visually noisy,
; while remaining far below the cost of map rendering.
SetTimer(LabSimpleFootprintsApply, LabSimpleFootprintsTickMs)
