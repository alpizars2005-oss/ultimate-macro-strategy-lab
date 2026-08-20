#Requires AutoHotkey v2.0

; Strategy Lab 0.4.8 interaction/memory hotfix.
;
; Goals:
;   - Layer state uses a numeric slot as the source of truth; labels are display-only.
;   - The legacy DropDownList callback is suppressed while the native selection commits.
;   - Drag/pan reuse persistent DIB frame buffers instead of allocating a bitmap/HBITMAP per frame.
;   - Drag copies a persistent stationary base with BitBlt and paints only the moving square.
;   - Pan keeps visible tower squares on screen while omitting text during motion.
;   - Projection/calibration values are cached once per interaction (no per-tower INI reads).
;   - Adaptive cadence and lightweight profiling report render time, FPS and working-set change.
; No gameplay clicks, strategy coordinates, saves, or footprint rules are changed.

global Lab047LayerIndex := Map()
global Lab047LayerIndexToken := ""
global Lab047ActiveSlot := 0
global Lab047DragLastPaint := 0
global Lab047DragLastFieldUpdate := 0
global Lab047PanLastPaint := 0

global Lab048FrameBuffers := []
global Lab048FrameIndex := 0
global Lab048DragBase := 0
global Lab048DragBaseKey := ""
global Lab048FastBrushes := Map()
global Lab048FastBorderBrush := 0
global Lab048FastSelectedBorderBrush := 0

global Lab048SourceBitmap := 0
global Lab048SourceW := 0
global Lab048SourceH := 0
global Lab048OffsetX := 0.0
global Lab048OffsetY := 0.0
global Lab048PlayableH := 0.0
global Lab048StrategyW := 0.0

global Lab048DragInterval := 25
global Lab048PanInterval := 33

global Lab047ProfileKind := ""
global Lab047ProfileFrames := 0
global Lab047ProfileTotalMs := 0
global Lab047ProfilePeakMs := 0
global Lab047ProfileStarted := 0
global Lab047ProfileStartMem := 0.0

Lab047DocumentToken() {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return ""
    towers := ""
    for index, tower in LabEditorDoc.RequiredTowers
        towers .= (index = 1 ? "" : "|") tower
    return LabEditorDoc.Path "|" LabEditorDoc.Placements.Length "|" towers
}

Lab047EnsureLayerIndex(force := false) {
    global LabEditorDoc, Lab047LayerIndex, Lab047LayerIndexToken, Lab047ActiveSlot
    if !IsObject(LabEditorDoc) {
        Lab047LayerIndex := Map()
        Lab047LayerIndexToken := ""
        Lab047ActiveSlot := 0
        return false
    }

    token := Lab047DocumentToken()
    changed := token != Lab047LayerIndexToken
    if !force && !changed && Lab047LayerIndex.Has(0)
        return true

    if changed
        Lab047ActiveSlot := 0

    indexMap := Map()
    indexMap[0] := []
    for index, placement in LabEditorDoc.Placements {
        indexMap[0].Push(index)
        slot := IsNumber(placement.slot) ? Integer(placement.slot) : 0
        if (slot <= 0)
            continue
        if !indexMap.Has(slot)
            indexMap[slot] := []
        indexMap[slot].Push(index)
    }

    Lab047LayerIndex := indexMap
    Lab047LayerIndexToken := token
    return true
}

Lab047VisibleIndices() {
    global Lab047LayerIndex, Lab047ActiveSlot
    if !Lab047EnsureLayerIndex()
        return []
    if Lab047LayerIndex.Has(Lab047ActiveSlot)
        return Lab047LayerIndex[Lab047ActiveSlot]
    return Lab047LayerIndex[0]
}

Lab047ArrayContains(values, needle) {
    for value in values {
        if (value = needle)
            return true
    }
    return false
}

Lab047RefreshLayerList(indices, selectedDocIndex := 0) {
    global LabEditorDoc, LabEditorList, LabEditorListRowMap
    if !IsObject(LabEditorDoc) || !LabEditorControlAlive(LabEditorList)
        return 0

    try LabEditorList.Delete()
    LabEditorListRowMap := []
    selectedVisibleRow := 0

    for docIndex in indices {
        if (docIndex < 1 || docIndex > LabEditorDoc.Placements.Length)
            continue
        placement := LabEditorDoc.Placements[docIndex]
        LabEditorList.Add(, docIndex, LabTowerPlacementDisplay(LabEditorDoc, placement), placement.x, placement.y)
        LabEditorListRowMap.Push(docIndex)
        if (docIndex = selectedDocIndex)
            selectedVisibleRow := LabEditorListRowMap.Length
    }

    if (selectedVisibleRow > 0)
        try LabEditorList.Modify(selectedVisibleRow, "Vis Select Focus")
    return selectedVisibleRow
}

