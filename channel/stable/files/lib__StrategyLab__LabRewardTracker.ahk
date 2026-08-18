#Requires AutoHotkey v2.0

; Fail-safe per-run reward tracker built only from Ultimate Macro's official state.ini
; counters. It intentionally does NOT OCR or scan the screen inside gameplay. Special
; item/drop image references live in LabRewardCatalog and can be matched later without
; putting the Strategy Editor or PlayStrategy timing at risk.

global LabRewardTrackerLastWins := ""
global LabRewardTrackerLastLosses := ""
global LabRewardTrackerBaseCoins := ""
global LabRewardTrackerBaseGems := ""
global LabRewardTrackerBaseExp := ""
global LabRewardTrackerPendingResult := ""
global LabRewardTrackerPendingAt := 0
global LabRewardTrackerPendingStrategy := ""

LabRewardTrackerRoot() {
    dir := A_AppData "\Ultimate_Macro\StrategyEditor\telemetry"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

LabRewardTrackerInt(file, key, fallback := 0) {
    value := fallback
    try value := IniRead(file, "State", key, fallback)
    return IsNumber(value) ? Integer(value) : Integer(fallback)
}

LabRewardTrackerEscape(value) {
    value := String(value)
    value := StrReplace(value, "\\", "\\\\")
    value := StrReplace(value, '"', '\\"')
    value := StrReplace(value, "`r", "")
    value := StrReplace(value, "`n", "\\n")
    return value
}

LabRewardTrackerWrite(result, strategy, coinDelta, gemDelta, expDelta, coins, gems, exp) {
    try {
        root := LabRewardTrackerRoot()
        stamp := FormatTime(, "yyyy-MM-ddTHH:mm:ss")
        line := '{"timestamp":"' LabRewardTrackerEscape(stamp)
            . '","result":"' LabRewardTrackerEscape(result)
            . '","strategy":"' LabRewardTrackerEscape(strategy)
            . '","coins":' coinDelta ',"gems":' gemDelta ',"exp":' expDelta
            . ',"coin_total":' coins ',"gem_total":' gems ',"exp_total":' exp
            . ',"special_drops":[]}' "`n"
        FileAppend(line, root "\rewards.jsonl", "UTF-8-RAW")

        last := root "\last-reward.ini"
        IniWrite(stamp, last, "Reward", "Timestamp")
        IniWrite(result, last, "Reward", "Result")
        IniWrite(strategy, last, "Reward", "Strategy")
        IniWrite(coinDelta, last, "Reward", "Coins")
        IniWrite(gemDelta, last, "Reward", "Gems")
        IniWrite(expDelta, last, "Reward", "EXP")
        IniWrite(LabRewardIconPath("Coin"), last, "Icons", "Coins")
        IniWrite(LabRewardIconPath("Gem"), last, "Icons", "Gems")
        IniWrite(LabRewardIconPath("Experience"), last, "Icons", "EXP")
    }
}

LabRewardTrackerTick(*) {
    global StateFile
    global LabRewardTrackerLastWins, LabRewardTrackerLastLosses
    global LabRewardTrackerBaseCoins, LabRewardTrackerBaseGems, LabRewardTrackerBaseExp
    global LabRewardTrackerPendingResult, LabRewardTrackerPendingAt, LabRewardTrackerPendingStrategy

    try {
        if !IsSet(StateFile) || StateFile = "" || !FileExist(StateFile)
            return

        wins := LabRewardTrackerInt(StateFile, "TotalTriumphs", 0)
        losses := LabRewardTrackerInt(StateFile, "TotalLosses", 0)
        coins := LabRewardTrackerInt(StateFile, "Coins", 0)
        gems := LabRewardTrackerInt(StateFile, "Gems", 0)
        exp := LabRewardTrackerInt(StateFile, "EXP", 0)
        strategy := IniRead(StateFile, "State", "Strategy", "")

        if (LabRewardTrackerLastWins = "") {
            LabRewardTrackerLastWins := wins
            LabRewardTrackerLastLosses := losses
            LabRewardTrackerBaseCoins := coins
            LabRewardTrackerBaseGems := gems
            LabRewardTrackerBaseExp := exp
            return
        }

        ; New StartStrategy sessions reset these cumulative counters. Rebase rather than
        ; treating the reset as a negative reward or carrying earnings across sessions.
        if (wins < LabRewardTrackerLastWins || losses < LabRewardTrackerLastLosses
            || coins < LabRewardTrackerBaseCoins || gems < LabRewardTrackerBaseGems
            || exp < LabRewardTrackerBaseExp) {
            LabRewardTrackerLastWins := wins
            LabRewardTrackerLastLosses := losses
            LabRewardTrackerBaseCoins := coins
            LabRewardTrackerBaseGems := gems
            LabRewardTrackerBaseExp := exp
            LabRewardTrackerPendingResult := ""
            LabRewardTrackerPendingAt := 0
            return
        }

        if (wins > LabRewardTrackerLastWins) {
            LabRewardTrackerLastWins := wins
            LabRewardTrackerPendingResult := "win"
            LabRewardTrackerPendingStrategy := strategy
            ; watchdog writes win/loss first, then currency totals. Give that separate
            ; process a short settling window so the deltas describe the same match.
            LabRewardTrackerPendingAt := A_TickCount + 1400
        }
        if (losses > LabRewardTrackerLastLosses) {
            LabRewardTrackerLastLosses := losses
            LabRewardTrackerPendingResult := "loss"
            LabRewardTrackerPendingStrategy := strategy
            LabRewardTrackerPendingAt := A_TickCount + 1400
        }

        if (LabRewardTrackerPendingResult != "" && A_TickCount >= LabRewardTrackerPendingAt) {
            ; Re-read after the settling window.
            coins := LabRewardTrackerInt(StateFile, "Coins", coins)
            gems := LabRewardTrackerInt(StateFile, "Gems", gems)
            exp := LabRewardTrackerInt(StateFile, "EXP", exp)

            coinDelta := Max(0, coins - LabRewardTrackerBaseCoins)
            gemDelta := Max(0, gems - LabRewardTrackerBaseGems)
            expDelta := Max(0, exp - LabRewardTrackerBaseExp)
            LabRewardTrackerWrite(LabRewardTrackerPendingResult, LabRewardTrackerPendingStrategy,
                coinDelta, gemDelta, expDelta, coins, gems, exp)

            LabRewardTrackerBaseCoins := coins
            LabRewardTrackerBaseGems := gems
            LabRewardTrackerBaseExp := exp
            LabRewardTrackerPendingResult := ""
            LabRewardTrackerPendingAt := 0
        }
    } catch Error as err {
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " err.Message "`n",
            LabRewardTrackerRoot() "\reward-tracker-errors.log", "UTF-8")
    }
}

SetTimer(LabRewardTrackerTick, 700)
