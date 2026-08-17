#Requires AutoHotkey v2.0

; Reward tracking is result-boundary only. It must never run inside PlayStrategy().
; The watchdog owns screen capture/template/OCR calls; this file owns persistence,
; dedupe, session totals and conservative candidate acceptance.

RewardTrackerRoot() {
    dir := A_AppData "\Ultimate_Macro"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

RewardTrackerSettingsFile() => RewardTrackerRoot() "\Options\Settings.tds"
RewardTrackerTotalsPath() => RewardTrackerRoot() "\reward_totals.ini"
RewardTrackerLedgerPath() => RewardTrackerRoot() "\reward_ledger.csv"
RewardTrackerRunsPath() => RewardTrackerRoot() "\reward_runs.csv"
RewardTrackerEvidenceDir() {
    dir := RewardTrackerRoot() "\RewardEvidence"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

RewardTrackerIsEnabled() {
    return Integer(IniRead(RewardTrackerSettingsFile(), "LabRewardTracker", "Enabled", 1)) = 1
}

RewardTrackerCaptureEvidenceEnabled() {
    return Integer(IniRead(RewardTrackerSettingsFile(), "LabRewardTracker", "CaptureEvidence", 1)) = 1
}

RewardTrackerSafeKey(value) {
    key := StrLower(Trim(String(value)))
    key := RegExReplace(key, "[^a-z0-9_-]+", "_")
    key := Trim(key, "_")
    return key != "" ? key : "unknown"
}

RewardTrackerEscapeCsv(value) {
    text := String(value)
    text := StrReplace(text, '"', '""')
    return '"' text '"'
}

RewardTrackerBeginSession(forceNew := false) {
    totals := RewardTrackerTotalsPath()
    current := IniRead(totals, "Meta", "CurrentSession", "")
    if (forceNew || current = "") {
        current := FormatTime(, "yyyyMMdd-HHmmss")
        IniWrite(current, totals, "Meta", "CurrentSession")
        try IniDelete(totals, "Session")
        try IniDelete(totals, "RunSession")
        try IniDelete(totals, "Seen")
        try IniDelete(totals, "SeenRuns")
        IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), totals, "Meta", "SessionStarted")
    }
    return current
}

RewardTrackerCurrentSession() => RewardTrackerBeginSession(false)

RewardTrackerMakeRunId(stateFile) {
    runNo := IniRead(stateFile, "State", "CurrentRunCount", 0)
    stratStart := IniRead(stateFile, "State", "CurrentStratStartTime", 0)
    return "run-" runNo "-" stratStart
}

RewardTrackerSeenKey(runId, rewardKey) {
    return RewardTrackerSafeKey(runId) "__" RewardTrackerSafeKey(rewardKey)
}

RewardTrackerAppend(runId, mapName, modeName, strategyPath, rewardKey, displayName, quantity, confidence := 1.0, evidence := "confirmed") {
    if !RewardTrackerIsEnabled()
        return false
    quantity := Integer(quantity)
    if (quantity <= 0)
        return false
    confidence := Number(confidence)
    if (confidence < 0 || confidence > 1)
        throw Error("Reward confidence must be between 0 and 1.")

    session := RewardTrackerCurrentSession()
    key := RewardTrackerSafeKey(rewardKey)
    totals := RewardTrackerTotalsPath()
    seenKey := RewardTrackerSeenKey(runId, key)
    if Integer(IniRead(totals, "Seen", seenKey, 0)) = 1
        return false

    ledger := RewardTrackerLedgerPath()
    if !FileExist(ledger) {
        FileAppend(
            "recorded_at,session_id,run_id,map,mode,strategy,reward_key,display_name,quantity,confidence,evidence`r`n",
            ledger, "UTF-8"
        )
    }

    row := RewardTrackerEscapeCsv(FormatTime(, "yyyy-MM-dd HH:mm:ss")) ","
        . RewardTrackerEscapeCsv(session) ","
        . RewardTrackerEscapeCsv(runId) ","
        . RewardTrackerEscapeCsv(mapName) ","
        . RewardTrackerEscapeCsv(modeName) ","
        . RewardTrackerEscapeCsv(strategyPath) ","
        . RewardTrackerEscapeCsv(key) ","
        . RewardTrackerEscapeCsv(displayName) ","
        . quantity "," Round(confidence, 3) ","
        . RewardTrackerEscapeCsv(evidence) "`r`n"
    FileAppend(row, ledger, "UTF-8")

    lifetime := Integer(IniRead(totals, "Lifetime", key, 0)) + quantity
    sessionTotal := Integer(IniRead(totals, "Session", key, 0)) + quantity
    IniWrite(lifetime, totals, "Lifetime", key)
    IniWrite(sessionTotal, totals, "Session", key)
    IniWrite(displayName, totals, "DisplayNames", key)
    IniWrite(1, totals, "Seen", seenKey)
    IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), totals, "Meta", "LastUpdated")
    return true
}

