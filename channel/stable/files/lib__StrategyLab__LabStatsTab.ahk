#Requires AutoHotkey v2.0

; Lightweight Strategy Lab Stats tab. It only reads existing state.ini/telemetry files;
; there is no OCR, network access or gameplay work here.

global LabStatsCtrls := []
global LabStatsTitle := ""
global LabStatsSubtitle := ""
global LabStatsState := ""
global LabStatsWL := ""
global LabStatsCurrency := ""
global LabStatsStrategy := ""
global LabStatsReward := ""
global LabStatsUpdated := ""

LabStatsControlAlive(ctrl) {
    if !IsObject(ctrl)
        return false
    hwnd := 0
    try hwnd := ctrl.Hwnd
    catch
        return false
    if !hwnd
        return false
    try return DllCall("user32\IsWindow", "Ptr", hwnd, "Int") != 0
    catch
        return false
}

LabStatsControlVisible(ctrl) {
    if !LabStatsControlAlive(ctrl)
        return false
    visible := false
    try visible := ctrl.Visible
    catch
        return false
    return !!visible
}

LabStatsCreateTab(gui) {
    global LabStatsCtrls, LabStatsTitle, LabStatsSubtitle, LabStatsState, LabStatsWL
    global LabStatsCurrency, LabStatsStrategy, LabStatsReward, LabStatsUpdated

    gui.SetFont("s12 w700 c55B7FF", "Segoe UI")
    LabStatsTitle := gui.Add("Text", "x30 y96 w300 h28 Hidden", "Strategy Lab Stats")
    gui.SetFont("s8 w400 c8794A0", "Segoe UI")
    LabStatsSubtitle := gui.Add("Text", "x30 y124 w620 h20 Hidden", "Live macro state • session counters • last confirmed reward")
    line := gui.Add("Progress", "x30 y150 w640 h1 Hidden Background333333", 0)

    gui.SetFont("s8 w700 c6D7785", "Segoe UI")
    stateLabel := gui.Add("Text", "x30 y174 w190 h18 Hidden", "MACRO STATE")
    wlLabel := gui.Add("Text", "x245 y174 w190 h18 Hidden", "SESSION W / L")
    currencyLabel := gui.Add("Text", "x460 y174 w190 h18 Hidden", "SESSION EARNINGS")

    gui.SetFont("s11 w700 cF2F2F2", "Segoe UI")
    LabStatsState := gui.Add("Text", "x30 y198 w190 h58 Hidden +Border Center 0x200 Background171717", "Stopped")
    LabStatsWL := gui.Add("Text", "x245 y198 w190 h58 Hidden +Border Center 0x200 Background171717", "0 W  •  0 L")
    LabStatsCurrency := gui.Add("Text", "x460 y198 w190 h58 Hidden +Border Center 0x200 Background171717", "0 Coins  •  0 Gems`n0 EXP")

    gui.SetFont("s8 w700 c6D7785", "Segoe UI")
    stratLabel := gui.Add("Text", "x30 y286 w620 h18 Hidden", "CURRENT STRATEGY")
    gui.SetFont("s10 w600 cF2F2F2", "Segoe UI")
    LabStatsStrategy := gui.Add("Text", "x30 y310 w620 h54 Hidden +Border Center 0x200 Background171717", "No strategy")

    gui.SetFont("s8 w700 c6D7785", "Segoe UI")
    rewardLabel := gui.Add("Text", "x30 y390 w620 h18 Hidden", "LAST CONFIRMED RUN REWARD")
    gui.SetFont("s10 w600 cF2F2F2", "Segoe UI")
    LabStatsReward := gui.Add("Text", "x30 y414 w620 h54 Hidden +Border Center 0x200 Background171717", "No confirmed run reward yet")

    gui.SetFont("s7 w400 c777777", "Segoe UI")
    LabStatsUpdated := gui.Add("Text", "x30 y492 w620 h20 Hidden Right", "")

    LabStatsCtrls := [LabStatsTitle, LabStatsSubtitle, line, stateLabel, wlLabel, currencyLabel,
        LabStatsState, LabStatsWL, LabStatsCurrency, stratLabel, LabStatsStrategy,
        rewardLabel, LabStatsReward, LabStatsUpdated]
    return LabStatsCtrls
}

