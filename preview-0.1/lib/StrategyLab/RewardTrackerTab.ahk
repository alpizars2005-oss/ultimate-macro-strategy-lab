#Requires AutoHotkey v2.0

global LabRewardCtrls := []

RewardTrackerCreateTab(gui) {
    global LabRewardCtrls, LabRewardEnabledCtrl, LabRewardEvidenceCtrl, LabRewardList
    global LabRewardLastRun, LabRewardRunStats, LabRewardStatus, LabRewardRefreshBtn, LabRewardResetBtn, LabRewardFolderBtn

    gui.SetFont("s10 w600 c3A86FF", "Segoe UI")
    title := gui.Add("Text", "x30 y95 w300 h22 Hidden", "Rewards & Run Analytics")
    line := gui.Add("Progress", "x30 y118 w640 h1 Hidden Background333333", 0)

    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabRewardEnabledCtrl := gui.Add("Checkbox", "x30 y132 w155 h22 Hidden", "Enable reward tracker")
    LabRewardEvidenceCtrl := gui.Add("Checkbox", "x205 y132 w185 h22 Hidden", "Capture result evidence")
    LabRewardRefreshBtn := gui.Add("Button", "x420 y128 w75 h28 Hidden", "Refresh")
    LabRewardResetBtn := gui.Add("Button", "x500 y128 w80 h28 Hidden", "New session")
    LabRewardFolderBtn := gui.Add("Button", "x585 y128 w85 h28 Hidden", "Evidence")

    LabRewardEnabledCtrl.Value := RewardTrackerIsEnabled()
    LabRewardEvidenceCtrl.Value := RewardTrackerCaptureEvidenceEnabled()
    LabRewardEnabledCtrl.OnEvent("Click", RewardTrackerSaveUiOptions)
    LabRewardEvidenceCtrl.OnEvent("Click", RewardTrackerSaveUiOptions)
    LabRewardRefreshBtn.OnEvent("Click", (*) => RewardTrackerRefreshUI())
    LabRewardResetBtn.OnEvent("Click", RewardTrackerNewSession)
    LabRewardFolderBtn.OnEvent("Click", RewardTrackerOpenEvidence)

    gui.SetFont("s8 w400 cFFFFFF", "Segoe UI")
    LabRewardList := gui.Add("ListView", "x30 y175 w400 h280 Hidden Grid", ["Reward", "Session", "Lifetime"])
    LabRewardList.ModifyCol(1, 200)
    LabRewardList.ModifyCol(2, 90)
    LabRewardList.ModifyCol(3, 90)

    gui.SetFont("s9 w600 cFFFFFF", "Segoe UI")
    statsTitle := gui.Add("Text", "x455 y175 w215 h22 Hidden", "Session runs")
    gui.SetFont("s8 w400 cAAAAAA", "Segoe UI")
    LabRewardRunStats := gui.Add("Text", "x455 y198 w215 h75 Hidden", "Runs: 0")

    gui.SetFont("s9 w600 cFFFFFF", "Segoe UI")
    lastTitle := gui.Add("Text", "x455 y280 w215 h22 Hidden", "Last detected run")
    gui.SetFont("s8 w400 cAAAAAA", "Segoe UI")
    LabRewardLastRun := gui.Add("Text", "x455 y303 w215 h110 Hidden", "No tracked run yet.")
    LabRewardStatus := gui.Add("Text", "x455 y420 w215 h40 Hidden", "")

    gui.SetFont("s8 w400 cAAAAAA", "Segoe UI")
    hint := gui.Add("Text", "x30 y470 w640 h55 Hidden",
        "Tracking runs only after a confirmed result screen. Coins/Gems/XP use the official result OCR. "
        . "Known item templates use image matching + quantity OCR; ambiguous reads are not counted.")

    LabRewardCtrls := [
        title, line, LabRewardEnabledCtrl, LabRewardEvidenceCtrl, LabRewardRefreshBtn,
        LabRewardResetBtn, LabRewardFolderBtn, LabRewardList, statsTitle, LabRewardRunStats,
        lastTitle, LabRewardLastRun, LabRewardStatus, hint
    ]
    return LabRewardCtrls
}

