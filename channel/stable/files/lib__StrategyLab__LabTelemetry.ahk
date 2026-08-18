#Requires AutoHotkey v2.0

; Low-overhead, append-only telemetry. It observes the official state.ini counters
; instead of guessing game outcomes, so one official result-counter increment becomes
; one ledger event. No polling or OCR occurs inside PlayStrategy().

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
    ; Windows filenames cannot contain a literal double quote, so normal quoted
    ; arguments are enough here. Keep command construction simple and parse-safe.
    return '"' value '"'
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

    try RunWait(cmd, , "Hide")
    catch
        return ""

    if !FileExist(out)
        return ""

    hash := Trim(FileRead(out, "UTF-8"))
    try FileDelete(out)
    return RegExMatch(hash, "i)^[0-9a-f]{64}$") ? StrUpper(hash) : ""
}

LabTelemetryAppendResult(result, wins, losses, strategyPath, coins, gems, exp, runCount) {
    root := LabTelemetryEnsureDir()
    ledger := root "\runs.jsonl"
    fp := LabTelemetryStrategyFingerprint(strategyPath)
    SplitPath(strategyPath, &strategyName)
    stamp := FormatTime(, "yyyy-MM-ddTHH:mm:ss")
    line := '{"timestamp":"' LabTelemetryEscape(stamp) '","result":"' result '","strategy":"'
        . LabTelemetryEscape(strategyName) '","strategy_sha256":"' fp '","wins":' wins ',"losses":' losses
        . ',"run_count":' runCount ',"coins":' coins ',"gems":' gems ',"exp":' exp '}' "`n"
    FileAppend(line, ledger, "UTF-8-RAW")
}

LabTelemetryPhase(running, startedAt, wins, losses) {
    if !running
        return "stopped"
    if IsNumber(startedAt) && Number(startedAt) > 0
        return "playback"
    return "running"
}

LabTelemetryTick(*) {
    global StateFile, LabTelemetryLastWins, LabTelemetryLastLosses, LabTelemetryLastStrategy, LabTelemetryLastHeartbeat
    if !IsSet(StateFile) || StateFile = "" || !FileExist(StateFile)
        return

    wins := Integer(IniRead(StateFile, "State", "TotalTriumphs", 0))
    losses := Integer(IniRead(StateFile, "State", "TotalLosses", 0))
    strategy := IniRead(StateFile, "State", "Strategy", "")
    coins := Integer(IniRead(StateFile, "State", "Coins", 0))
    gems := Integer(IniRead(StateFile, "State", "Gems", 0))
    exp := Integer(IniRead(StateFile, "State", "EXP", 0))
    runCount := Integer(IniRead(StateFile, "State", "CurrentRunCount", 0))
    running := IniRead(StateFile, "State", "Running", 0) = "1"
    startedAt := IniRead(StateFile, "State", "TimeWhenStartedPlaying", 0)

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
        IniWrite(LabTelemetryPhase(running, startedAt, wins, losses), hb, "Heartbeat", "Phase")
        IniWrite(running ? 1 : 0, hb, "Heartbeat", "Running")
        IniWrite(strategy, hb, "Heartbeat", "Strategy")
        IniWrite(wins, hb, "Heartbeat", "Wins")
        IniWrite(losses, hb, "Heartbeat", "Losses")
        IniWrite(A_NowUTC, hb, "Heartbeat", "UpdatedUTC")
    }
}

SetTimer(LabTelemetryTick, 1000)
