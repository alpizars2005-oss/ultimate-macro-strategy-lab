#Requires AutoHotkey v2.0

; Strategy Lab placement-footprint geometry.
;
; The circle shown by the editor is the TDS PLACEMENT BOUNDARY: the small striped
; circle while placing and the cyan outline around a placed tower. It is NOT the large
; attack/range ring. The user's 1920-wide Operator reference measures ~78 px diameter;
; Operator is Average/1.5, giving a visual baseline of ~26 strategy pixels per unit.
;
; A post-run analyzer can override that baseline per map after observing multiple cyan
; rings, while collision checks remain in canonical 1920x1009 strategy coordinates.

global LabFootprintReferenceWidth := 1920.0
global LabFootprintReferenceHeight := 1009.0
global LabFootprintPixelsPerUnit := 26.0

LabFootprintMapName(document) {
    if !IsObject(document)
        return ""
    try {
        if document.Settings.Has("map")
            return Trim(String(document.Settings["map"]))
    }
    return ""
}

LabFootprintPixelsPerUnitForDocument(document) {
    global LabFootprintPixelsPerUnit
    mapName := LabFootprintMapName(document)
    if (mapName = "")
        return LabFootprintPixelsPerUnit
    c := LabMapCalibration(mapName)
    return IsObject(c) ? Number(c.pixelsPerUnit) : LabFootprintPixelsPerUnit
}

LabFootprintUnitsForPlacement(placement, document) {
    if !IsObject(document) || !IsObject(placement)
        return 1.5
    tower := document.TowerNameForSlot(placement.slot)
    return tower != "" ? LabTowerPlacementFootprint(tower) : 1.5
}

LabFootprintReferenceRadius(placement, document) {
    return LabFootprintUnitsForPlacement(placement, document) * LabFootprintPixelsPerUnitForDocument(document)
}

LabFootprintLogicalPoint(index, placement) {
    global LabEditorDragIndex, LabEditorDragPreviewX, LabEditorDragPreviewY
    if (index = LabEditorDragIndex && LabEditorDragPreviewX != "" && LabEditorDragPreviewY != "")
        return {x: Number(LabEditorDragPreviewX), y: Number(LabEditorDragPreviewY)}
    return {x: Number(placement.x), y: Number(placement.y)}
}

LabFootprintCanvasEllipse(placement, document, viewport, canvasW, canvasH) {
    global LabFootprintReferenceWidth
    radius := LabFootprintReferenceRadius(placement, document)
    zoom := IsObject(viewport) ? Number(viewport.Zoom) : 1.0
    strategyPlayableH := LabMapPlayableStrategyHeight(document.StrategyHeight)
    return {
        w: (radius * 2.0) * (Number(canvasW) / LabFootprintReferenceWidth) * zoom,
        h: (radius * 2.0) * (Number(canvasH) / strategyPlayableH) * zoom
    }
}

; Returns a Map keyed by document placement index. Any key present is intersecting at
; least one other real placement footprint. The comparison is deliberately performed in
; source strategy pixels so it does not depend on Editor zoom or hotbar cropping.
LabFootprintCollisionMap(document) {
    global LabFootprintReferenceWidth, LabFootprintReferenceHeight
    collisions := Map()
    if !IsObject(document) || document.Placements.Length < 2
        return collisions

    width := Max(1.0, Number(document.StrategyWidth))
    height := Max(1.0, Number(document.StrategyHeight))
    points := []

    for index, placement in document.Placements {
        logical := LabFootprintLogicalPoint(index, placement)
        points.Push({
            index: index,
            x: logical.x * LabFootprintReferenceWidth / width,
            y: logical.y * LabFootprintReferenceHeight / height,
            radius: LabFootprintReferenceRadius(placement, document)
        })
    }

    for i, a in points {
        j := i + 1
        while (j <= points.Length) {
            b := points[j]
            dx := a.x - b.x
            dy := a.y - b.y
            minDistance := a.radius + b.radius
            if ((dx * dx) + (dy * dy) < (minDistance * minDistance)) {
                collisions[a.index] := true
                collisions[b.index] := true
            }
            j += 1
        }
    }
    return collisions
}

LabFootprintMarkerDiameter(selected := false) {
    ; The center marker stays compact. The boundary itself carries the placement truth.
    return selected ? 5.0 : 3.5
}

LabFootprintLabelOffset(selected := false) {
    return selected ? 6 : 5
}
