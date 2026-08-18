#Requires AutoHotkey v2.0

; Strategy Lab map library.
; A camera capture made by Ultimate Macro is authoritative for SpawnTower editing.
; Wiki top-down images are reference-only until a future projective calibration is saved.

; Keep the active source bitmap decoded while the user pans/zooms. Previously every
; frame validated the image and decoded it again, which meant two disk/decode passes
; per render. This cache is invalidated automatically when the file timestamp/size changes.
global LabMapRenderCache := {path: "", stamp: "", size: 0, bitmap: 0, width: 0, height: 0}
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

LabMapReferenceDir() {
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
    for ext in ["png", "jpg", "jpeg", "bmp"] {
        path := dir "\" key "." ext
        if !FileExist(path)
            continue
        if LabMapImageUsable(path)
            return path
        ; A previous network error may have left HTML/WebP under a PNG/JPG name.
        ; Purge it so Sync Assets can retry instead of getting stuck forever.
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
    reference := LabMapReferencePath(mapName)
    if (reference != "")
        return {path: reference, mode: "reference", calibrated: false, label: "Wiki top-down reference"}
    return {path: "", mode: "none", calibrated: false, label: "No cached map image"}
}

LabMapSaveCameraCapture(mapName, sourcePath) {
    entry := LabMapResolve(mapName)
    if (entry.key = "" || !FileExist(sourcePath))
        return ""
    target := LabMapCameraDir() "\" entry.key ".png"
    FileCopy(sourcePath, target, true)
    ; If this map was currently cached, force the next render to decode the new capture.
    LabMapInvalidateRenderCache(target)
    return LabMapImageUsable(target) ? target : ""
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

    SourceRect(sourceW, sourceH) {
        sw := Max(1, Round(sourceW / this.Zoom))
        sh := Max(1, Round(sourceH / this.Zoom))
        sx := Round((this.CenterX * sourceW) - sw / 2)
        sy := Round((this.CenterY * sourceH) - sh / 2)
        sx := Max(0, Min(sourceW - sw, sx))
        sy := Max(0, Min(sourceH - sh, sy))
        return {x: sx, y: sy, w: sw, h: sh}
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
        rect := viewport.SourceRect(sourceW, sourceH)
        pOut := Gdip_CreateBitmap(width, height)
        if !pOut
            return false
        graphics := Gdip_GraphicsFromImage(pOut)
        if !graphics
            return false
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
        Gdip_DrawImage(graphics, pSource, 0, 0, width, height, rect.x, rect.y, rect.w, rect.h)
        ; The live viewport is transient. JPEG 84 is visually clean at editor size and
        ; much cheaper to encode/write than the old PNG frame path.
        Gdip_SaveBitmapToFile(pOut, outputPath, 84)
        return FileExist(outputPath)
    } finally {
        if graphics
            try Gdip_DeleteGraphics(graphics)
        if pOut
            try Gdip_DisposeImage(pOut)
        ; pSource belongs to LabMapRenderCache and stays decoded for the next frame.
    }
}
