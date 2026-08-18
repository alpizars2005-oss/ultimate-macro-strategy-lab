#Requires AutoHotkey v2.0

; Safe remote bridge. Discord/network work is isolated in a PowerShell worker. This
; AHK side only consumes tiny INI commands and applies gameplay-changing requests at
; startup or at the between-match hook injected by lab_preflight.ps1.

global RemoteCommandFile := A_AppData "\Ultimate_Macro\remote_command.ini"
global LabRemoteRoot := A_AppData "\Ultimate_Macro\StrategyEditor"
global LabRemoteConfig := LabRemoteRoot "\remote.ini"
global LabRemoteWorkerPid := 0
global LabRemoteLabCommandFile := LabRemoteRoot "\lab_remote_command.ini"

global LabRemoteSettingsPid := 0

LabRemoteEnsureRoot() {
    global LabRemoteRoot
    if !DirExist(LabRemoteRoot)
        DirCreate(LabRemoteRoot)
    return LabRemoteRoot
}

LabRemoteEnabled() {
    global LabRemoteConfig
    return FileExist(LabRemoteConfig) && IniRead(LabRemoteConfig, "Remote", "Enabled", 0) = "1"
}

LabRemoteLaunchSettings(*) {
    global LabRemoteSettingsPid, LabRemoteRoot
    LabRemoteEnsureRoot()
    script := A_ScriptDir "\submacros\lab_remote_settings.ps1"
    logPath := LabRemoteRoot "\remote-settings.log"

    if !FileExist(script) {
        msg := "Remote settings helper is missing: " script
        try StrategyEditorSetStatus(msg, true)
        try MsgBox(msg "`n`nRun/update Strategy Lab 0.3.3+.", "Strategy Lab Remote", 0x10)
        return
    }

    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' script '" -InstallDir "' A_ScriptDir '"'
    try {
        Run(cmd, A_ScriptDir, , &LabRemoteSettingsPid)
        try StrategyEditorSetStatus("Opening Discord Remote settings…")
    } catch Error as err {
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " ERROR launcher: " err.Message "`n", logPath, "UTF-8")
        try StrategyEditorSetStatus("Could not open Remote settings: " err.Message, true)
        try MsgBox("Could not open Discord Remote settings.`n`n" err.Message "`n`nLog: " logPath, "Strategy Lab Remote", 0x10)
    }
}

LabRemoteEnsureWorker(*) {
    global LabRemoteWorkerPid
    if !LabRemoteEnabled() {
        if (LabRemoteWorkerPid && ProcessExist(LabRemoteWorkerPid))
            try ProcessClose(LabRemoteWorkerPid)
        LabRemoteWorkerPid := 0
        return
    }

    if (LabRemoteWorkerPid && ProcessExist(LabRemoteWorkerPid))
        return

    worker := A_ScriptDir "\submacros\lab_discord_worker.ps1"
    if !FileExist(worker)
        return
    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' worker '" -InstallDir "' A_ScriptDir '"'
    try Run(cmd, A_ScriptDir, "Hide", &LabRemoteWorkerPid)
}

LabRemoteClearCommand(result := "", details := "") {
    global RemoteCommandFile, StateFile
    commandId := ""
    if IsSet(RemoteCommandFile) && FileExist(RemoteCommandFile)
        commandId := IniRead(RemoteCommandFile, "Command", "Id", "")
    try FileDelete(RemoteCommandFile)
    if IsSet(StateFile) {
        if (commandId != "")
            try IniWrite(commandId, StateFile, "Remote", "LastCommandId")
        try IniWrite(result, StateFile, "Remote", "LastResult")
        try IniWrite(details, StateFile, "Remote", "LastDetails")
        try IniWrite(A_NowUTC, StateFile, "Remote", "LastCompletedUTC")
    }
}

LabRemoteResetSessionStats() {
    global StateFile, AutorunStartTime, CurrentRunCount, CurrentStratStartTime
    if !IsSet(StateFile)
        return
    for key in ["Coins", "Gems", "EXP", "TotalTriumphs", "TotalLosses", "TotalTimeSeconds", "Timescale", "CurrentRunCount"]
        try IniWrite(0, StateFile, "State", key)
    try IniWrite(A_TickCount, StateFile, "State", "CurrentStratStartTime")
    try IniWrite(0, StateFile, "State", "StartTime")
    try CurrentRunCount := 0
    try CurrentStratStartTime := A_TickCount
    try AutorunStartTime := 0
}

LabRemoteApplyStrategyPath(path, loadNow := false) {
    global Strategy1Path, Strategy1Ctrl, SettingsFile, StateFile
    if (path = "" || !FileExist(path))
        return false

    if loadNow {
        try LoadStrategyFile(path)
        catch Error as err {
            LabRemoteClearCommand("error", "Could not load strategy: " err.Message)
            return false
        }
    }

    Strategy1Path := path
    try Strategy1Ctrl.Text := path
    try IniWrite(path, SettingsFile, "Options", "Strategy1")
    try IniWrite(path, StateFile, "State", "Strategy")
    return true
}