Lab047SlotForChoice(choice) {
    global LabEditorLayerOptions
    if (choice <= 1)
        return 0
    if (choice > LabEditorLayerOptions.Length)
        return 0
    option := LabEditorLayerOptions[choice]
    match := 0
    if RegExMatch(option, "i)^Slot\s+(\d+)", &match)
        return Integer(match[1])
    return 0
}

Lab047ApplyLayerChoice(choice, nativeCommit := false) {
    global LabEditorLayer, LabEditorLayerOptions, LabEditorLayerChangeBusy, LabEditorLayerCtrl
    global LabEditorDoc, LabEditorSelectedRow, LabEditorXCtrl, LabEditorYCtrl
    global Lab047ActiveSlot

    if !nativeCommit && LabEditorLayerChangeBusy
        return
    if !IsObject(LabEditorDoc) {
        if nativeCommit
            LabEditorLayerChangeBusy := false
        return
    }
    if (choice < 1 || choice > LabEditorLayerOptions.Length) {
        if nativeCommit
            LabEditorLayerChangeBusy := false
        return
    }

    Lab047EnsureLayerIndex()
    wanted := LabEditorLayerOptions[choice]
    if (wanted = "") {
        if nativeCommit
            LabEditorLayerChangeBusy := false
        return
    }

    LabEditorLayerChangeBusy := true
    try {
        Lab047ActiveSlot := Lab047SlotForChoice(choice)
        LabEditorLayer := wanted

        if LabEditorControlAlive(LabEditorLayerCtrl) {
            currentChoice := 0
            try currentChoice := Integer(LabEditorLayerCtrl.Value)
            if (currentChoice != choice)
                try LabEditorLayerCtrl.Choose(choice)
        }

        indices := Lab047VisibleIndices()
        if !Lab047ArrayContains(indices, LabEditorSelectedRow)
            LabEditorSelectedRow := indices.Length > 0 ? indices[1] : 0

        Lab047RefreshLayerList(indices, LabEditorSelectedRow)

        if (LabEditorSelectedRow > 0 && LabEditorSelectedRow <= LabEditorDoc.Placements.Length) {
            placement := LabEditorDoc.Placements[LabEditorSelectedRow]
            if LabEditorControlAlive(LabEditorXCtrl)
                try LabEditorXCtrl.Text := placement.x
            if LabEditorControlAlive(LabEditorYCtrl)
                try LabEditorYCtrl.Text := placement.y
            StrategyEditorShowTower(placement)
        }

        Lab048ReleaseDragBase()
        StrategyEditorReleaseFastBase()
        StrategyEditorRenderBackground()
        StrategyEditorSetStatus("Layer: " LabEditorLayer " • " indices.Length " placement"
            (indices.Length = 1 ? "" : "s") ".")
    } finally {
        LabEditorLayerChangeBusy := false
    }
}

Lab047Command(wParam, lParam, msg, hwnd) {
    global LabEditorLayerCtrl, LabEditorLayerOptions, LabEditorLayerChangeBusy
    if LabEditorLayerChangeBusy || !LabEditorControlAlive(LabEditorLayerCtrl)
        return

    ctrlHwnd := 0
    try ctrlHwnd := LabEditorLayerCtrl.Hwnd
    if !ctrlHwnd || lParam != ctrlHwnd
        return

    notify := (wParam >> 16) & 0xFFFF
    if (notify != 1)
        return

    selectedZero := -1
    try selectedZero := DllCall("user32\SendMessageW", "Ptr", ctrlHwnd, "UInt", 0x0147,
        "Ptr", 0, "Ptr", 0, "Ptr")
    choice := selectedZero + 1
    if (choice < 1 || choice > LabEditorLayerOptions.Length)
        return

    LabEditorLayerChangeBusy := true
    SetTimer(Lab047ApplyLayerChoice.Bind(choice, true), -1)
}

Lab048CreateSurface() {
    global LabEditorCanvasW, LabEditorCanvasH
    width := Integer(LabEditorCanvasW)
    height := Integer(LabEditorCanvasH)
    if (width <= 0 || height <= 0)
        return 0

    bmi := Buffer(40, 0)
    NumPut("UInt", 40, bmi, 0)
    NumPut("Int", width, bmi, 4)
    NumPut("Int", -height, bmi, 8)
    NumPut("UShort", 1, bmi, 12)
    NumPut("UShort", 32, bmi, 14)
    NumPut("UInt", 0, bmi, 16)

    screenDC := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    if !screenDC
        return 0

    bits := 0
    hBitmap := 0
    hdc := 0
    try {
        hBitmap := DllCall("gdi32\CreateDIBSection", "Ptr", screenDC, "Ptr", bmi.Ptr,
            "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
        if !hBitmap
            return 0
        hdc := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
        if !hdc {
            DllCall("gdi32\DeleteObject", "Ptr", hBitmap)
            return 0
        }
    } finally {
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDC)
    }

    return {hBitmap: hBitmap, hdc: hdc, bits: bits, width: width, height: height}
}