RewardTrackerRecordRun(runId, result, mapName, modeName, strategyPath, timeSeconds, evidencePath := "") {
    if !RewardTrackerIsEnabled()
        return
    totals := RewardTrackerTotalsPath()
    runSeenKey := RewardTrackerSafeKey(runId)
    if Integer(IniRead(totals, "SeenRuns", runSeenKey, 0)) = 1
        return

    runs := RewardTrackerRunsPath()
    if !FileExist(runs)
        FileAppend("recorded_at,session_id,run_id,result,map,mode,strategy,time_seconds,evidence`r`n", runs, "UTF-8")

    seconds := Integer(Max(0, timeSeconds))
    row := RewardTrackerEscapeCsv(FormatTime(, "yyyy-MM-dd HH:mm:ss")) ","
        . RewardTrackerEscapeCsv(RewardTrackerCurrentSession()) ","
        . RewardTrackerEscapeCsv(runId) ","
        . RewardTrackerEscapeCsv(result) ","
        . RewardTrackerEscapeCsv(mapName) ","
        . RewardTrackerEscapeCsv(modeName) ","
        . RewardTrackerEscapeCsv(strategyPath) ","
        . seconds ","
        . RewardTrackerEscapeCsv(evidencePath) "`r`n"
    FileAppend(row, runs, "UTF-8")

    for section in ["RunSession", "RunLifetime"] {
        IniWrite(Integer(IniRead(totals, section, "Runs", 0)) + 1, totals, section, "Runs")
        IniWrite(Integer(IniRead(totals, section, "Seconds", 0)) + seconds, totals, section, "Seconds")
        if (result = "Triumph")
            IniWrite(Integer(IniRead(totals, section, "Triumphs", 0)) + 1, totals, section, "Triumphs")
        else if (result = "Loss")
            IniWrite(Integer(IniRead(totals, section, "Losses", 0)) + 1, totals, section, "Losses")
    }
    IniWrite(1, totals, "SeenRuns", runSeenKey)

    IniWrite(result, totals, "LastRun", "Result")
    IniWrite(mapName, totals, "LastRun", "Map")
    IniWrite(modeName, totals, "LastRun", "Mode")
    IniWrite(strategyPath, totals, "LastRun", "Strategy")
    IniWrite(Integer(Max(0, timeSeconds)), totals, "LastRun", "Seconds")
    IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), totals, "LastRun", "RecordedAt")
    if (evidencePath != "")
        IniWrite(evidencePath, totals, "LastRun", "Evidence")
}

RewardTrackerGetTotals(section := "Session") {
    totals := RewardTrackerTotalsPath()
    result := []
    if !FileExist(totals)
        return result
    raw := IniRead(totals, section, "")
    for line in StrSplit(StrReplace(raw, "`r"), "`n") {
        if !RegExMatch(line, "^([^=]+)=(\d+)$", &m)
            continue
        key := Trim(m[1])
        quantity := Integer(m[2])
        display := IniRead(totals, "DisplayNames", key, key)
        result.Push({key: key, display: display, quantity: quantity})
    }
    return result
}

RewardTrackerAcceptCandidate(candidate) {
    if !IsObject(candidate)
        return {accepted: false, reason: "invalid-candidate"}
    if !candidate.HasOwnProp("key") || !candidate.HasOwnProp("quantity") || !candidate.HasOwnProp("confidence")
        return {accepted: false, reason: "missing-fields"}
    quantity := Integer(candidate.quantity)
    confidence := Number(candidate.confidence)
    if (quantity <= 0 || quantity > 100000000)
        return {accepted: false, reason: "quantity-out-of-range"}
    if (confidence < 0.82)
        return {accepted: false, reason: "low-confidence"}
    return {accepted: true, reason: "confirmed"}
}

RewardTrackerCatalogPath() {
    return A_WorkingDir "\Resources\RewardTracker\catalog.ini"
}

