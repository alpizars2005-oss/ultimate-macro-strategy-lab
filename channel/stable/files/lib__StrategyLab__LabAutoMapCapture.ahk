#Requires AutoHotkey v2.0

; One-shot exact-map capture for the screenshot-only 0.4 editor.
;
; This runs at the safe RunStrategy boundary after the macro has aligned/verified the
; camera and BEFORE the match is started. If a usable camera image is already cached,
; this function returns immediately and adds zero capture work to later runs.

global LabAutoMapCaptureBusy := false

LabAutoMapCaptureLog(message) {
    try {
        dir := A_AppData "\Ultimate_Macro\StrategyEditor"
        if !DirExist(dir)
            DirCreate(dir)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n",
            dir "\auto-map-capture.log", "UTF-8")
    }
}

LabMapAutoCaptureIfMissing(mapName) {
    global LabAutoMapCaptureBusy

    name := Trim(String(mapName))
    if (name = "")
        return ""

    cached := LabMapCameraPath(name)
    if (cached != "")
        return cached

    if LabAutoMapCaptureBusy
        return ""
    if !WinExist("ahk_exe RobloxPlayerBeta.exe")
        return ""

    LabAutoMapCaptureBusy := true
    pBitmap := 0
    tempPath := ""
    try {
        getRobloxPos(&x, &y, &w, &h)
        if (w < 100 || h < 100)
            throw Error("Roblox client area is not usable.")

        ; AlignCamera()/special-map path has already completed. A tiny settle delay is
        ; enough to avoid catching the final camera interpolation frame.
        Sleep(160)
        pBitmap := Gdip_BitmapFromScreen(x "|" y "|" w "|" h)
        if !pBitmap
            throw Error("GDI+ could not capture Roblox.")

        dir := A_AppData "\Ultimate_Macro\StrategyEditor"
        if !DirExist(dir)
            DirCreate(dir)
        tempPath := dir "\auto-map-capture-" A_TickCount ".png"
        Gdip_SaveBitmapToFile(pBitmap, tempPath, 95)
        if !FileExist(tempPath) || FileGetSize(tempPath) < 500
            throw Error("Temporary map screenshot was not written correctly.")

        saved := LabMapSaveCameraCapture(name, tempPath)
        if (saved = "")
            throw Error("MapLibrary rejected the captured screenshot.")

        LabAutoMapCaptureLog("Captured exact macro-camera map: " name " -> " saved)
        return saved
    } catch Error as err {
        ; Cosmetic/editor capture must never interrupt gameplay. A failed attempt is
        ; logged and the next run can retry because no camera file was created.
        LabAutoMapCaptureLog("Capture failed for " name ": " err.Message)
        return ""
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
        if (tempPath != "" && FileExist(tempPath))
            try FileDelete(tempPath)
        LabAutoMapCaptureBusy := false
    }
}