Lab048DestroySurface(surface) {
    if !IsObject(surface)
        return
    if surface.hdc
        try DllCall("gdi32\DeleteDC", "Ptr", surface.hdc)
    if surface.hBitmap
        try DllCall("gdi32\DeleteObject", "Ptr", surface.hBitmap)
}

Lab048OwnsHandle(hBitmap) {
    global Lab048FrameBuffers, Lab048DragBase
    if !hBitmap
        return false
    for surface in Lab048FrameBuffers {
        if IsObject(surface) && surface.hBitmap = hBitmap
            return true
    }
    return IsObject(Lab048DragBase) && Lab048DragBase.hBitmap = hBitmap
}

Lab048DetachPersistentPresentation() {
    global LabEditorSnapshot, LabEditorCanvasBitmap
    current := LabEditorCanvasBitmap
    if !current || !Lab048OwnsHandle(current)
        return
    if LabEditorControlAlive(LabEditorSnapshot) {
        hwnd := 0
        try hwnd := LabEditorSnapshot.Hwnd
        if hwnd
            try DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x0172, "Ptr", 0, "Ptr", 0, "Ptr")
    }
    LabEditorCanvasBitmap := 0
}

Lab048ReleaseDragBase(*) {
    global Lab048DragBase, Lab048DragBaseKey
    if IsObject(Lab048DragBase)
        Lab048DestroySurface(Lab048DragBase)
    Lab048DragBase := 0
    Lab048DragBaseKey := ""
}

Lab048ReleaseFrameBuffers(*) {
    global Lab048FrameBuffers, Lab048FrameIndex
    Lab048DetachPersistentPresentation()
    for surface in Lab048FrameBuffers
        Lab048DestroySurface(surface)
    Lab048FrameBuffers := []
    Lab048FrameIndex := 0
}

Lab048EnsureFrameBuffers() {
    global Lab048FrameBuffers, LabEditorCanvasW, LabEditorCanvasH
    if (Lab048FrameBuffers.Length = 2) {
        first := Lab048FrameBuffers[1]
        second := Lab048FrameBuffers[2]
        if (first.width = LabEditorCanvasW && first.height = LabEditorCanvasH
            && second.width = LabEditorCanvasW && second.height = LabEditorCanvasH)
            return true
    }

    Lab048ReleaseFrameBuffers()
    Lab048ReleaseDragBase()
    a := Lab048CreateSurface()
    b := Lab048CreateSurface()
    if !IsObject(a) || !IsObject(b) {
        if IsObject(a)
            Lab048DestroySurface(a)
        if IsObject(b)
            Lab048DestroySurface(b)
        return false
    }
    Lab048FrameBuffers := [a, b]
    return true
}

Lab048BeginGraphics(surface, &oldBitmap) {
    oldBitmap := 0
    if !IsObject(surface) || !surface.hdc || !surface.hBitmap
        return 0

    try oldBitmap := DllCall("gdi32\SelectObject", "Ptr", surface.hdc, "Ptr", surface.hBitmap, "Ptr")
    if !oldBitmap
        return 0

    graphics := 0
    status := 1
    try status := DllCall("gdiplus\GdipCreateFromHDC", "Ptr", surface.hdc, "Ptr*", &graphics, "Int")
    if (status != 0 || !graphics) {
        try DllCall("gdi32\SelectObject", "Ptr", surface.hdc, "Ptr", oldBitmap, "Ptr")
        oldBitmap := 0
        return 0
    }
    return graphics
}

Lab048EndGraphics(surface, graphics, oldBitmap) {
    if graphics
        try Gdip_DeleteGraphics(graphics)
    if IsObject(surface) && surface.hdc && oldBitmap
        try DllCall("gdi32\SelectObject", "Ptr", surface.hdc, "Ptr", oldBitmap, "Ptr")
}

Lab048ClearGraphics(graphics) {
    if graphics
        try DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF171717, "Int")
}