RewardTrackerReadCatalog() {
    path := RewardTrackerCatalogPath()
    result := []
    if !FileExist(path)
        return result
    sections := IniRead(path)
    for section in StrSplit(StrReplace(sections, "`r"), "`n") {
        section := Trim(section)
        if (section = "")
            continue
        template := IniRead(path, section, "template", "")
        if (template = "")
            continue
        display := IniRead(path, section, "display", section)
        threshold := Number(IniRead(path, section, "threshold", 0.86))
        result.Push({
            key: section,
            display: display,
            template: A_WorkingDir "\Resources\RewardTracker\Templates\" template,
            threshold: threshold
        })
    }
    return result
}

; Watchdog-only helper: attempts registered icon templates and OCRs the quantity text
; directly below the matched icon. No quantity = no reward is committed.
RewardTrackerScanKnownItems(runId, mapName, modeName, strategyPath, clientX, clientY, clientW, clientH) {
    found := []
    if !RewardTrackerIsEnabled()
        return found

    for item in RewardTrackerReadCatalog() {
        if !FileExist(item.template)
            continue

        match := AdvImageSearch(
            item.template,
            Round(clientW * 0.10), Round(clientH * 0.25),
            Round(clientW * 0.55), Round(clientH * 0.55),
            0.45, 1.8, 0.04
        )
        if (match.status != "success" || match.score < item.threshold)
            continue

        quantity := RewardTrackerOcrItemQuantity(match, clientX, clientY)
        candidate := {
            key: item.key,
            display: item.display,
            quantity: quantity,
            confidence: match.score,
            evidence: "template+ocr"
        }
        decision := RewardTrackerAcceptCandidate(candidate)
        if !decision.accepted
            continue

        if RewardTrackerAppend(
            runId, mapName, modeName, strategyPath,
            candidate.key, candidate.display, candidate.quantity,
            candidate.confidence, candidate.evidence
        )
            found.Push(candidate)
    }
    return found
}

RewardTrackerOcrItemQuantity(match, clientX, clientY) {
    ; ImageSearch returns Roblox-client coordinates. GDI+ capture needs screen coordinates.
    qX := Max(0, match.x - Round(match.w * 0.25))
    qY := Max(0, match.y + Round(match.h * 0.72))
    qW := Max(45, Round(match.w * 1.50))
    qH := Max(28, Round(match.h * 0.65))

    pBitmap := Gdip_BitmapFromScreen((clientX + qX) "|" (clientY + qY) "|" qW "|" qH)
    if !pBitmap
        return 0
    text := ""
    try {
        scaled := Gdip_CreateBitmap(qW * 4, qH * 4)
        if !scaled
            return 0
        g := Gdip_GraphicsFromImage(scaled)
        if g {
            DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)
            Gdip_DrawImage(g, pBitmap, 0, 0, qW * 4, qH * 4, 0, 0, qW, qH)
            try text := OCR.FromBitmap(scaled, {lang:"en-US", scale:2}).Text
            Gdip_DeleteGraphics(g)
        }
        Gdip_DisposeImage(scaled)
    } finally {
        Gdip_DisposeImage(pBitmap)
    }

    if RegExMatch(text, "i)[x×]\s*(\d{1,6})", &m)
        return Integer(m[1])
    if RegExMatch(text, "i)(\d{1,6})", &m)
        return Integer(m[1])
    return 0
}

RewardTrackerCaptureEvidence(runId, clientX, clientY, clientW, clientH) {
    if !RewardTrackerIsEnabled() || !RewardTrackerCaptureEvidenceEnabled()
        return ""

    ; Crop the center result panel, not the whole desktop.
    x := clientX + Round(clientW * 0.20)
    y := clientY + Round(clientH * 0.18)
    w := Round(clientW * 0.60)
    h := Round(clientH * 0.62)
    pBitmap := Gdip_BitmapFromScreen(x "|" y "|" w "|" h)
    if !pBitmap
        return ""

    path := RewardTrackerEvidenceDir() "\" FormatTime(, "yyyyMMdd-HHmmss") "-" RewardTrackerSafeKey(runId) ".png"
    try {
        Gdip_SaveBitmapToFile(pBitmap, path, 95)
        totals := RewardTrackerTotalsPath()
        count := Integer(IniRead(totals, "Meta", "EvidenceCount", 0)) + 1
        IniWrite(count, totals, "Meta", "EvidenceCount")
        return path
    } finally {
        Gdip_DisposeImage(pBitmap)
    }
}
