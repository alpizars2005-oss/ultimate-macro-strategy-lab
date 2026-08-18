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
global LabRemoteWebhookBtn := ""
global LabRemoteWebhookInstallAttempts := 0

LabRemoteEnsureRoot() {
    global LabRemoteRoot
    if !DirExist(LabRemoteRoot)
        DirCreate(LabRemoteRoot)
    return LabRemoteRoot
}

LabRemoteLog(text) {
    global LabRemoteRoot
    try {
        LabRemoteEnsureRoot()
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " String(text) "`n", LabRemoteRoot "\remote-ahk.log", "UTF-8")
    }
}

LabRemoteEnabled() {
    global LabRemoteConfig
    return FileExist(LabRemoteConfig) && String(IniRead(LabRemoteConfig, "Remote", "Enabled", 0)) = "1"
}

LabRemoteLaunchSettings(*) {
    global LabRemoteSettingsPid, LabRemoteRoot
    LabRemoteEnsureRoot()
    script := A_ScriptDir "\submacros\lab_remote_settings.ps1"
    logPath := LabRemoteRoot "\remote-settings.log"

    if !FileExist(script) {
        msg := "Remote settings helper is missing: " script
        try StrategyEditorSetStatus(msg, true)
        try MsgBox(msg "`n`nRun the Strategy Lab repair tool or update to 0.3.5+.", "Strategy Lab Remote", 0x10)
        return
    }

    ; Do not spawn a stack of settings windows if the user clicks twice.
    if (LabRemoteSettingsPid && ProcessExist(LabRemoteSettingsPid)) {
        try StrategyEditorSetStatus("Discord Remote settings are already open.")
        return
    }

    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' script '" -InstallDir "' A_ScriptDir '"'
    try {
        Run(cmd, A_ScriptDir, , &LabRemoteSettingsPid)
        LabRemoteLog("settings UI launched PID " LabRemoteSettingsPid)
        try StrategyEditorSetStatus("Opening Discord Remote settings...")
    } catch Error as err {
        LabRemoteSettingsPid := 0
        LabRemoteLog("settings launcher ERROR: " err.Message)
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " ERROR launcher: " err.Message "`n", logPath, "UTF-8")
        try StrategyEditorSetStatus("Could not open Remote settings: " err.Message, true)
        try MsgBox("Could not open Discord Remote settings.`n`n" err.Message "`n`nLog: " logPath, "Strategy Lab Remote", 0x10)
    }
}

; The old Dark-style title shortcut depends on a native Static control receiving click
; notifications. Keep that shortcut, but also create a real Button on the Webhook tab.
; The button does not require patching upstream tab arrays and is shown by a guarded
; monitor only while Tab4 is active, so there is always a reliable entry point.
LabRemoteInstallWebhookEntry(*) {
    global MainGui, Tab4_Title, LabRemoteWebhookBtn, LabRemoteWebhookInstallAttempts

    LabRemoteWebhookInstallAttempts += 1
    if !IsSet(MainGui) || !IsObject(MainGui) {
        if (LabRemoteWebhookInstallAttempts < 30)
            SetTimer(LabRemoteInstallWebhookEntry, -250)
        return
    }

    if IsSet(Tab4_Title) && IsObject(Tab4_Title) {
        ; SS_NOTIFY: allows the preflight-installed title Click callback to fire on
        ; Windows builds where a plain Text control otherwise ignores mouse clicks.
        try Tab4_Title.Opt("+0x100")
    }

    if !IsObject(LabRemoteWebhookBtn) {
        try {
            LabRemoteWebhookBtn := MainGui.Add("Button", "x515 y88 w155 h30 Hidden", "Discord Remote")
            LabRemoteWebhookBtn.OnEvent("Click", LabRemoteLaunchSettings)
        } catch Error as err {
            LabRemoteLog("Webhook-tab Remote button creation failed: " err.Message)
            if (LabRemoteWebhookInstallAttempts < 30)
                SetTimer(LabRemoteInstallWebhookEntry, -250)
            return
        }
    }

    SetTimer(LabRemoteWebhookUiTick, 150)
}

LabRemoteWebhookUiTick(*) {
    global LabRemoteWebhookBtn, CurrentTab
    if !IsObject(LabRemoteWebhookBtn)
        return

    show := false
    try {
        if IsSet(CurrentTab)
            show := (CurrentTab = "Tab4")
    }
    try LabRemoteWebhookBtn.Visible := show
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
    if !FileExist(worker) {
        LabRemoteLog("Discord worker missing: " worker)
        return
    }

    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' worker '" -InstallDir "' A_ScriptDir '"'
    try {
        Run(cmd, A_ScriptDir, "Hide", &LabRemoteWorkerPid)
        LabRemoteLog("Discord worker launched PID " LabRemoteWorkerPid)
    } catch Error as err {
        LabRemoteWorkerPid := 0
        LabRemoteLog("Discord worker launch ERROR: " err.Message)
    }
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
    try Strategy1Ctrl.Value := path
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
    ; Upstream StartStrategy is StartStrategy(ctrl, *), matching the F1 handler.
    try SetTimer((*) => StartStrategy(0, 0), -150)
    return true
}

; Called only from the high-confidence between-match preflight hook. Never consume a
; Discord network request inside PlayStrategy(), where tower timing is sensitive.
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
    try LabRemoteEnsureWorker()
    try LabRemoteApplyStartupCommand()
    try LabRemoteConsumeLabCommand()
}

LabRemoteOnExit(*) {
    global LabRemoteWorkerPid
    if (LabRemoteWorkerPid && ProcessExist(LabRemoteWorkerPid))
        try ProcessClose(LabRemoteWorkerPid)
}

LabRemoteEnsureRoot()
SetTimer(LabRemoteInstallWebhookEntry, -750)
SetTimer(LabRemoteTick, 1000)
OnExit(LabRemoteOnExit)