Lab048BitBlt(source, target) {
    global LabEditorCanvasW, LabEditorCanvasH
    if !IsObject(source) || !IsObject(target)
        return false

    oldSrc := 0
    oldDst := 0
    try {
        oldSrc := DllCall("gdi32\SelectObject", "Ptr", source.hdc, "Ptr", source.hBitmap, "Ptr")
        oldDst := DllCall("gdi32\SelectObject", "Ptr", target.hdc, "Ptr", target.hBitmap, "Ptr")
        if !oldSrc || !oldDst
            return false
        return !!DllCall("gdi32\BitBlt",
            "Ptr", target.hdc, "Int", 0, "Int", 0, "Int", LabEditorCanvasW, "Int", LabEditorCanvasH,
            "Ptr", source.hdc, "Int", 0, "Int", 0, "UInt", 0x00CC0020, "Int")
    } finally {
        if oldDst
            try DllCall("gdi32\SelectObject", "Ptr", target.hdc, "Ptr", oldDst, "Ptr")
        if oldSrc
            try DllCall("gdi32\SelectObject", "Ptr", source.hdc, "Ptr", oldSrc, "Ptr")
    }
}

Lab048NextFrameBuffer() {
    global Lab048FrameBuffers, Lab048FrameIndex
    if !Lab048EnsureFrameBuffers()
        return 0
    Lab048FrameIndex := Lab048FrameIndex = 1 ? 2 : 1
    return Lab048FrameBuffers[Lab048FrameIndex]
}

Lab048Present(surface) {
    global LabEditorSnapshot, LabEditorCanvasBitmap
    if !IsObject(surface) || !surface.hBitmap || !LabEditorControlAlive(LabEditorSnapshot)
        return false

    hwnd := 0
    try hwnd := LabEditorSnapshot.Hwnd
    if !hwnd
        return false

    old := 0
    try old := DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x0172,
        "Ptr", 0, "Ptr", surface.hBitmap, "Ptr")
    LabEditorCanvasBitmap := surface.hBitmap

    if old && old != surface.hBitmap && !Lab048OwnsHandle(old)
        try DllCall("gdi32\DeleteObject", "Ptr", old)

    try DllCall("user32\InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", false)
    return true
}

Lab047GetSlotBrush(slot) {
    global Lab048FastBrushes
    key := String(slot)
    if Lab048FastBrushes.Has(key)
        return Lab048FastBrushes[key]
    brush := Gdip_BrushCreateSolid(StrategyEditorSlotColor(slot, 255))
    if brush
        Lab048FastBrushes[key] := brush
    return brush
}

Lab047EnsureBorderBrushes() {
    global Lab048FastBorderBrush, Lab048FastSelectedBorderBrush
    if !Lab048FastBorderBrush
        Lab048FastBorderBrush := Gdip_BrushCreateSolid(0xFF20252B)
    if !Lab048FastSelectedBorderBrush
        Lab048FastSelectedBorderBrush := Gdip_BrushCreateSolid(0xFFFFFFFF)
}

Lab047DrawFastMarker(graphics, placement, x, y, selected := false) {
    global Lab048FastBorderBrush, Lab048FastSelectedBorderBrush
    Lab047EnsureBorderBrushes()
    fillBrush := Lab047GetSlotBrush(placement.slot)
    borderBrush := selected ? Lab048FastSelectedBorderBrush : Lab048FastBorderBrush
    markerSize := selected ? 22 : 18
    half := markerSize / 2.0
    border := selected ? 2 : 1

    if borderBrush
        Gdip_FillRectangle(graphics, borderBrush, x - half, y - half, markerSize, markerSize)
    if fillBrush
        Gdip_FillRectangle(graphics, fillBrush, x - half + border, y - half + border,
            markerSize - (border * 2), markerSize - (border * 2))
}

Lab048PrepareInteraction() {
    global LabEditorSourceImage, LabEditorDoc
    global Lab048SourceBitmap, Lab048SourceW, Lab048SourceH
    global Lab048OffsetX, Lab048OffsetY, Lab048PlayableH, Lab048StrategyW

    Lab047EnsureLayerIndex()
    if !IsObject(LabEditorDoc) || LabEditorSourceImage = "" || !FileExist(LabEditorSourceImage)
        return false
    if !Lab048EnsureFrameBuffers()
        return false

    Lab048SourceBitmap := LabMapAcquireRenderBitmap(LabEditorSourceImage, &sourceW, &sourceH)
    if !Lab048SourceBitmap || sourceW <= 0 || sourceH <= 0
        return false

    Lab048SourceW := sourceW
    Lab048SourceH := sourceH
    Lab048PlayableH := LabMapPlayableStrategyHeight(LabEditorDoc.StrategyHeight)
    Lab048StrategyW := Number(LabEditorDoc.StrategyWidth)

    Lab048OffsetX := 0.0
    Lab048OffsetY := 0.0
    mapName := StrategyEditorMapName()
    if (mapName != "") {
        c := LabMapCalibration(mapName)
        Lab048OffsetX := Number(c.offsetX)
        Lab048OffsetY := Number(c.offsetY)
    }
    return true
}

