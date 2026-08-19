#Requires AutoHotkey v2.0

; Loaded by submacros/watchdog.ahk, not by Main_Lab.
; The watchdog already owns reliable Triumph/Loss detection, so this is the safest place
; to preserve a post-run reference before RestartMain. Failure here is always cosmetic:
; the outcome flow and macro restart must continue regardless.

LabWatchdogSafeKey(value) {
    key := StrLower(Trim(String(value)))
    key := RegExReplace(key, "[^a-z0-9]+", "-")
    return Trim(key, "-")
}

LabWatchdogLog(message) {
    try {
        dir := A_AppData "\Ultimate_Macro\StrategyEditor"
        if !DirExist(dir)
            DirCreate(dir)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n",
            dir "\postrun-capture.log", "UTF-8")
    }
}

LabWatchdogClientRect(&x, &y, &w, &h) {
    x := 0, y := 0, w := 0, h := 0
    hwnd := 0
    try hwnd := GetRobloxHWND()
    if !hwnd
        return false
    try WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwnd)
    catch
        return false
    return w >= 100 && h >= 100
}

LabWatchdogCaptureOutcome(result) {
    global StateFile

    outcome := Trim(String(result))
    if (outcome = "")
        return ""

    strategyPath := ""
    try strategyPath := IniRead(StateFile, "State", "Strategy", "")
    if (strategyPath = "" || !FileExist(strategyPath)) {
        LabWatchdogLog("Skipped " outcome " reference: current strategy path is unavailable.")
        return ""
    }

    mapName := ""
    try mapName := IniRead(strategyPath, "Settings", "map", "")
    if (mapName = "") {
        LabWatchdogLog("Skipped " outcome " reference: strategy has no map setting.")
        return ""
    }

    key := LabWatchdogSafeKey(mapName)
    if (key = "")
        return ""

    if !LabWatchdogClientRect(&x, &y, &w, &h) {
        LabWatchdogLog("Skipped " outcome " reference: Roblox client rectangle unavailable.")
        return ""
    }

    root := A_AppData "\Ultimate_Macro\StrategyEditor\MapLibrary\postrun\" key
    try {
        if !DirExist(root)
            DirCreate(root)
    } catch Error as err {
        LabWatchdogLog("Could not create post-run directory: " err.Message)
        return ""
    }

    stamp := FormatTime(, "yyyyMMdd-HHmmss")
    safeOutcome := StrLower(RegExReplace(outcome, "[^A-Za-z0-9]+", "-"))
    target := root "\" stamp "-" safeOutcome ".jpg"
    pBitmap := 0
    try {
        pBitmap := Gdip_BitmapFromScreen(x "|" y "|" w "|" h)
        if !pBitmap
            throw Error("GDI+ capture failed.")
        Gdip_SaveBitmapToFile(pBitmap, target, 88)
        if !FileExist(target) || FileGetSize(target) < 1000
            throw Error("Encoded post-run reference is unusable.")

        latest := A_AppData "\Ultimate_Macro\StrategyEditor\MapLibrary\postrun\latest.ini"
        IniWrite(mapName, latest, "Capture", "Map")
        IniWrite(outcome, latest, "Capture", "Result")
        IniWrite(target, latest, "Capture", "Image")
        IniWrite(strategyPath, latest, "Capture", "Strategy")
        IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), latest, "Capture", "CapturedAt")
        IniWrite(w, latest, "Capture", "Width")
        IniWrite(h, latest, "Capture", "Height")

        LabWatchdogLog("Captured " outcome " client reference for " mapName " -> " target)
    } catch Error as err {
        LabWatchdogLog("Post-run capture failed for " mapName ": " err.Message)
        return ""
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
    }

    ; Analyze outside the watchdog process. It may take a second; RestartMain must not
    ; wait for image processing or calibration.
    worker := A_WorkingDir "\submacros\lab_postrun_calibrate.ps1"
    if FileExist(worker) {
        cleanTarget := StrReplace(target, '"', '')
        cleanStrategy := StrReplace(strategyPath, '"', '')
        cleanMap := StrReplace(mapName, '"', '')
        cleanResult := StrReplace(outcome, '"', '')
        cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' worker
            . '" -InstallDir "' A_WorkingDir '" -Screenshot "' cleanTarget
            . '" -StrategyPath "' cleanStrategy '" -MapName "' cleanMap
            . '" -Result "' cleanResult '"'
        try Run(cmd, A_WorkingDir, "Hide")
        catch Error as err
            LabWatchdogLog("Calibration worker could not start: " err.Message)
    }
    return target
}