RewardTrackerShow() {
    global LabRewardCtrls
    for ctrl in LabRewardCtrls
        ctrl.Visible := true
    RewardTrackerRefreshUI()
}

RewardTrackerSaveUiOptions(*) {
    global LabRewardEnabledCtrl, LabRewardEvidenceCtrl, SettingsFile
    IniWrite(LabRewardEnabledCtrl.Value ? 1 : 0, SettingsFile, "LabRewardTracker", "Enabled")
    IniWrite(LabRewardEvidenceCtrl.Value ? 1 : 0, SettingsFile, "LabRewardTracker", "CaptureEvidence")
    RewardTrackerRefreshUI()
}

RewardTrackerNewSession(*) {
    RewardTrackerBeginSession(true)
    RewardTrackerRefreshUI()
}

RewardTrackerOpenEvidence(*) {
    dir := RewardTrackerEvidenceDir()
    Run('explorer.exe "' dir '"')
}

RewardTrackerRefreshUI() {
    global LabRewardList, LabRewardLastRun, LabRewardRunStats, LabRewardStatus
    if !IsSet(LabRewardList)
        return

    session := Map()
    lifetime := Map()
    names := Map()

    for item in RewardTrackerGetTotals("Session") {
        session[item.key] := item.quantity
        names[item.key] := item.display
    }
    for item in RewardTrackerGetTotals("Lifetime") {
        lifetime[item.key] := item.quantity
        names[item.key] := item.display
    }

    keys := []
    seen := Map()
    for key, _ in lifetime {
        keys.Push(key)
        seen[key] := true
    }
    for key, _ in session {
        if !seen.Has(key)
            keys.Push(key)
    }

    LabRewardList.Delete()
    if (keys.Length = 0) {
        LabRewardList.Add(, "No rewards recorded yet", "0", "0")
    } else {
        for key in keys
            LabRewardList.Add(, names[key], session.Has(key) ? session[key] : 0, lifetime.Has(key) ? lifetime[key] : 0)
    }

    totals := RewardTrackerTotalsPath()
    runs := Integer(IniRead(totals, "RunSession", "Runs", 0))
    wins := Integer(IniRead(totals, "RunSession", "Triumphs", 0))
    losses := Integer(IniRead(totals, "RunSession", "Losses", 0))
    runSeconds := Integer(IniRead(totals, "RunSession", "Seconds", 0))
    winRate := runs > 0 ? Round((wins / runs) * 100) : 0
    LabRewardRunStats.Text := "Runs: " runs "   Wins: " wins "   Losses: " losses
        . "`nWin rate: " winRate "%   Runtime: " RewardTrackerFormatDuration(runSeconds)

    result := IniRead(totals, "LastRun", "Result", "")
    if (result = "") {
        LabRewardLastRun.Text := "No tracked run yet."
    } else {
        mapName := IniRead(totals, "LastRun", "Map", "Unknown")
        modeName := IniRead(totals, "LastRun", "Mode", "Unknown")
        seconds := Integer(IniRead(totals, "LastRun", "Seconds", 0))
        recorded := IniRead(totals, "LastRun", "RecordedAt", "")
        evidence := IniRead(totals, "LastRun", "Evidence", "")
        LabRewardLastRun.Text := result "`nMap: " mapName "`nMode: " modeName
            . "`nRuntime: " RewardTrackerFormatDuration(seconds)
            . "`nRecorded: " recorded
            . (evidence != "" ? "`nEvidence saved: yes" : "")
    }

    LabRewardStatus.Text := "Session: " RewardTrackerCurrentSession()
        . "`nEvidence captures: " IniRead(totals, "Meta", "EvidenceCount", 0)
}

RewardTrackerFormatDuration(seconds) {
    seconds := Max(0, Integer(seconds))
    mins := Floor(seconds / 60)
    secs := Mod(seconds, 60)
    return mins > 0 ? mins "m " secs "s" : secs "s"
}