Lab048ClearInteractionSource() {
    global Lab048SourceBitmap, Lab048SourceW, Lab048SourceH
    global Lab048OffsetX, Lab048OffsetY, Lab048PlayableH, Lab048StrategyW
    Lab048SourceBitmap := 0
    Lab048SourceW := 0
    Lab048SourceH := 0
    Lab048OffsetX := 0.0
    Lab048OffsetY := 0.0
    Lab048PlayableH := 0.0
    Lab048StrategyW := 0.0
}

Lab048PlacementPoint(index, placement, &px, &py) {
    global LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragIndex, LabEditorDragPreviewX, LabEditorDragPreviewY
    global Lab048OffsetX, Lab048OffsetY, Lab048PlayableH, Lab048StrategyW

    rawX := Number(placement.x)
    rawY := Number(placement.y)
    if (index = LabEditorDragIndex && LabEditorDragPreviewX != "" && LabEditorDragPreviewY != "") {
        rawX := Number(LabEditorDragPreviewX)
        rawY := Number(LabEditorDragPreviewY)
    }
    if (rawY > Lab048PlayableH)
        return false

    normalizedX := (rawX + Lab048OffsetX) / Max(1.0, Lab048StrategyW)
    normalizedY := (rawY + Lab048OffsetY) / Max(1.0, Lab048PlayableH)
    visibleW := 1.0 / LabEditorViewport.Zoom
    visibleH := 1.0 / LabEditorViewport.Zoom
    left := LabEditorViewport.CenterX - visibleW / 2
    top := LabEditorViewport.CenterY - visibleH / 2

    fx := ((normalizedX - left) / visibleW) * LabEditorCanvasW
    fy := ((normalizedY - top) / visibleH) * LabEditorCanvasH
    if (fx < 0 || fx > LabEditorCanvasW || fy < 0 || fy > LabEditorCanvasH)
        return false

    px := Round(fx)
    py := Round(fy)
    return true
}

Lab048ViewportToStrategy(mx, my) {
    global LabEditorViewport, LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global Lab048OffsetX, Lab048OffsetY, Lab048PlayableH, Lab048StrategyW

    visibleW := 1.0 / LabEditorViewport.Zoom
    visibleH := 1.0 / LabEditorViewport.Zoom
    left := LabEditorViewport.CenterX - visibleW / 2
    top := LabEditorViewport.CenterY - visibleH / 2
    normalizedX := left + ((Number(mx) - LabEditorCanvasX) / Max(1, LabEditorCanvasW)) * visibleW
    normalizedY := top + ((Number(my) - LabEditorCanvasY) / Max(1, LabEditorCanvasH)) * visibleH

    x := (Max(0.0, Min(1.0, normalizedX)) * Lab048StrategyW) - Lab048OffsetX
    y := (Max(0.0, Min(1.0, normalizedY)) * Lab048PlayableH) - Lab048OffsetY
    return {
        x: Round(Max(0, Min(Lab048StrategyW, x))),
        y: Round(Max(0, Min(Lab048PlayableH, y)))
    }
}

Lab048PlacementAllowed(placement) {
    global Lab047ActiveSlot
    return Lab047ActiveSlot = 0 || (IsNumber(placement.slot) && Integer(placement.slot) = Lab047ActiveSlot)
}

Lab048DrawVisibleMarkers(graphics, skipIndex := 0, selectedIndex := 0) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return
    for index, placement in LabEditorDoc.Placements {
        if (index = skipIndex) || !Lab048PlacementAllowed(placement)
            continue
        px := 0
        py := 0
        if !Lab048PlacementPoint(index, placement, &px, &py)
            continue
        Lab047DrawFastMarker(graphics, placement, px, py, index = selectedIndex)
    }
}

Lab048DragKey(dragIndex) {
    global LabEditorSourceImage, LabEditorViewport, LabEditorCanvasW, LabEditorCanvasH
    global Lab047ActiveSlot, Lab048OffsetX, Lab048OffsetY
    return LabEditorSourceImage "|" dragIndex "|" Lab047ActiveSlot
        . "|" Round(LabEditorViewport.Zoom, 3)
        . "|" Round(LabEditorViewport.CenterX, 4) "|" Round(LabEditorViewport.CenterY, 4)
        . "|" LabEditorCanvasW "x" LabEditorCanvasH
        . "|" Lab048OffsetX "|" Lab048OffsetY
}

