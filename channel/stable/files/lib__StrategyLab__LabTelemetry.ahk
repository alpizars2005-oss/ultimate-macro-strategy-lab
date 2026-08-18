#Requires AutoHotkey v2.0

; Low-overhead, append-only telemetry. It observes Ultimate Macro's official state.ini
; counters and never performs OCR or gameplay polling inside PlayStrategy(). Timer
; callbacks are intentionally fail-safe: malformed/missing state values are treated as
; defaults instead of surfacing an exception that could terminate the macro.

global LabTelemetryLastWins := ""
global LabTelemetryLastLosses := ""
global LabTelemetryLastStrategy := ""
global LabTelemetryLastHeartbeat := 0

global LabTelemetryRoot := A_AppData "\Ultimate_Macro\StrategyEditor\telemetry"

LabTelemetryEnsureDir() {
    global LabTelemetryRoot
    if !DirExist(LabTelemetryRoot)
        DirCreate(LabTelemetryRoot)
    return LabTelemetryRoot
}

LabTelemetryEscape(value) {
    value := String(value)
    value := StrReplace(value, "\\", "\\\\")
    value := StrReplace(value, '"', '\\"')
    value := StrReplace(value, "`r", "")
    value := StrReplace(value, "`n", "\\n")
    return value
}

LabTelemetryQuoteArg(value) {
    ; Windows filenames cannot contain a literal double quote.
    return '"' value '"'
}

LabTelemetryReadInteger(file, section, key, defaultValue := 0) {
    value := defaultValue
    try value := IniRead(file, section, key, defaultValue)
    if !IsNumber(value)
        return Integer(defaultValue)
    return Integer(value)
}

LabTelemetryStrategyFingerprint(path) {
    if (path = "" || !FileExist(path))
        return ""

    root := LabTelemetryEnsureDir()
    out := root "\fingerprint.tmp"
    helper := A_ScriptDir "\submacros\lab_fingerprint.ps1"
    if !FileExist(helper)
        return ""

    if FileExist(out)
        try FileDelete(out)

    cmd := "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "
        . LabTelemetryQuoteArg(helper)
        . " -InputPath " LabTelemetryQuoteArg(path)
        . " -OutputPath " LabTelemetryQuoteArg(out)

    try RunWait(cmd, A_ScriptDir, "Hide")
    catch
        return ""

    if !FileExist(out)
        return ""

    hash := ""
    try hash := Trim(FileRead(out, "UTF-8"))
    try FileDelete(out)
    return RegExMatch(hash, "i)^[0-9a-f]{64}$") ? StrUpper(hash) : ""
}

LabTelemetryAppendResult(result, wins, losses, strategyPath, coins, gems, exp, runCount) {
    try {
        root := LabTelemetryEnsureDir()
        ledger := root "\runs.jsonl"
        fp := LabTelemetryStrategyFingerprint(strategyPath)
        strategyName := ""
        if (strategyPath != "")
            try SplitPath(strategyPath, &strategyName)
        stamp := FormatTime(, "yyyy-MM-ddTHH:mm:ss")
        line := '{"timestamp":"' LabTelemetryEscape(stamp) '","result":"' LabTelemetryEscape(result)
            . '","strategy":"' LabTelemetryEscape(strategyName) '","strategy_sha256":"' fp
            . '","wins":' wins ',"losses":' losses ',"run_count":' runCount
            . ',"coins":' coins ',"gems":' gems ',"exp":' exp '}' "`n"
        FileAppend(line, ledger, "UTF-8-RAW")
    }
}

LabTelemetryPhase(running, startedAt) {
    if !running
        return "stopped"
    if IsNumber(startedAt) && Number(startedAt) > 0
        return "playback"
    return "running"
}

LabTelemetryTick(*) {
    global StateFile, LabTelemetryLastWins, LabTelemetryLastLosses
    global LabTelemetryLastStrategy, LabTelemetryLastHeartbeat

    try {
        if !IsSet(StateFile) || StateFile = "" || !FileExist(StateFile)
            return

        wins := LabTelemetryReadInteger(StateFile, "State", "TotalTriumphs", 0)
        losses := LabTelemetryReadInteger(StateFile, "State", "TotalLosses", 0)
        strategy := IniRead(StateFile, "State", "Strategy", "")
        coins := LabTelemetryReadInteger(StateFile, "State", "Coins", 0)
        gems := LabTelemetryReadInteger(StateFile, "State", "Gems", 0)
        exp := LabTelemetryReadInteger(StateFile, "State", "EXP", 0)
        runCount := LabTelemetryReadInteger(StateFile, "State", "CurrentRunCount", 0)
        running := String(IniRead(StateFile, "State", "Running", 0)) = "1"
        startedAt := IniRead(StateFile, "State", "TimeWhenStartedPlaying", 0)

        ; The first observation establishes a baseline and never invents historical runs.
        if (LabTelemetryLastWins = "") {
            LabTelemetryLastWins := wins
            LabTelemetryLastLosses := losses
        } else {
            while (wins > LabTelemetryLastWins) {
                LabTelemetryLastWins += 1
                LabTelemetryAppendResult("win", LabTelemetryLastWins, losses, strategy, coins, gems, exp, runCount)
            }
            while (losses > LabTelemetryLastLosses) {
                LabTelemetryLastLosses += 1
                LabTelemetryAppendResult("loss", wins, LabTelemetryLastLosses, strategy, coins, gems, exp, runCount)
            }
            if (wins < LabTelemetryLastWins)
                LabTelemetryLastWins := wins
            if (losses < LabTelemetryLastLosses)
                LabTelemetryLastLosses := losses
        }

        LabTelemetryLastStrategy := strategy

        now := A_TickCount
        if (!LabTelemetryLastHeartbeat || now - LabTelemetryLastHeartbeat >= 5000) {
            LabTelemetryLastHeartbeat := now
            root := LabTelemetryEnsureDir()
            hb := root "\heartbeat.ini"
            try IniWrite(LabTelemetryPhase(running, startedAt), hb, "Heartbeat", "Phase")
            try IniWrite(running ? 1 : 0, hb, "Heartbeat", "Running")
            try IniWrite(strategy, hb, "Heartbeat", "Strategy")
            try IniWrite(wins, hb, "Heartbeat", "Wins")
            try IniWrite(losses, hb, "Heartbeat", "Losses")
            try IniWrite(A_NowUTC, hb, "Heartbeat", "UpdatedUTC")
        }
    } catch Error as err {
        ; Telemetry must never be able to bring down gameplay. Keep one lightweight
        ; diagnostic line and retry naturally on the next timer tick.
        try {
            root := LabTelemetryEnsureDir()
            FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " err.Message "`n", root "\telemetry-errors.log", "UTF-8")
        }
    }
}

SetTimer(LabTelemetryTick, 1000)
