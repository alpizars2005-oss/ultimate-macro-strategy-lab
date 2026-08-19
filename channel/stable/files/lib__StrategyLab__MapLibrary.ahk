#Requires AutoHotkey v2.0

; Strategy Lab map library.
; The editor uses the exact Roblox CLIENT image, not a screen-origin crop. Ultimate
; Macro records SpawnTower coordinates in the 1920x1009 client coordinate space.
;
; 0.4.6 also exposes a playable ROI which stops just above the hotbar. This removes UI
; pixels that can never contain a valid placement while preserving strategy coordinates
; through a matching forward/inverse projection.

global LabMapRenderCache := {path: "", stamp: "", size: 0, bitmap: 0, width: 0, height: 0}
global LabMapReferenceWidth := 1920.0
global LabMapReferenceHeight := 1009.0
global LabMapPlayableBottomReference := 918.0
OnExit(LabMapReleaseRenderCache)

LabMapSafeKey(value) {
    key := StrLower(Trim(String(value)))
    key := RegExReplace(key, "[^a-z0-9]+", "-")
    return Trim(key, "-")
}

LabMapRoot() {
    dir := A_AppData "\Ultimate_Macro\StrategyEditor\MapLibrary"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabMapCameraDir() {
    dir := LabMapRoot() "\camera"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabMapCalibrationDir() {
    dir := LabMapRoot() "\calibration"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabMapPostRunDir() {
    dir := LabMapRoot() "\postrun"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabMapReferenceDir() {
    ; Backwards-compatible cleanup only. Web map art is never used for coordinate work.
    dir := LabMapRoot() "\reference"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabMapCatalogPath() => A_ScriptDir "\Resources\StrategyLab\Maps\catalog.ini"

LabMapCatalog() {
    result := Map()
    path := LabMapCatalogPath()
    if !FileExist(path)
        return result
    sections := IniRead(path)
    for section in StrSplit(StrReplace(sections, "`r"), "`n") {
        section := Trim(section)
        if (section = "")
            continue
        key := LabMapSafeKey(section)
        aliases := IniRead(path, section, "aliases", section)
        entry := {
            key: key,
            name: IniRead(path, section, "display", section),
            wikiPage: IniRead(path, section, "wikiPage", section),
            aliases: aliases
        }
        result[key] := entry
        for alias in StrSplit(aliases, "|") {
            aliasKey := LabMapSafeKey(alias)
            if (aliasKey != "")
                result[aliasKey] := entry
        }
    }
    return result
}

LabMapResolve(mapName) {
    key := LabMapSafeKey(mapName)
    catalog := LabMapCatalog()
    if catalog.Has(key)
        return catalog[key]
    return {key: key, name: Trim(String(mapName)), wikiPage: Trim(String(mapName)), aliases: mapName}
}

; IMPORTANT: getRobloxPos() in the upstream macro intentionally returns client SIZE but
; x/y=0 because it wraps GetClientRect. Gdip_BitmapFromScreen needs SCREEN coordinates.
; WinGetClientPos is therefore the authoritative capture rectangle.
LabMapGetRobloxClientRect(&x, &y, &width, &height) {
    x := 0, y := 0, width := 0, height := 0
    hwnd := 0
    try hwnd := GetRobloxHWND()
    if !hwnd
        return false
    try WinGetClientPos(&x, &y, &width, &height, "ahk_id " hwnd)
    catch
        return false
    return width >= 100 && height >= 100
}

LabMapImageUsable(path) {
    if (path = "" || !FileExist(path))
        return false
    pBitmap := 0
    try {
        pBitmap := Gdip_CreateBitmapFromFile(path)
        if !pBitmap
            return false
        return Gdip_GetImageWidth(pBitmap) > 0 && Gdip_GetImageHeight(pBitmap) > 0
    } catch {
        return false
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
    }
}

LabMapFindCachedFile(dir, key) {
    for ext in ["jpg", "jpeg", "png", "bmp"] {
        path := dir "\" key "." ext
        if !FileExist(path)
            continue
        if LabMapImageUsable(path)
            return path
        try FileDelete(path)
    }
    return ""
}

LabMapCameraPath(mapName) {
    entry := LabMapResolve(mapName)
    return LabMapFindCachedFile(LabMapCameraDir(), entry.key)
}

LabMapReferencePath(mapName) {
    entry := LabMapResolve(mapName)
    return LabMapFindCachedFile(LabMapReferenceDir(), entry.key)
}

LabMapPreferredBackground(mapName) {
    camera := LabMapCameraPath(mapName)
    if (camera != "")
        return {path: camera, mode: "camera", calibrated: true, label: "Macro camera library"}
    return {path: "", mode: "none", calibrated: false, label: "No exact camera screenshot"}
}

LabMapCameraMetaPath(mapName) {
    entry := LabMapResolve(mapName)
    return entry.key != "" ? LabMapCameraDir() "\" entry.key ".meta.ini" : ""
}

LabMapCameraMetaValue(mapName, key, fallback := "") {
    meta := LabMapCameraMetaPath(mapName)
    if (meta = "" || !FileExist(meta))
        return fallback
    try return IniRead(meta, "Capture", key, fallback)
    catch
        return fallback
}

LabMapCameraCaptureStage(mapName) => Trim(String(LabMapCameraMetaValue(mapName, "Stage", "")))

LabMapCameraNeedsRefresh(mapName) {
    camera := LabMapCameraPath(mapName)
    if (camera = "")
        return true

    ; Captures through 0.4.5 used GetClientRect size with screen x/y=0. On a normal
    ; maximized Roblox window that included the title bar and shifted every placement.
    ; Only a capture explicitly tagged ClientAligned=1 is trusted from 0.4.6 onward.
    if String(LabMapCameraMetaValue(mapName, "ClientAligned", 0)) != "1"
        return true
    return LabMapCameraCaptureStage(mapName) = ""
}

LabMapWriteCameraMeta(mapName, stage, width := 0, height := 0) {
    global LabMapPlayableBottomReference
    meta := LabMapCameraMetaPath(mapName)
    if (meta = "")
        return
    try {
        IniWrite(stage, meta, "Capture", "Stage")
        IniWrite("0.4.6", meta, "Capture", "WriterVersion")
        IniWrite(1, meta, "Capture", "ClientAligned")
        IniWrite(LabMapPlayableBottomReference, meta, "Capture", "PlayableBottomReference")
        IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), meta, "Capture", "CapturedAt")
        if (width > 0)
            IniWrite(width, meta, "Capture", "Width")
        if (height > 0)
            IniWrite(height, meta, "Capture", "Height")
    }
}

LabMapRemoveCameraVariants(key, keepPath := "") {
    if (key = "")
        return
    for ext in ["jpg", "jpeg", "png", "bmp"] {
        path := LabMapCameraDir() "\" key "." ext
        if (keepPath != "" && path = keepPath)
            continue
        if FileExist(path)
            try FileDelete(path)
    }
}

LabMapSaveCameraBitmap(mapName, pBitmap, stage := "manual") {
    entry := LabMapResolve(mapName)
    if (entry.key = "" || !pBitmap)
        return ""

    width := 0
    height := 0
    try width := Gdip_GetImageWidth(pBitmap)
    try height := Gdip_GetImageHeight(pBitmap)
    if (width < 100 || height < 100)
        return ""

    dir := LabMapCameraDir()
    target := dir "\" entry.key ".jpg"
    temp := dir "\." entry.key "." A_TickCount ".tmp.jpg"
    if FileExist(temp)
        try FileDelete(temp)

    try {
        Gdip_SaveBitmapToFile(pBitmap, temp, 86)
        if !FileExist(temp) || FileGetSize(temp) < 1000 || !LabMapImageUsable(temp)
            throw Error("Encoded camera screenshot is not usable.")

        LabMapReleaseRenderCache()
        LabMapRemoveCameraVariants(entry.key)
        FileMove(temp, target, 1)
        if !LabMapImageUsable(target)
            throw Error("Final camera screenshot is not usable.")

        LabMapWriteCameraMeta(mapName, stage, width, height)
        return target
    } catch {
        return ""
    } finally {
        if FileExist(temp)
            try FileDelete(temp)
    }
}

LabMapSaveCameraCapture(mapName, sourcePath, stage := "manual") {
    if (sourcePath = "" || !FileExist(sourcePath))
        return ""
    pBitmap := 0
    try {
        pBitmap := Gdip_CreateBitmapFromFile(sourcePath)
        if !pBitmap
            return ""
        return LabMapSaveCameraBitmap(mapName, pBitmap, stage)
    } catch {
        return ""
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
    }
}

LabMapPlayableRatio() {
    global LabMapReferenceHeight, LabMapPlayableBottomReference
    return LabMapPlayableBottomReference / LabMapReferenceHeight
}

LabMapPlayableStrategyHeight(strategyHeight) {
    return Max(1.0, Number(strategyHeight) * LabMapPlayableRatio())
}

LabMapPlayableSourceHeight(sourceHeight) {
    return Max(1, Floor(Number(sourceHeight) * LabMapPlayableRatio()))
}

LabMapCalibrationPath(mapName) {
    entry := LabMapResolve(mapName)
    return entry.key != "" ? LabMapCalibrationDir() "\" entry.key ".ini" : ""
}

LabMapCalibration(mapName) {
    ; The default 26 px/unit comes from the actual TDS cyan placement outline measured
    ; in the canonical 1920-wide client: an Average/1.5 Operator ring is ~78px across.
    result := {pixelsPerUnit: 26.0, offsetX: 0.0, offsetY: 0.0, samples: 0, confidence: 0.0, source: "visual-default"}
    path := LabMapCalibrationPath(mapName)
    if (path = "" || !FileExist(path))
        return result
    try {
        ppu := IniRead(path, "Geometry", "PixelsPerUnit", result.pixelsPerUnit)
        ox := IniRead(path, "Geometry", "OffsetX", 0)
        oy := IniRead(path, "Geometry", "OffsetY", 0)
        samples := IniRead(path, "Geometry", "Samples", 0)
        confidence := IniRead(path, "Geometry", "Confidence", 0)
        source := IniRead(path, "Geometry", "Source", "postrun")
        if IsNumber(ppu) && Number(ppu) >= 16 && Number(ppu) <= 40
            result.pixelsPerUnit := Number(ppu)
        if IsNumber(ox) && Abs(Number(ox)) <= 50
            result.offsetX := Number(ox)
        if IsNumber(oy) && Abs(Number(oy)) <= 50
            result.offsetY := Number(oy)
        if IsNumber(samples)
            result.samples := Integer(samples)
        if IsNumber(confidence)
            result.confidence := Number(confidence)
        result.source := source
    }
    return result
}

LabMapApplyCalibrationPoint(mapName, x, y) {
    c := LabMapCalibration(mapName)
    return {x: Number(x) + c.offsetX, y: Number(y) + c.offsetY}
}

LabMapRemoveCalibrationPoint(mapName, x, y) {
    c := LabMapCalibration(mapName)
    return {x: Number(x) - c.offsetX, y: Number(y) - c.offsetY}
}

LabMapInvalidateRenderCache(path := "") {
    global LabMapRenderCache
    if (path != "" && LabMapRenderCache.path != path)
        return
    LabMapReleaseRenderCache()
}

LabMapReleaseRenderCache(*) {
    global LabMapRenderCache
    if IsObject(LabMapRenderCache) && LabMapRenderCache.bitmap
        try Gdip_DisposeImage(LabMapRenderCache.bitmap)
    LabMapRenderCache := {path: "", stamp: "", size: 0, bitmap: 0, width: 0, height: 0}
}

LabMapAcquireRenderBitmap(path, &width, &height) {
    global LabMapRenderCache
    width := 0
    height := 0
    if (path = "" || !FileExist(path))
        return 0

    stamp := ""
    size := 0
    try stamp := FileGetTime(path, "M")
    try size := FileGetSize(path)

    if (LabMapRenderCache.bitmap
        && LabMapRenderCache.path = path
        && LabMapRenderCache.stamp = stamp
        && LabMapRenderCache.size = size) {
        width := LabMapRenderCache.width
        height := LabMapRenderCache.height
        return LabMapRenderCache.bitmap
    }

    LabMapReleaseRenderCache()
    pBitmap := 0
    try pBitmap := Gdip_CreateBitmapFromFile(path)
    if !pBitmap
        return 0

    width := Gdip_GetImageWidth(pBitmap)
    height := Gdip_GetImageHeight(pBitmap)
    if (width <= 0 || height <= 0) {
        try Gdip_DisposeImage(pBitmap)
        return 0
    }

    LabMapRenderCache := {
        path: path,
        stamp: stamp,
        size: size,
        bitmap: pBitmap,
        width: width,
        height: height
    }
    return pBitmap
}

class LabMapViewport {
    __New() {
        this.Zoom := 1.0
        this.CenterX := 0.5
        this.CenterY := 0.5
    }

    Reset() {
        this.Zoom := 1.0
        this.CenterX := 0.5
        this.CenterY := 0.5
    }

    SetZoom(value) {
        this.Zoom := Max(1.0, Min(4.0, Number(value)))
        this.ClampCenter()
    }

    ZoomBy(delta) => this.SetZoom(this.Zoom + delta)

    Pan(dx, dy) {
        visibleW := 1.0 / this.Zoom
        visibleH := 1.0 / this.Zoom
        this.CenterX += Number(dx) * visibleW
        this.CenterY += Number(dy) * visibleH
        this.ClampCenter()
    }

    ClampCenter() {
        halfW := 0.5 / this.Zoom
        halfH := 0.5 / this.Zoom
        this.CenterX := Max(halfW, Min(1.0 - halfW, this.CenterX))
        this.CenterY := Max(halfH, Min(1.0 - halfH, this.CenterY))
    }

    SourceRect(sourceW, sourceH, contentRatio := 1.0) {
        contentH := Max(1, Floor(sourceH * Max(0.1, Min(1.0, Number(contentRatio)))))
        sw := Max(1, Round(sourceW / this.Zoom))
        sh := Max(1, Round(contentH / this.Zoom))
        sx := Round((this.CenterX * sourceW) - sw / 2)
        sy := Round((this.CenterY * contentH) - sh / 2)
        sx := Max(0, Min(sourceW - sw, sx))
        sy := Max(0, Min(contentH - sh, sy))
        return {x: sx, y: sy, w: sw, h: sh, contentH: contentH}
    }

    StrategyToViewport(x, y, strategyW, strategyH, viewportW, viewportH) {
        normalizedX := Number(x) / Max(1, strategyW)
        normalizedY := Number(y) / Max(1, strategyH)
        visibleW := 1.0 / this.Zoom
        visibleH := 1.0 / this.Zoom
        left := this.CenterX - visibleW / 2
        top := this.CenterY - visibleH / 2
        px := ((normalizedX - left) / visibleW) * viewportW
        py := ((normalizedY - top) / visibleH) * viewportH
        return {x: Round(px), y: Round(py), visible: px >= 0 && px <= viewportW && py >= 0 && py <= viewportH}
    }

    ViewportToStrategy(px, py, strategyW, strategyH, viewportW, viewportH) {
        visibleW := 1.0 / this.Zoom
        visibleH := 1.0 / this.Zoom
        left := this.CenterX - visibleW / 2
        top := this.CenterY - visibleH / 2
        normalizedX := left + (Number(px) / Max(1, viewportW)) * visibleW
        normalizedY := top + (Number(py) / Max(1, viewportH)) * visibleH
        return {
            x: Round(Max(0, Min(1, normalizedX)) * strategyW),
            y: Round(Max(0, Min(1, normalizedY)) * strategyH)
        }
    }
}

LabMapRenderViewport(sourcePath, viewport, outputPath, width, height) {
    pSource := LabMapAcquireRenderBitmap(sourcePath, &sourceW, &sourceH)
    if !pSource || sourceW <= 0 || sourceH <= 0
        return false

    pOut := 0
    graphics := 0
    try {
        rect := viewport.SourceRect(sourceW, sourceH, LabMapPlayableRatio())
        pOut := Gdip_CreateBitmap(width, height)
        if !pOut
            return false
        graphics := Gdip_GraphicsFromImage(pOut)
        if !graphics
            return false
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
        Gdip_DrawImage(graphics, pSource, 0, 0, width, height, rect.x, rect.y, rect.w, rect.h)
        Gdip_SaveBitmapToFile(pOut, outputPath, 84)
        return FileExist(outputPath)
    } finally {
        if graphics
            try Gdip_DeleteGraphics(graphics)
        if pOut
            try Gdip_DisposeImage(pOut)
    }
}