Lab048BuildDragBase(dragIndex) {
    global Lab048DragBase, Lab048DragBaseKey
    global Lab048SourceBitmap, Lab048SourceW, Lab048SourceH

    key := Lab048DragKey(dragIndex)
    if IsObject(Lab048DragBase) && Lab048DragBaseKey = key
        return Lab048DragBase

    Lab048ReleaseDragBase()
    surface := Lab048CreateSurface()
    if !IsObject(surface)
        return 0

    oldBitmap := 0
    graphics := Lab048BeginGraphics(surface, &oldBitmap)
    if !graphics {
        Lab048DestroySurface(surface)
        return 0
    }

    success := false
    try {
        Lab048ClearGraphics(graphics)
        StrategyEditorDrawSource(graphics, Lab048SourceBitmap, Lab048SourceW, Lab048SourceH, true)
        Lab048DrawVisibleMarkers(graphics, dragIndex, 0)
        success := true
    } finally {
        Lab048EndGraphics(surface, graphics, oldBitmap)
        if !success
            Lab048DestroySurface(surface)
    }
    if !success
        return 0

    Lab048DragBase := surface
    Lab048DragBaseKey := key
    return surface
}

Lab048RenderDragFrame(dragIndex) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc)
        return false

    base := Lab048BuildDragBase(dragIndex)
    target := Lab048NextFrameBuffer()
    if !IsObject(base) || !IsObject(target)
        return false
    if !Lab048BitBlt(base, target)
        return false

    if (dragIndex >= 1 && dragIndex <= LabEditorDoc.Placements.Length) {
        placement := LabEditorDoc.Placements[dragIndex]
        px := 0
        py := 0
        if Lab048PlacementAllowed(placement) && Lab048PlacementPoint(dragIndex, placement, &px, &py) {
            oldBitmap := 0
            graphics := Lab048BeginGraphics(target, &oldBitmap)
            if graphics {
                try {
                    Lab047DrawFastMarker(graphics, placement, px, py, true)
                } finally {
                    Lab048EndGraphics(target, graphics, oldBitmap)
                }
            }
        }
    }
    return Lab048Present(target)
}

Lab048RenderPanFrame() {
    global Lab048SourceBitmap, Lab048SourceW, Lab048SourceH, LabEditorSelectedRow
    target := Lab048NextFrameBuffer()
    if !IsObject(target) || !Lab048SourceBitmap
        return false

    oldBitmap := 0
    graphics := Lab048BeginGraphics(target, &oldBitmap)
    if !graphics
        return false

    success := false
    try {
        Lab048ClearGraphics(graphics)
        StrategyEditorDrawSource(graphics, Lab048SourceBitmap, Lab048SourceW, Lab048SourceH, true)
        Lab048DrawVisibleMarkers(graphics, 0, LabEditorSelectedRow)
        success := true
    } finally {
        Lab048EndGraphics(target, graphics, oldBitmap)
    }
    return success ? Lab048Present(target) : false
}

Lab048MemoryMB() {
    size := A_PtrSize = 8 ? 72 : 40
    counters := Buffer(size, 0)
    NumPut("UInt", size, counters, 0)
    process := DllCall("kernel32\GetCurrentProcess", "Ptr")
    ok := 0
    try ok := DllCall("psapi\GetProcessMemoryInfo", "Ptr", process, "Ptr", counters.Ptr, "UInt", size, "Int")
    if !ok
        return 0.0
    offset := A_PtrSize = 8 ? 16 : 12
    bytes := NumGet(counters, offset, "UPtr")
    return Round(bytes / 1048576.0, 1)
}

Lab047ProfileReset(kind) {
    global Lab047ProfileKind, Lab047ProfileFrames, Lab047ProfileTotalMs
    global Lab047ProfilePeakMs, Lab047ProfileStarted, Lab047ProfileStartMem
    Lab047ProfileKind := kind
    Lab047ProfileFrames := 0
    Lab047ProfileTotalMs := 0
    Lab047ProfilePeakMs := 0
    Lab047ProfileStarted := A_TickCount
    Lab047ProfileStartMem := Lab048MemoryMB()
}

Lab047ProfileAdd(elapsedMs) {
    global Lab047ProfileFrames, Lab047ProfileTotalMs, Lab047ProfilePeakMs
    Lab047ProfileFrames += 1
    Lab047ProfileTotalMs += elapsedMs
    Lab047ProfilePeakMs := Max(Lab047ProfilePeakMs, elapsedMs)
}