LabRemoteApplyStartupCommand(*) {
    global RemoteCommandFile, RunningStrategy, Strategy1Ctrl
    if !IsSet(RemoteCommandFile) || !FileExist(RemoteCommandFile)
        return false
    if IsSet(RunningStrategy) && RunningStrategy
        return false
    if !IsSet(Strategy1Ctrl) || !IsObject(Strategy1Ctrl)
        return false

    action := StrLower(Trim(IniRead(RemoteCommandFile, "Command", "Action", "")))
    if (action != "start")
        return false

    strategy := Trim(IniRead(RemoteCommandFile, "Command", "Strategy", ""))
    if !LabRemoteApplyStrategyPath(strategy, true) {
        if FileExist(RemoteCommandFile)
            LabRemoteClearCommand("error", "START strategy does not exist or could not load: " strategy)
        return false
    }

    LabRemoteResetSessionStats()
    LabRemoteClearCommand("start_accepted", strategy)
    ; Upstream StartStrategy is StartStrategy(ctrl, *), so call it with the same
    ; placeholder arguments used by the macro's F1 handler instead of a zero-arg timer.
    try SetTimer((*) => StartStrategy(0, 0), -150)
    return true
}

; Called from the high-confidence between-match preflight hook. It is deliberately
; never called from PlayStrategy(), so a Discord/network request cannot disturb tower
; timings in the active match.
LabRemoteConsumeBetweenMatches(&switched, &stratName) {
    global RemoteCommandFile, RunningStrategy, RotateStrategies, CurrentStratStartTime, CurrentRunCount
    global StateFile
    if !IsSet(RemoteCommandFile) || !FileExist(RemoteCommandFile)
        return ""

    action := StrLower(Trim(IniRead(RemoteCommandFile, "Command", "Action", "")))
    if (action = "")
        return ""

    if (action = "stop" || action = "pause") {
        current := stratName
        try IniWrite(0, StateFile, "State", "Running")
        try RunningStrategy := false
        try KillSubmacros()
        try LabReleaseHeldInputs()
        LabRemoteClearCommand("stopped_safe", current)
        return "stop"
    }

    if (action = "switch") {
        newStrat := Trim(IniRead(RemoteCommandFile, "Command", "Strategy", ""))
        if !LabRemoteApplyStrategyPath(newStrat, true) {
            if FileExist(RemoteCommandFile)
                LabRemoteClearCommand("error", "SWITCH strategy does not exist or could not load: " newStrat)
            return ""
        }
        switched := true
        stratName := newStrat
        try RotateStrategies := false
        try CurrentStratStartTime := A_TickCount
        try CurrentRunCount := 0
        try IniWrite(1, StateFile, "State", "Running")
        try IniWrite(0, StateFile, "State", "CurrentRunCount")
        LabRemoteClearCommand("switched_safe", newStrat)
        return "switch"
    }

    if (action = "stop_now") {
        LabRemoteClearCommand("stopped_now", stratName)
        try LabEmergencyStop()
        return "stop"
    }

    LabRemoteClearCommand("error", "Unknown remote action: " action)
    return ""
}

LabRemoteConsumeLabCommand(*) {
    global LabRemoteLabCommandFile, LabEditorRingMode
    if !FileExist(LabRemoteLabCommandFile)
        return
    action := StrLower(Trim(IniRead(LabRemoteLabCommandFile, "Command", "Action", "")))
    value := Trim(IniRead(LabRemoteLabCommandFile, "Command", "Value", ""))
    try FileDelete(LabRemoteLabCommandFile)

    if (action = "emergency_stop") {
        try LabEmergencyStop()
        return
    }

    if (action = "rings") {
        if (value = "all" || value = "selected" || value = "off") {
            LabEditorRingMode := value
            try LabEditorRingsBtn.Text := StrategyEditorRingButtonText()
            try StrategyEditorApplyLayer()
        }
        return
    }

    if (action = "recalibrate") {
        mapName := ""
        try mapName := StrategyEditorMapName()
        if (mapName != "") {
            path := LabMapCameraPath(mapName)
            if (path != "") {
                try LabMapInvalidateRenderCache(path)
                try FileDelete(path)
                try StrategyEditorAutoLoadMap()
            }
        }
        return
    }
}

LabRemoteTick(*) {
    LabRemoteEnsureWorker()
    LabRemoteApplyStartupCommand()
    LabRemoteConsumeLabCommand()
}

LabRemoteOnExit(*) {
    global LabRemoteWorkerPid
    if (LabRemoteWorkerPid && ProcessExist(LabRemoteWorkerPid))
        try ProcessClose(LabRemoteWorkerPid)
}

LabRemoteEnsureRoot()
SetTimer(LabRemoteTick, 1000)
OnExit(LabRemoteOnExit)
