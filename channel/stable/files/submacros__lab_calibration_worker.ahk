#Requires AutoHotkey v2.0
#SingleInstance Off
#Include "%A_ScriptDir%\..\lib\Gdip_All.ahk"

; Passive calibration worker.
; It watches the same state.ini boundary Ultimate Macro already writes when
; PlayStrategy() begins. The screenshot work happens in this separate process,
; so the gameplay/recording AHK thread is never interrupted by GDI+ encoding.

parentPid := 0
Loop A_Args.Length {
    if (A_Args[A_Index] = "--parent" && A_Index < A_Args.Length) {
        try parentPid := Integer(A_Args[A_Index + 1])
        break
    }
}

root := A_AppData "\Ultimate_Macro\StrategyEditor"
cameraDir := root "\MapLibrary\camera"
stateFile := A_AppData "\Ultimate_Macro\state.ini"
logPath := root "\calibration.log"
metaPath := root "\calibration.ini"

if !DirExist(root)
    DirCreate(root)
if !DirExist(cameraDir)
    DirCreate(cameraDir)

pToken := Gdip_Startup()
if !pToken
    ExitApp()
OnExit(LabCalibrationWorkerCleanup)

lastStamp := ""

Loop {
    if (parentPid && !ProcessExist(parentPid))
        break

    if FileExist(stateFile) {
        running := 0
        stamp := ""
        strategyPath := ""
        try running := Integer(IniRead(stateFile, "State", "Running", 0))
        try stamp := Trim(IniRead(stateFile, "State", "TimeWhenStartedPlaying", ""))
        try strategyPath := Trim(IniRead(stateFile, "State", "Strategy", ""))

        if (running = 1 && stamp != "" && stamp != "0" && stamp != lastStamp) {
            ; Mark this run immediately: one calibration attempt per strategy start.
            ; A failed attempt is logged and the next normal run can retry safely.
            lastStamp := stamp
            try LabCalibrationHandleRun(strategyPath, cameraDir, metaPath, logPath)
            catch Error as err
                LabCalibrationLog(logPath, "capture ERROR :: " err.Message)
        }
    }

    Sleep(125)
}

ExitApp()

LabCalibrationWorkerCleanup(*) {
    global pToken
    if pToken
        try Gdip_Shutdown(pToken)
}

LabCalibrationSafeKey(value) {
    key := StrLower(Trim(String(value)))
    key := RegExReplace(key, "[^a-z0-9]+", "-")
    return Trim(key, "-")
}

LabCalibrationLog(path, text) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " text "`r`n", path, "UTF-8")
}

LabCalibrationExistingCamera(cameraDir, key) {
    for ext in ["jpg", "jpeg", "png", "bmp"] {
        candidate := cameraDir "\" key "." ext
        if !FileExist(candidate)
            continue
        size := 0
        try size := FileGetSize(candidate)
        if (size >= 10000)
            return candidate
        try FileDelete(candidate)
    }
    return ""
}

LabCalibrationHandleRun(strategyPath, cameraDir, metaPath, logPath) {
    if (strategyPath = "" || !FileExist(strategyPath)) {
        LabCalibrationLog(logPath, "capture SKIP: strategy path unavailable")
        return false
    }

    mapName := ""
    try mapName := Trim(IniRead(strategyPath, "Settings", "map", ""))
    if (mapName = "") {
        LabCalibrationLog(logPath, "capture SKIP: strategy has no map setting :: " strategyPath)
        return false
    }

    key := LabCalibrationSafeKey(mapName)
    if (key = "")
        return false

    existing := LabCalibrationExistingCamera(cameraDir, key)
    if (existing != "") {
        LabCalibrationLog(logPath, "capture READY " mapName " -> " existing)
        return true
    }

    ; PlayStrategy writes TimeWhenStartedPlaying after MainGui.Hide() and after the
    ; normal ready/camera setup path. Wait briefly only for Roblox to be foreground;
    ; never activate/focus it from this helper because gameplay owns the input focus.
    hwnd := 0
    Loop 24 {
        hwnd := WinExist("ahk_exe RobloxPlayerBeta.exe")
        if (hwnd && WinActive("ahk_id " hwnd))
            break
        Sleep(75)
    }
    if (!hwnd || !WinActive("ahk_id " hwnd)) {
        LabCalibrationLog(logPath, "capture SKIP " mapName ": Roblox was not foreground")
        return false
    }

    x := 0, y := 0, w := 0, h := 0
    try WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwnd)
    catch Error as err {
        LabCalibrationLog(logPath, "capture ERROR " mapName " client rect :: " err.Message)
        return false
    }
    if (w < 640 || h < 360) {
        LabCalibrationLog(logPath, "capture SKIP " mapName ": invalid client size " w "x" h)
        return false
    }

    pBitmap := 0
    target := cameraDir "\" key ".jpg"
    temp := cameraDir "\" key ".capture-" A_TickCount ".jpg"
    try {
        pBitmap := Gdip_BitmapFromScreen(x "|" y "|" w "|" h)
        if !pBitmap
            throw Error("GDI+ could not capture the Roblox client.")

        ; Full client resolution preserves the exact recorded coordinate plane.
        ; JPEG 86 is intentionally used instead of PNG: at 1080p it is typically
        ; a small fraction of the size while remaining far sharper than the editor canvas.
        Gdip_SaveBitmapToFile(pBitmap, temp, 86)
        if !FileExist(temp) || FileGetSize(temp) < 10000
            throw Error("The captured JPEG was empty or invalid.")

        ; Remove old variants so MapLibrary cannot prefer a stale PNG over this exact frame.
        for ext in ["png", "jpeg", "bmp"] {
            old := cameraDir "\" key "." ext
            if FileExist(old)
                try FileDelete(old)
        }
        if FileExist(target)
            FileDelete(target)
        FileMove(temp, target, 1)

        strategyW := ""
        strategyH := ""
        try strategyW := IniRead(strategyPath, "Do Not Edit", "width", "")
        try strategyH := IniRead(strategyPath, "Do Not Edit", "height", "")
        IniWrite(mapName, metaPath, key, "Map")
        IniWrite(target, metaPath, key, "CameraFile")
        IniWrite(w, metaPath, key, "ClientWidth")
        IniWrite(h, metaPath, key, "ClientHeight")
        IniWrite(strategyW, metaPath, key, "StrategyWidth")
        IniWrite(strategyH, metaPath, key, "StrategyHeight")
        IniWrite(FormatTime(, "yyyy-MM-ddTHH:mm:ss"), metaPath, key, "Captured")
        IniWrite("auto-first-run", metaPath, key, "Source")

        LabCalibrationLog(logPath, "capture OK " mapName " " w "x" h " -> " target)
        return true
    } finally {
        if pBitmap
            try Gdip_DisposeImage(pBitmap)
        if FileExist(temp)
            try FileDelete(temp)
    }
}