Lab048AdaptInterval(kind, elapsedMs) {
    global Lab048DragInterval, Lab048PanInterval
    if (elapsedMs <= 8)
        target := 20
    else if (elapsedMs <= 14)
        target := 24
    else if (elapsedMs <= 22)
        target := 30
    else if (elapsedMs <= 30)
        target := 40
    else
        target := 50

    if (kind = "Drag")
        Lab048DragInterval := Max(20, Min(55, Round((Lab048DragInterval * 0.7) + (target * 0.3))))
    else
        Lab048PanInterval := Max(24, Min(60, Round((Lab048PanInterval * 0.7) + (target * 0.3))))
}

Lab047ProfileAppend(kind) {
    global Lab047ProfileKind, Lab047ProfileFrames, Lab047ProfileTotalMs
    global Lab047ProfilePeakMs, Lab047ProfileStarted, Lab047ProfileStartMem, LabEditorStatus

    if (Lab047ProfileKind != kind || Lab047ProfileFrames < 1)
        return

    elapsed := Max(1, A_TickCount - Lab047ProfileStarted)
    avg := Round(Lab047ProfileTotalMs / Lab047ProfileFrames, 1)
    fps := Round((Lab047ProfileFrames * 1000.0) / elapsed, 1)
    endMem := Lab048MemoryMB()
    deltaMem := Round(endMem - Lab047ProfileStartMem, 1)
    memText := ""
    if (Lab047ProfileStartMem > 0 && endMem > 0)
        memText := " • mem " Lab047ProfileStartMem "→" endMem " MB (" (deltaMem >= 0 ? "+" : "") deltaMem ")"
    suffix := "Perf " kind ": " avg " ms avg • " Lab047ProfilePeakMs " ms peak • ~" fps " FPS" memText

    if LabEditorControlAlive(LabEditorStatus) {
        current := ""
        try current := Trim(LabEditorStatus.Text)
        try LabEditorStatus.Text := (current != "" ? current "  |  " : "") suffix
    }
    Lab047ProfileKind := ""
}

Lab048ReleaseResources(*) {
    global Lab048FastBrushes, Lab048FastBorderBrush, Lab048FastSelectedBorderBrush
    Lab048DetachPersistentPresentation()
    Lab048ReleaseDragBase()
    Lab048ReleaseFrameBuffers()
    Lab048ClearInteractionSource()

    for key, brush in Lab048FastBrushes {
        if brush
            try Gdip_DeleteBrush(brush)
    }
    Lab048FastBrushes := Map()

    if Lab048FastBorderBrush
        try Gdip_DeleteBrush(Lab048FastBorderBrush)
    if Lab048FastSelectedBorderBrush
        try Gdip_DeleteBrush(Lab048FastSelectedBorderBrush)
    Lab048FastBorderBrush := 0
    Lab048FastSelectedBorderBrush := 0
}

Lab048PauseHousekeeping() {
    try SetTimer(StrategyEditorWorkspaceMonitor, 0)
    try SetTimer(StrategyEditorInteractiveStateGuard, 0)
}

Lab048ResumeHousekeeping() {
    try SetTimer(StrategyEditorWorkspaceMonitor, 250)
    try SetTimer(StrategyEditorInteractiveStateGuard, 1500)
}

Lab047CanvasMouseDown(wParam, lParam, msg, hwnd) {
    global LabEditorDragPlacement, LabEditorPanActive
    global Lab047DragLastPaint, Lab047DragLastFieldUpdate, Lab047PanLastPaint

    Lab048ReleaseDragBase()
    StrategyEditorReleaseFastBase()
    Lab047DragLastPaint := 0
    Lab047DragLastFieldUpdate := 0
    Lab047PanLastPaint := 0

    result := Lab044CanvasMouseDown(wParam, lParam, msg, hwnd)
    if IsObject(LabEditorDragPlacement) {
        if Lab048PrepareInteraction() {
            Lab048PauseHousekeeping()
            Lab047ProfileReset("Drag")
        }
    } else if LabEditorPanActive {
        if Lab048PrepareInteraction() {
            Lab048PauseHousekeeping()
            Lab047ProfileReset("Pan")
        }
    }
    return result
}

