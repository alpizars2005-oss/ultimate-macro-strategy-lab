#Requires AutoHotkey v2.0

LabTowerSafeKey(value) {
    key := StrLower(Trim(String(value)))
    key := RegExReplace(key, "[^a-z0-9]+", "-")
    return Trim(key, "-")
}

LabTowerCatalogPath() => A_WorkingDir "\Resources\StrategyLab\Towers\catalog.ini"

LabTowerPortraitDir() {
    dir := A_AppData "\Ultimate_Macro\StrategyEditor\TowerLibrary"
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

LabTowerPortraitPath(towerName) {
    entry := LabTowerResolve(towerName)
    for ext in ["png", "jpg", "jpeg", "bmp"] {
        path := LabTowerPortraitDir() "\" entry.key "." ext
        if FileExist(path)
            return path
    }
    placeholder := A_WorkingDir "\Resources\StrategyLab\Towers\placeholder.png"
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
    ; A placement-limit of exactly one is intentionally shown without #1.
    if (entry.placementLimit = 1)
        return entry.name
    return entry.name " #" LabTowerOccurrence(document, placement)
}
