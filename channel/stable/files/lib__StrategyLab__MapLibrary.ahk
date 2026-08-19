#Requires AutoHotkey v2.0

; Strategy Lab map library.
; The authoritative editor background is the exact Roblox client view captured with the
; same fixed Ultimate Macro camera that produced the SpawnTower coordinates. Wiki maps
; are never used for coordinate editing.

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
    ; Kept only for backwards-compatible cleanup/migration. The 0.4+ editor does not
    ; use web/top-down reference images for coordinate editing.
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
    ; 0.4.3 writes JPEG first. Check it before legacy PNG so a stale 0.4.2 capture can
    ; never win after a successful refresh.
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

LabMapCameraCaptureStage(mapName) {
    meta := LabMapCameraMetaPath(mapName)
    if (meta = "" || !FileExist(meta))
        return ""
    try return Trim(IniRead(meta, "Capture", "Stage", ""))
    catch
        return ""
}

LabMapCameraNeedsRefresh(mapName) {
    camera := LabMapCameraPath(mapName)
    if (camera = "")
        return true
    ; 0.4.2 could capture the map-vote/lobby screen before the match. It wrote no
    ; metadata, so one successful SpawnTower-stage capture transparently replaces it.
    return LabMapCameraCaptureStage(mapName) = ""
}

LabMapWriteCameraMeta(mapName, stage, width := 0, height := 0) {
    meta := LabMapCameraMetaPath(mapName)
    if (meta = "")
        return
    try {
        IniWrite(stage, meta, "Capture", "Stage")
        IniWrite("0.4.3", meta, "Capture", "WriterVersion")
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

; Save from an already-decoded bitmap. This is the preferred auto-capture path: no
; intermediate PNG and no FileCopy over a GDI+-locked image.
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
        ; JPEG 86 keeps text/terrain crisp enough for a placement canvas while making
        ; the persistent map library dramatically smaller than full-resolution PNG.
        Gdip_SaveBitmapToFile(pBitmap, temp, 86)
        if !FileExist(temp) || FileGetSize(temp) < 1000 || !LabMapImageUsable(temp)
            throw Error("Encoded camera screenshot is not usable.")

        ; Critical ordering: the renderer may hold the old target decoded. Releasing
        ; that bitmap BEFORE replacement avoids Windows ERROR_SHARING_VIOLATION/
        ; generic FileCopy failures when an editor is open during auto-capture.
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

; Compatibility path for the manual Capture Map button and older callers.
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

; Retained for callers outside the live Editor. The editor itself renders directly to
; an in-memory HBITMAP in StrategyEditorMaps.ahk and therefore does not use this helper
; while dragging/panning.
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
        Gdip_SaveBitmapToFile(pOut, outputPath, 84)
        return FileExist(outputPath)
    } finally {
        if graphics
            try Gdip_DeleteGraphics(graphics)
        if pOut
            try Gdip_DisposeImage(pOut)
    }
}
