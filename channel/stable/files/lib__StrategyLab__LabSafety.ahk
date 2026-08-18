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

    ; Release inputs first so the machine immediately returns to a controllable state.
    try LabReleaseHeldInputs()

    ; Upstream StopStrategy is declared as StopStrategy(ctrl, *), therefore AutoHotkey
    ; requires at least one positional argument even when we invoke it programmatically.
    ; Passing 0 mirrors the macro's own F2 handler and avoids a parse-time arity error.
    try {
        if IsSet(RunningStrategy) && RunningStrategy
            StopStrategy(0, 0)
    } catch {
        ; Emergency fallback: do not let an upstream stop-path failure leave the Lab
        ; believing playback is still active.
        try RunningStrategy := false
        try KillSubmacros()
    }

    try RunningStrategy := false
    try LabReleaseHeldInputs()

    if IsSet(StateFile) && StateFile != "" {
        try IniWrite("emergency_stop", StateFile, "Lab", "LastSafetyEvent")
        try IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), StateFile, "Lab", "LastSafetyAt")
    }

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
