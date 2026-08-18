#Requires AutoHotkey v2.0

global LabTowerResolvedPortraitCache := Map()

LabTowerSafeKey(value) {
    key := StrLower(Trim(String(value)))
    key := RegExReplace(key, "[^a-z0-9]+", "-")
    return Trim(key, "-")
}

LabTowerCatalogPath() => A_ScriptDir "\Resources\StrategyLab\Towers\catalog.ini"

LabTowerPortraitDir() {
    dir := A_AppData "\Ultimate_Macro\StrategyEditor\TowerLibrary"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabTowerPreviewDir() {
    dir := LabTowerPortraitDir() "\preview"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabTowerCatalog() {
    result := Map()
    path := LabTowerCatalogPath()
    if !FileExist(path)
        return result
    sections := IniRead(path)
    for section in StrSplit(StrReplace(sections, "`r"), "`n") {
        section := Trim(section)
        if (section = "")
            continue
        entry := {
            key: LabTowerSafeKey(section),
            name: IniRead(path, section, "display", section),
            wikiPage: IniRead(path, section, "wikiPage", section),
            placementLimit: Integer(IniRead(path, section, "placementLimit", 0)),
            aliases: IniRead(path, section, "aliases", section)
        }
        result[entry.key] := entry
        for alias in StrSplit(entry.aliases, "|") {
            aliasKey := LabTowerSafeKey(alias)
            if (aliasKey != "")
                result[aliasKey] := entry
        }
    }
    return result
}

LabTowerResolve(towerName) {
    key := LabTowerSafeKey(towerName)
    catalog := LabTowerCatalog()
    if catalog.Has(key)
        return catalog[key]
    return {key: key, name: Trim(String(towerName)), wikiPage: Trim(String(towerName)), placementLimit: 0, aliases: towerName}
}

LabTowerImageUsable(path) {
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

LabTowerCachedPortraitPath(towerName) {
    global LabTowerResolvedPortraitCache
    entry := LabTowerResolve(towerName)

    if LabTowerResolvedPortraitCache.Has(entry.key) {
        cachedPath := LabTowerResolvedPortraitCache[entry.key]
        if FileExist(cachedPath)
            return cachedPath
        LabTowerResolvedPortraitCache.Delete(entry.key)
    }

    for ext in ["png", "jpg", "jpeg", "bmp"] {
        path := LabTowerPortraitDir() "\" entry.key "." ext
        if !FileExist(path)
            continue
        if LabTowerImageUsable(path) {
            LabTowerResolvedPortraitCache[entry.key] := path
            return path
        }
        try FileDelete(path)
    }
    return ""
}

; Native Picture controls can crop wide/tall wiki art when both control dimensions
; are fixed. Build one small square presentation cache per tower instead: the entire
; source image is scaled with aspect ratio preserved, padded and centered on the same
; dark surface used by Strategy Lab. The downloaded original cache remains untouched.
LabTowerPreparePreview(sourcePath, key) {
    if (sourcePath = "" || !FileExist(sourcePath) || key = "")
        return ""

    preview := LabTowerPreviewDir() "\" key ".jpg"
    sourceStamp := ""
    previewStamp := ""
    previewSize := 0
    try sourceStamp := FileGetTime(sourcePath, "M")
    try previewStamp := FileGetTime(preview, "M")
    try previewSize := FileGetSize(preview)
    if FileExist(preview) && previewStamp != "" && sourceStamp != ""
        && previewStamp >= sourceStamp && previewSize >= 1500
        return preview

    pSource := 0
    pCanvas := 0
    graphics := 0
    brush := 0
    temp := preview ".tmp.jpg"
    try {
        pSource := Gdip_CreateBitmapFromFile(sourcePath)
        if !pSource
            return ""
        sourceW := Gdip_GetImageWidth(pSource)
        sourceH := Gdip_GetImageHeight(pSource)
        if (sourceW <= 0 || sourceH <= 0)
            return ""

        canvasSize := 320
        padding := 22
        usable := canvasSize - (padding * 2)
        scale := Min(usable / sourceW, usable / sourceH)
        drawW := Max(1, Round(sourceW * scale))
        drawH := Max(1, Round(sourceH * scale))
        drawX := Floor((canvasSize - drawW) / 2)
        drawY := Floor((canvasSize - drawH) / 2)

        pCanvas := Gdip_CreateBitmap(canvasSize, canvasSize)
        if !pCanvas
            return ""
        graphics := Gdip_GraphicsFromImage(pCanvas)
        if !graphics
            return ""
        brush := Gdip_BrushCreateSolid(0xFF15191F)
        Gdip_FillRectangle(graphics, brush, 0, 0, canvasSize, canvasSize)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
        Gdip_DrawImage(graphics, pSource, drawX, drawY, drawW, drawH, 0, 0, sourceW, sourceH)

        if FileExist(temp)
            try FileDelete(temp)
        Gdip_SaveBitmapToFile(pCanvas, temp, 90)
        if !FileExist(temp) || FileGetSize(temp) < 1500
            return ""
        if FileExist(preview)
            FileDelete(preview)
        FileMove(temp, preview, 1)
        return preview
    } catch {
        return ""
    } finally {
        if brush
            try Gdip_DeleteBrush(brush)
        if graphics
            try Gdip_DeleteGraphics(graphics)
        if pCanvas
            try Gdip_DisposeImage(pCanvas)
        if pSource
            try Gdip_DisposeImage(pSource)
        if FileExist(temp)
            try FileDelete(temp)
    }
}

LabTowerPortraitPath(towerName) {
    entry := LabTowerResolve(towerName)
    cached := LabTowerCachedPortraitPath(towerName)
    if (cached != "") {
        preview := LabTowerPreparePreview(cached, entry.key)
        return preview != "" ? preview : cached
    }
    placeholder := A_ScriptDir "\Resources\StrategyLab\Towers\placeholder.png"
    return FileExist(placeholder) ? placeholder : ""
}

LabTowerOccurrence(document, placement) {
    occurrence := 0
    targetSlot := String(placement.slot)
    for candidate in document.Placements {
        if (String(candidate.slot) = targetSlot)
            occurrence += 1
        if (candidate = placement)
            return occurrence
    }
    return 1
}

LabTowerPlacementDisplay(document, placement) {
    rawTower := document.TowerNameForSlot(placement.slot)
    if (rawTower = "")
        rawTower := "Slot " placement.slot
    entry := LabTowerResolve(rawTower)
    if (entry.placementLimit = 1)
        return entry.name
    return entry.name " #" LabTowerOccurrence(document, placement)
}

LabTowerPlacementMeta(document, placement) {
    rawTower := document.TowerNameForSlot(placement.slot)
    if (rawTower = "")
        rawTower := "Slot " placement.slot
    entry := LabTowerResolve(rawTower)
    occurrence := LabTowerOccurrence(document, placement)
    limitText := entry.placementLimit = 1
        ? "Unique placement"
        : (entry.placementLimit > 1 ? "Placement " occurrence " of " entry.placementLimit : "Placement " occurrence)
    return "Slot " placement.slot "  •  " limitText
}
