#Requires AutoHotkey v2.0

; One-shot exact-map capture for the screenshot-only editor.
;
; 0.4.2 captured after CheckTheMapF(), which can still be the map-vote/lobby screen.
; 0.4.3 is called at the very beginning of SpawnTower(): at that point the match and
; fixed macro camera are definitely live, but no tower has been placed yet.

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

LabMapAutoCaptureCurrent(*) {
    global gamemap
    if !IsSet(gamemap)
        return ""
    return LabMapAutoCaptureIfMissing(gamemap)
}

LabMapAutoCaptureIfMissing(mapName) {
    global LabAutoMapCaptureBusy, MainGui
    global LabEditorCurrentMap, LabEditorSourceImage, LabEditorBackgroundMode

    name := Trim(String(mapName))
    if (name = "")
        return ""

    ; A 0.4.3 capture has stage metadata. Old 0.4.2 files deliberately have none and
    ; are refreshed once because they may contain the map-vote/lobby screen.
    cached := LabMapCameraPath(name)
    if (cached != "" && !LabMapCameraNeedsRefresh(name))
        return cached

    if LabAutoMapCaptureBusy
        return ""
    if !WinExist("ahk_exe RobloxPlayerBeta.exe")
        return ""

    LabAutoMapCaptureBusy := true
    pBitmap := 0
    restoreMainGui := false
    try {
        ; The macro normally hides MainGui while running, but make the capture robust
        ; when a developer/test starts SpawnTower with the editor still visible.
        if IsSet(MainGui) && IsObject(MainGui) {
            mainHwnd := 0
            try mainHwnd := MainGui.Hwnd
            if (mainHwnd && DllCall("user32\IsWindow", "Ptr", mainHwnd, "Int")
                && DllCall("user32\IsWindowVisible", "Ptr", mainHwnd, "Int")) {
                try MainGui.Hide()
                restoreMainGui := true
                Sleep(50)
            }
        }

        getRobloxPos(&x, &y, &w, &h)
        if (w < 100 || h < 100)
            throw Error("Roblox client area is not usable.")

        ; SpawnTower has only just begun, so the view is the same fixed macro camera
        ; used by the recorded coordinates and still contains no newly placed tower.
        pBitmap := Gdip_BitmapFromScreen(x "|" y "|" w "|" h)
        if !pBitmap
            throw Error("GDI+ could not capture Roblox.")

        saved := LabMapSaveCameraBitmap(name, pBitmap, "spawn")
        if (saved = "")
            throw Error("MapLibrary rejected the captured screenshot.")

        ; If the editor has this map open, point it at the refreshed file now. Do not
        ; force a render during gameplay; the next editor repaint will pick it up.
        if IsSet(LabEditorCurrentMap) && LabEditorCurrentMap = name {
            LabEditorSourceImage := saved
            LabEditorBackgroundMode := "camera"
        }

        LabAutoMapCaptureLog("Captured exact SpawnTower camera: " name " -> " saved)
        return saved
    } catch Error as err {
        ; Editor imagery must never stop a strategy. If capture fails we keep gameplay
        ; running and retry on a later SpawnTower/run because no valid stage was saved.
        LabAutoMapCaptureLog("Capture failed for " name ": " err.Message)
        return ""
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
        if restoreMainGui && IsSet(MainGui) && IsObject(MainGui)
            try MainGui.Show("NA")
        LabAutoMapCaptureBusy := false
    }
}
