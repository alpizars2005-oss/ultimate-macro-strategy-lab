#Requires AutoHotkey v2.0

; One-shot exact-map capture for the screenshot-only editor.
;
; SpawnTower never performs capture/focus/GDI/file work inline. The compatibility hook
; schedules this worker and immediately returns to the original macro. 0.4.6 fixes the
; important coordinate bug: GetClientRect gives size but NOT screen x/y, so screenshots
; now use WinGetClientPos through LabMapGetRobloxClientRect().

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
    SetTimer(LabMapAutoCaptureDeferred, -2200)
    return ""
}

LabMapAutoCaptureDeferred(*) {
    global gamemap, LabAutoMapCaptureScheduled, LabAutoMapCaptureRetry

    LabAutoMapCaptureScheduled := false
    if !LabAutoMapStrategyRunning() || !IsSet(gamemap)
        return ""

    name := Trim(String(gamemap))
    if (name = "")
        return ""

    cached := LabMapCameraPath(name)
    if (cached != "" && !LabMapCameraNeedsRefresh(name))
        return cached

    ; Never steal foreground focus for an editor screenshot.
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
        if !LabMapGetRobloxClientRect(&x, &y, &w, &h)
            throw Error("Roblox client screen rectangle is not usable.")

        pBitmap := Gdip_BitmapFromScreen(x "|" y "|" w "|" h)
        if !pBitmap
            throw Error("GDI+ could not capture the Roblox client.")

        saved := LabMapSaveCameraBitmap(name, pBitmap, "spawn")
        if (saved = "")
            throw Error("MapLibrary rejected the captured screenshot.")

        if IsSet(LabEditorCurrentMap) && LabEditorCurrentMap = name {
            LabEditorSourceImage := saved
            LabEditorBackgroundMode := "camera"
        }

        LabAutoMapCaptureLog("Captured client-aligned fixed-camera map: " name " [" x "," y " " w "x" h "] -> " saved)
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