LabStatsShow() {
    global LabStatsCtrls
    for ctrl in LabStatsCtrls {
        if LabStatsControlAlive(ctrl)
            try ctrl.Visible := true
    }
    LabStatsRefresh()
}

LabStatsReadInt(key, fallback := 0) {
    global StateFile
    if !IsSet(StateFile) || StateFile = "" || !FileExist(StateFile)
        return Integer(fallback)
    value := fallback
    try value := IniRead(StateFile, "State", key, fallback)
    return IsNumber(value) ? Integer(value) : Integer(fallback)
}

LabStatsShortPath(path) {
    if (path = "")
        return "No strategy"
    name := ""
    try SplitPath(path, &name)
    return name != "" ? name : path
}

LabStatsRefresh(*) {
    global StateFile, LabStatsState, LabStatsWL, LabStatsCurrency, LabStatsStrategy
    global LabStatsReward, LabStatsUpdated

    if !LabStatsControlVisible(LabStatsState)
        return
    if !IsSet(StateFile) || StateFile = "" || !FileExist(StateFile)
        return

    running := false
    wins := 0
    losses := 0
    coins := 0
    gems := 0
    exp := 0
    strategy := ""

    try {
        running := String(IniRead(StateFile, "State", "Running", 0)) = "1"
        wins := LabStatsReadInt("TotalTriumphs", 0)
        losses := LabStatsReadInt("TotalLosses", 0)
        coins := LabStatsReadInt("Coins", 0)
        gems := LabStatsReadInt("Gems", 0)
        exp := LabStatsReadInt("EXP", 0)
        strategy := IniRead(StateFile, "State", "Strategy", "")
    }

    if !LabStatsControlAlive(LabStatsState)
        return

    try LabStatsState.Text := running ? "RUNNING" : "STOPPED"
    total := wins + losses
    rate := total > 0 ? Round((wins / total) * 100, 1) : 0
    if LabStatsControlAlive(LabStatsWL)
        try LabStatsWL.Text := wins " W  •  " losses " L`n" rate "% winrate"
    if LabStatsControlAlive(LabStatsCurrency)
        try LabStatsCurrency.Text := coins " Coins  •  " gems " Gems`n" exp " EXP"
    if LabStatsControlAlive(LabStatsStrategy)
        try LabStatsStrategy.Text := LabStatsShortPath(strategy)

    if LabStatsControlAlive(LabStatsReward) {
        rewardFile := A_AppData "\Ultimate_Macro\StrategyEditor\telemetry\last-reward.ini"
        if FileExist(rewardFile) {
            result := IniRead(rewardFile, "Reward", "Result", "")
            rCoins := IniRead(rewardFile, "Reward", "Coins", 0)
            rGems := IniRead(rewardFile, "Reward", "Gems", 0)
            rExp := IniRead(rewardFile, "Reward", "EXP", 0)
            rewardStrat := IniRead(rewardFile, "Reward", "Strategy", "")
            try LabStatsReward.Text := StrUpper(result) "  •  +" rCoins " Coins  •  +" rGems " Gems  •  +" rExp " EXP"
                . (rewardStrat != "" ? "`n" LabStatsShortPath(rewardStrat) : "")
        } else {
            try LabStatsReward.Text := "No confirmed run reward yet"
        }
    }

    if LabStatsControlAlive(LabStatsUpdated)
        try LabStatsUpdated.Text := "Updated " FormatTime(, "HH:mm:ss")
}

LabStatsExit(*) {
    try SetTimer(LabStatsRefresh, 0)
}

SetTimer(LabStatsRefresh, 1000)
OnExit(LabStatsExit)
