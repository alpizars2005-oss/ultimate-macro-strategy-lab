#Requires AutoHotkey v2.0

; Reliability guard borrowed from the Macro-Recorder-JSON safety model: one visible,
; global emergency stop and a best-effort release of held inputs after interruption.

global LabSafetyEnabled := true
global LabSafetyLastStop := 0

LabReleaseHeldInputs(*) {
    keys := ["LButton", "RButton", "MButton", "XButton1", "XButton2",
        "Ctrl", "LControl", "RControl", "Shift", "LShift", "RShift",
        "Alt", "LAlt", "RAlt", "LWin", "RWin",
        "w", "a", "s", "d", "q", "e", "f", "r", "t", "y", "u", "x", "z",
        "Space", "Enter", "Tab", "Esc", "Up", "Down", "Left", "Right"]
    for key in keys {
        try SendEvent("{" key " up}")
    }
}

LabEmergencyStop(*) {
    global LabSafetyLastStop, RunningStrategy, StateFile
    now := A_TickCount
    if (LabSafetyLastStop && now - LabSafetyLastStop < 750)
        return
    LabSafetyLastStop := now

    try LabReleaseHeldInputs()
    try {
        if IsSet(RunningStrategy) && RunningStrategy
            StopStrategy()
    }
    try RunningStrategy := false
    try IniWrite("emergency_stop", StateFile, "Lab", "LastSafetyEvent")
    try IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), StateFile, "Lab", "LastSafetyAt")
    try StrategyEditorSetStatus("F12 emergency stop triggered. Held inputs were released.", true)
}

LabSafetyInstall(*) {
    global LabSafetyEnabled
    if !LabSafetyEnabled
        return
    try Hotkey("F12", LabEmergencyStop, "On")
}

LabSafetyOnExit(*) {
    try LabReleaseHeldInputs()
}

SetTimer(LabSafetyInstall, -500)
OnExit(LabSafetyOnExit)
