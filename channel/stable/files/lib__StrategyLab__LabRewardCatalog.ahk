#Requires AutoHotkey v2.0

; Reward/drop reference cache. This module is intentionally independent from gameplay
; and the Strategy Editor render loop. Missing network assets are a cosmetic miss only.

global LabRewardCatalogCache := ""
global LabRewardAssetSyncPid := 0
global LabRewardAutoSyncStarted := false

LabRewardSafeKey(value) {
    key := StrLower(Trim(String(value)))
    key := RegExReplace(key, "[^a-z0-9]+", "-")
    return Trim(key, "-")
}

LabRewardCatalogPath() => A_ScriptDir "\Resources\StrategyLab\Rewards\catalog.ini"

LabRewardIconDir() {
    dir := A_AppData "\Ultimate_Macro\StrategyEditor\RewardLibrary"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabRewardCatalog() {
    global LabRewardCatalogCache
    if IsObject(LabRewardCatalogCache)
        return LabRewardCatalogCache

    result := Map()
    path := LabRewardCatalogPath()
    if !FileExist(path) {
        LabRewardCatalogCache := result
        return result
    }

    sections := IniRead(path)
    for section in StrSplit(StrReplace(sections, "`r"), "`n") {
        section := Trim(section)
        if (section = "")
            continue
        entry := {
            key: LabRewardSafeKey(section),
            name: section,
            display: IniRead(path, section, "display", section),
            wikiPage: IniRead(path, section, "wikiPage", section),
            aliases: IniRead(path, section, "aliases", section),
            hints: IniRead(path, section, "hints", section),
            kind: IniRead(path, section, "kind", "reward"),
            core: String(IniRead(path, section, "core", 0)) = "1",
            track: String(IniRead(path, section, "track", 1)) = "1"
        }
        result[entry.key] := entry
        for alias in StrSplit(entry.aliases, "|") {
            aliasKey := LabRewardSafeKey(alias)
            if (aliasKey != "")
                result[aliasKey] := entry
        }
    }
    LabRewardCatalogCache := result
    return result
}

LabRewardResolve(name) {
    catalog := LabRewardCatalog()
    key := LabRewardSafeKey(name)
    if catalog.Has(key)
        return catalog[key]
    return {
        key: key,
        name: Trim(String(name)),
        display: Trim(String(name)),
        wikiPage: Trim(String(name)),
        aliases: Trim(String(name)),
        hints: Trim(String(name)),
        kind: "reward",
        core: false,
        track: true
    }
}

LabRewardCachedIconPath(name) {
    entry := LabRewardResolve(name)
    if (entry.key = "")
        return ""
    for ext in ["jpg", "jpeg", "png", "bmp"] {
        path := LabRewardIconDir() "\" entry.key "." ext
        if FileExist(path) && FileGetSize(path) > 200
            return path
    }
    return ""
}

LabRewardIconPath(name) => LabRewardCachedIconPath(name)

LabRewardCoreNames() {
    result := []
    seen := Map()
    for _, entry in LabRewardCatalog() {
        if !entry.core || seen.Has(entry.key)
            continue
        seen[entry.key] := true
        result.Push(entry.name)
    }
    return result
}

LabRewardMissingCoreNames() {
    missing := []
    for name in LabRewardCoreNames() {
        if (LabRewardCachedIconPath(name) = "")
            missing.Push(name)
    }
    return missing
}

LabRewardJoinNames(names) {
    text := ""
    for name in names
        text .= (text != "" ? "|" : "") name
    return text
}

LabRewardMaybeSyncAssets(*) {
    global LabRewardAssetSyncPid, LabRewardAutoSyncStarted
    if LabRewardAutoSyncStarted
        return
    LabRewardAutoSyncStarted := true

    missing := LabRewardMissingCoreNames()
    if (missing.Length = 0)
        return

    helper := A_ScriptDir "\submacros\lab_reward_assets.ps1"
    if !FileExist(helper)
        return

    names := LabRewardJoinNames(missing)
    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' helper
        . '" -InstallDir "' A_ScriptDir '" -Names "' StrReplace(names, '"', '') '"'
    try Run(cmd, A_ScriptDir, "Hide", &LabRewardAssetSyncPid)
}

; Cosmetic/network work is delayed until well after startup and never blocks Editor boot.
SetTimer(LabRewardMaybeSyncAssets, -6000)
