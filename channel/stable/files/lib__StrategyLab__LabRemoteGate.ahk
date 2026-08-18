#Requires AutoHotkey v2.0

; Safe remote bridge. Discord/network work is isolated in a PowerShell worker. This
; AHK side only consumes tiny INI commands and applies gameplay-changing requests at
; startup or at the between-match hook injected by lab_preflight.ps1.

global RemoteCommandFile := A_AppData "\Ultimate_Macro\remote_command.ini"
global LabRemoteRoot := A_AppData "\Ultimate_Macro\StrategyEditor"
global LabRemoteConfig := LabRemoteRoot "\remote.ini"
global LabRemoteWorkerPid := 0
global LabRemoteLastConfigCheck := 0
global LabRemoteLabCommandFile := LabRemoteRoot "\lab_remote_command.ini"

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
    script := A_ScriptDir "\submacros\lab_remote_settings.ps1"
    if !FileExist(script) {
        try StrategyEditorSetStatus("Remote settings helper is missing.", true)
        return
    }
    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' script '" -InstallDir "' A_ScriptDir '"'
    try Run(cmd)
}

LabRemoteEnsureWorker(*) {
    global LabRemoteWorkerPid
    if !LabRemoteEnabled()
        return

    if (LabRemoteWorkerPid && ProcessExist(LabRemoteWorkerPid))
        return

    worker := A_ScriptDir "\submacros\lab_discord_worker.ps1"
    if !FileExist(worker)
        return
    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' worker '" -InstallDir "' A_ScriptDir '"'
    try Run(cmd, , "Hide", &LabRemoteWorkerPid)
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

LabRemoteApplyStrategyPath(path) {
    global Strategy1Path, Strategy1Ctrl, SettingsFile, StateFile
    if (path = "" || !FileExist(path))
        return false
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
    if !LabRemoteApplyStrategyPath(strategy) {
        LabRemoteClearCommand("error", "START strategy does not exist: " strategy)
        return false
    }

    LabRemoteClearCommand("start_accepted", strategy)
    try SetTimer(StartStrategy, -150)
    return true
}

; Called from the high-confidence between-match preflight hook. Keep this function
; side-effect free inside actual strategy playback: it is never called by PlayStrategy().
LabRemoteConsumeBetweenMatches(&switched, &stratName) {
    global RemoteCommandFile, RunningStrategy, RotateStrategies, CurrentStratStartTime, CurrentRunCount
    if !IsSet(RemoteCommandFile) || !FileExist(RemoteCommandFile)
        return ""

    action := StrLower(Trim(IniRead(RemoteCommandFile, "Command", "Action", "")))
    if (action = "")
        return ""

    if (action = "stop" || action = "pause") {
        LabRemoteClearCommand("stopped_safe", stratName)
        try RunningStrategy := false
        try LabReleaseHeldInputs()
        return "stop"
    }

    if (action = "switch") {
        newStrat := Trim(IniRead(RemoteCommandFile, "Command", "Strategy", ""))
        if !LabRemoteApplyStrategyPath(newStrat) {
            LabRemoteClearCommand("error", "SWITCH strategy does not exist: " newStrat)
            return ""
        }
        switched := true
        stratName := newStrat
        try RotateStrategies := false
        try CurrentStratStartTime := A_TickCount
        try CurrentRunCount := 0
        LabRemoteClearCommand("switch_accepted", newStrat)
        return "switch"
    }

    if (action = "stop_now") {
        LabRemoteClearCommand("stopped_now", stratName)
        try LabEmergencyStop()
        return "stop"
    }

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

LabRemoteEnsureRoot()
SetTimer(LabRemoteTick, 1000)
