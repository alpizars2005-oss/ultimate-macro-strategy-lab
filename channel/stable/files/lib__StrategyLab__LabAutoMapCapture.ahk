#Requires AutoHotkey v2.0

; One-shot exact-map capture for the screenshot-only editor.
;
; 0.4.4 rule: SpawnTower must never perform screenshot, GUI, file or GDI+ work inline.
; The preflight compatibility hook may still call LabMapAutoCaptureCurrent(), but that
; function only schedules a deferred attempt and returns immediately. Gameplay clicks
; therefore retain their original ordering/timing.

global LabAutoMapCaptureBusy := false
global LabAutoMapCaptureScheduled := false
global LabAutoMapCaptureRetry := 0

LabAutoMapCaptureLog(message) {
    try {
        dir := A_AppData "\Ultimate_Macro\StrategyEditor"
        if !DirExist(dir)
            DirCreate(dir)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n",
            dir "\auto-map-capture.log", "UTF-8")
    }
}

LabAutoMapStrategyRunning() {
    global RunningStrategy
    if !IsSet(RunningStrategy)
        return false
    try return !!RunningStrategy
    catch
        return false
}

; Compatibility entry point injected by 0.4.3 preflight at SpawnTower entry. In 0.4.4
; it is intentionally constant-time: no disk lookup, no image decode, no WinActivate,
; no Hide/Show, no getRobloxPos and no GDI+.
LabMapAutoCaptureCurrent(*) {
    global gamemap, LabAutoMapCaptureScheduled, LabAutoMapCaptureRetry

    if !IsSet(gamemap)
        return ""
    if (Trim(String(gamemap)) = "")
        return ""
    if LabAutoMapCaptureScheduled
        return ""

    LabAutoMapCaptureScheduled := true
    LabAutoMapCaptureRetry := 0
    ; Give the original SpawnTower thread ample time to execute its real slot/placement
    ; clicks first. The fixed macro camera does not change after that first placement.
    SetTimer(LabMapAutoCaptureDeferred, -2200)
    return ""
}

LabMapAutoCaptureDeferred(*) {
    global gamemap, LabAutoMapCaptureScheduled, LabAutoMapCaptureRetry

    LabAutoMapCaptureScheduled := false
    if !LabAutoMapStrategyRunning()
        return ""
    if !IsSet(gamemap)
        return ""

    name := Trim(String(gamemap))
    if (name = "")
        return ""

    cached := LabMapCameraPath(name)
    if (cached != "" && !LabMapCameraNeedsRefresh(name))
        return cached

    ; Never alter foreground focus to obtain an editor picture. If Roblox is not the
    ; active window, retry later instead of touching MainGui/WinActivate and risking the
    ; macro's absolute Click commands.
    if !WinActive("ahk_exe RobloxPlayerBeta.exe") {
        if (LabAutoMapCaptureRetry < 8) {
            LabAutoMapCaptureRetry += 1
            LabAutoMapCaptureScheduled := true
            SetTimer(LabMapAutoCaptureDeferred, -750)
        } else {
            LabAutoMapCaptureLog("Deferred capture gave up waiting for Roblox foreground: " name)
        }
        return ""
    }

    return LabMapAutoCaptureIfMissing(name)
}

LabMapAutoCaptureIfMissing(mapName) {
    global LabAutoMapCaptureBusy
    global LabEditorCurrentMap, LabEditorSourceImage, LabEditorBackgroundMode

    name := Trim(String(mapName))
    if (name = "")
        return ""

    cached := LabMapCameraPath(name)
    if (cached != "" && !LabMapCameraNeedsRefresh(name))
        return cached

    if LabAutoMapCaptureBusy
        return ""
    if !WinExist("ahk_exe RobloxPlayerBeta.exe")
        return ""
    if !WinActive("ahk_exe RobloxPlayerBeta.exe") {
        LabAutoMapCaptureLog("Skipped capture because Roblox was not foreground: " name)
        return ""
    }

    LabAutoMapCaptureBusy := true
    pBitmap := 0
    try {
        getRobloxPos(&x, &y, &w, &h)
        if (w < 100 || h < 100)
            throw Error("Roblox client area is not usable.")

        ; No GUI/focus operations occur here. Gameplay has already had >2 seconds to
        ; complete the first SpawnTower click sequence, while the authoritative fixed
        ; macro camera remains unchanged.
        pBitmap := Gdip_BitmapFromScreen(x "|" y "|" w "|" h)
        if !pBitmap
            throw Error("GDI+ could not capture Roblox.")

        saved := LabMapSaveCameraBitmap(name, pBitmap, "runtime-deferred")
        if (saved = "")
            throw Error("MapLibrary rejected the captured screenshot.")

        if IsSet(LabEditorCurrentMap) && LabEditorCurrentMap = name {
            LabEditorSourceImage := saved
            LabEditorBackgroundMode := "camera"
        }

        LabAutoMapCaptureLog("Captured deferred fixed-camera map: " name " -> " saved)
        return saved
    } catch Error as err {
        LabAutoMapCaptureLog("Capture failed for " name ": " err.Message)
        return ""
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
        LabAutoMapCaptureBusy := false
    }
}
