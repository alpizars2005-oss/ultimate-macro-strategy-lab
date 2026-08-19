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

LabFootprintCanonicalPoint(index, placement, document) {
    global LabFootprintReferenceWidth, LabFootprintReferenceHeight
    logical := LabFootprintLogicalPoint(index, placement)
    return {
        x: logical.x * LabFootprintReferenceWidth / Max(1.0, Number(document.StrategyWidth)),
        y: logical.y * LabFootprintReferenceHeight / Max(1.0, Number(document.StrategyHeight)),
        radius: LabFootprintReferenceRadius(placement, document)
    }
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

LabFootprintPlacementCollides(index, document) {
    if !IsObject(document) || index < 1 || index > document.Placements.Length
        return false
    aPlacement := document.Placements[index]
    a := LabFootprintCanonicalPoint(index, aPlacement, document)
    for otherIndex, otherPlacement in document.Placements {
        if (otherIndex = index)
            continue
        b := LabFootprintCanonicalPoint(otherIndex, otherPlacement, document)
        dx := a.x - b.x
        dy := a.y - b.y
        minDistance := a.radius + b.radius
        if ((dx * dx) + (dy * dy) < (minDistance * minDistance))
            return true
    }
    return false
}

; Returns a Map keyed by document placement index. Any key present is intersecting at
; least one other real placement footprint. The comparison is deliberately performed in
; source strategy pixels so it does not depend on Editor zoom or hotbar cropping.
LabFootprintCollisionMap(document) {
    collisions := Map()
    if !IsObject(document) || document.Placements.Length < 2
        return collisions

    points := []
    for index, placement in document.Placements {
        p := LabFootprintCanonicalPoint(index, placement, document)
        points.Push({index: index, x: p.x, y: p.y, radius: p.radius})
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
    return selected ? 5.0 : 3.5
}

LabFootprintLabelOffset(selected := false) {
    return selected ? 6 : 5
}