Lab047CanvasMouseMove(wParam, lParam, msg, hwnd) {
    global LabEditorDoc, LabEditorDragPlacement, LabEditorDragIndex
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorDragPreviewX, LabEditorDragPreviewY, LabEditorXCtrl, LabEditorYCtrl
    global LabEditorPanActive, LabEditorViewport
    global LabEditorPanStartX, LabEditorPanStartY, LabEditorPanStartCenterX, LabEditorPanStartCenterY
    global LabEditorPanLastMouseX, LabEditorPanLastMouseY
    global Lab047DragLastPaint, Lab047DragLastFieldUpdate, Lab047PanLastPaint
    global Lab048DragInterval, Lab048PanInterval, Lab048SourceBitmap

    if Lab044StrategyRunning() {
        Lab044ReleasePointerCapture(true)
        Lab048DetachPersistentPresentation()
        Lab048ReleaseDragBase()
        Lab048ClearInteractionSource()
        Lab048ResumeHousekeeping()
        return
    }

    drag := LabEditorDragPlacement
    dragIndex := LabEditorDragIndex
    if IsObject(drag) && dragIndex > 0 && IsObject(LabEditorDoc) {
        StrategyEditorGetClientCursor(&mx, &my)
        mx := Max(LabEditorCanvasX, Min(LabEditorCanvasX + LabEditorCanvasW, mx))
        my := Max(LabEditorCanvasY, Min(LabEditorCanvasY + LabEditorCanvasH, my))
        logical := Lab048SourceBitmap ? Lab048ViewportToStrategy(mx, my) : StrategyEditorViewportToStrategy(mx, my)
        if (logical.x = LabEditorDragPreviewX && logical.y = LabEditorDragPreviewY)
            return 0

        LabEditorDragPreviewX := logical.x
        LabEditorDragPreviewY := logical.y
        now := A_TickCount

        if (!Lab047DragLastFieldUpdate || now - Lab047DragLastFieldUpdate >= 100) {
            Lab047DragLastFieldUpdate := now
            if LabEditorControlAlive(LabEditorXCtrl)
                try LabEditorXCtrl.Text := logical.x
            if LabEditorControlAlive(LabEditorYCtrl)
                try LabEditorYCtrl.Text := logical.y
        }

        if (!Lab047DragLastPaint || now - Lab047DragLastPaint >= Lab048DragInterval) {
            Lab047DragLastPaint := now
            started := A_TickCount
            if Lab048RenderDragFrame(dragIndex) {
                elapsed := Max(0, A_TickCount - started)
                Lab047ProfileAdd(elapsed)
                Lab048AdaptInterval("Drag", elapsed)
            }
        }
        return 0
    }

    if !LabEditorPanActive
        return
    if !StrategyEditorIsActive() {
        Lab044ReleasePointerCapture(false)
        Lab048DetachPersistentPresentation()
        Lab048ClearInteractionSource()
        Lab048ResumeHousekeeping()
        return 0
    }

    StrategyEditorGetClientCursor(&mx, &my)
    if (LabEditorPanLastMouseX != "" && mx = LabEditorPanLastMouseX && my = LabEditorPanLastMouseY)
        return 0
    LabEditorPanLastMouseX := mx
    LabEditorPanLastMouseY := my

    visibleW := 1.0 / LabEditorViewport.Zoom
    visibleH := 1.0 / LabEditorViewport.Zoom
    dx := mx - LabEditorPanStartX
    dy := my - LabEditorPanStartY
    LabEditorViewport.CenterX := LabEditorPanStartCenterX - (dx / Max(1, LabEditorCanvasW)) * visibleW
    LabEditorViewport.CenterY := LabEditorPanStartCenterY - (dy / Max(1, LabEditorCanvasH)) * visibleH
    LabEditorViewport.ClampCenter()

    now := A_TickCount
    if (!Lab047PanLastPaint || now - Lab047PanLastPaint >= Lab048PanInterval) {
        Lab047PanLastPaint := now
        started := A_TickCount
        if Lab048RenderPanFrame() {
            elapsed := Max(0, A_TickCount - started)
            Lab047ProfileAdd(elapsed)
            Lab048AdaptInterval("Pan", elapsed)
        }
    }
    return 0
}

Lab047CanvasMouseUp(wParam, lParam, msg, hwnd) {
    global LabEditorDragPlacement, LabEditorPanActive
    kind := IsObject(LabEditorDragPlacement) ? "Drag" : (LabEditorPanActive ? "Pan" : "")

    Lab048DetachPersistentPresentation()
    result := Lab044CanvasMouseUp(wParam, lParam, msg, hwnd)

    Lab048ReleaseDragBase()
    StrategyEditorReleaseFastBase()
    Lab048ClearInteractionSource()
    Lab048ResumeHousekeeping()
    if (kind != "")
        Lab047ProfileAppend(kind)
    return result
}

Lab047CanvasWheel(wParam, lParam, msg, hwnd) {
    Lab048DetachPersistentPresentation()
    Lab048ReleaseDragBase()
    StrategyEditorReleaseFastBase()
    Lab048ClearInteractionSource()
    Lab048ResumeHousekeeping()
    return Lab044CanvasWheel(wParam, lParam, msg, hwnd)
}

OnMessage(0x0111, Lab047Command)
OnExit(Lab048ReleaseResources)

try SetTimer(StrategyEditorWorkspaceMonitor, 250)
try SetTimer(StrategyEditorInteractiveStateGuard, 1500)
