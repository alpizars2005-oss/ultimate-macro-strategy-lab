#Requires AutoHotkey v2.0

; Strategy Lab placement-footprint geometry.
;
; TDS exposes placement footprint as a boundary radius (for example Small=1,
; Average=1.5, Very Large=2.5). Ultimate Macro records placement centers in its
; 1920x1009 strategy coordinate space. With the fixed macro camera, one footprint
; unit is ~12 strategy pixels. Keeping the calculation in the reference coordinate
; space makes collision checks independent from Editor zoom and canvas size.

global LabFootprintReferenceWidth := 1920.0
global LabFootprintReferenceHeight := 1009.0
global LabFootprintPixelsPerUnit := 12.0

LabFootprintUnitsForPlacement(placement, document) {
    if !IsObject(document) || !IsObject(placement)
        return 1.5
    tower := document.TowerNameForSlot(placement.slot)
    return tower != "" ? LabTowerPlacementFootprint(tower) : 1.5
}

LabFootprintReferenceRadius(placement, document) {
    return LabFootprintUnitsForPlacement(placement, document) * LabFootprintPixelsPerUnit
}

LabFootprintLogicalPoint(index, placement) {
    global LabEditorDragIndex, LabEditorDragPreviewX, LabEditorDragPreviewY
    if (index = LabEditorDragIndex && LabEditorDragPreviewX != "" && LabEditorDragPreviewY != "")
        return {x: Number(LabEditorDragPreviewX), y: Number(LabEditorDragPreviewY)}
    return {x: Number(placement.x), y: Number(placement.y)}
}

LabFootprintCanvasEllipse(placement, document, viewport, canvasW, canvasH) {
    global LabFootprintReferenceWidth, LabFootprintReferenceHeight
    radius := LabFootprintReferenceRadius(placement, document)
    zoom := IsObject(viewport) ? Number(viewport.Zoom) : 1.0
    return {
        w: (radius * 2.0) * (Number(canvasW) / LabFootprintReferenceWidth) * zoom,
        h: (radius * 2.0) * (Number(canvasH) / LabFootprintReferenceHeight) * zoom
    }
}

; Returns a Map keyed by document placement index. Any key present in the map is
; currently intersecting at least one other placement footprint. The comparison is
; performed in the canonical 1920x1009 strategy space rather than canvas pixels.
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
    ; The footprint itself is the authoritative placement guide. Keep the center marker
    ; intentionally tiny so it never visually masquerades as the tower boundary.
    return selected ? 7.0 : 5.0
}

LabFootprintLabelOffset(selected := false) {
    return selected ? 5 : 4
}
