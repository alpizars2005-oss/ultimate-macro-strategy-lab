#Requires AutoHotkey v2.0

; Core persistence and confidence rules for the future watchdog integration.
; Screen capture/template search/OCR are injected by the macro integration layer so
; this module never needs to run during strategy playback.

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

RewardTrackerLedgerPath() {
    dir := A_AppData "\\Ultimate_Macro"
    if !DirExist(dir)
        DirCreate(dir)
    return dir "\\reward_ledger.csv"
}

RewardTrackerTotalsPath() {
    dir := A_AppData "\\Ultimate_Macro"
    if !DirExist(dir)
        DirCreate(dir)
    return dir "\\reward_totals.ini"
}

RewardTrackerAppend(runId, mapName, modeName, rewardKey, displayName, quantity, confidence := 1.0, evidence := "template") {
    quantity := Integer(quantity)
    if (quantity <= 0)
        return false
    confidence := Number(confidence)
    if (confidence < 0 || confidence > 1)
        throw Error("Reward confidence must be between 0 and 1.")

    key := RewardTrackerSafeKey(rewardKey)
    ledger := RewardTrackerLedgerPath()
    if !FileExist(ledger)
        FileAppend("recorded_at,run_id,map,mode,reward_key,display_name,quantity,confidence,evidence`r`n", ledger, "UTF-8")

    row := RewardTrackerEscapeCsv(FormatTime(, "yyyy-MM-dd HH:mm:ss")) ","
        . RewardTrackerEscapeCsv(runId) ","
        . RewardTrackerEscapeCsv(mapName) ","
        . RewardTrackerEscapeCsv(modeName) ","
        . RewardTrackerEscapeCsv(key) ","
        . RewardTrackerEscapeCsv(displayName) ","
        . quantity "," Round(confidence, 3) ","
        . RewardTrackerEscapeCsv(evidence) "`r`n"
    FileAppend(row, ledger, "UTF-8")

    totals := RewardTrackerTotalsPath()
    lifetime := Integer(IniRead(totals, "Lifetime", key, 0)) + quantity
    session := Integer(IniRead(totals, "Session", key, 0)) + quantity
    IniWrite(lifetime, totals, "Lifetime", key)
    IniWrite(session, totals, "Session", key)
    IniWrite(displayName, totals, "DisplayNames", key)
    IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), totals, "Meta", "LastUpdated")
    return true
}

RewardTrackerResetSession() {
    totals := RewardTrackerTotalsPath()
    try IniDelete(totals, "Session")
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

; Called by an integration layer after matching a known icon and OCRing its quantity.
RewardTrackerAcceptCandidate(candidate) {
    ; candidate = {key, display, quantity, confidence, evidence}
    if !IsObject(candidate)
        return {accepted: false, reason: "invalid-candidate"}
    if !candidate.HasOwnProp("key") || !candidate.HasOwnProp("quantity") || !candidate.HasOwnProp("confidence")
        return {accepted: false, reason: "missing-fields"}
    quantity := Integer(candidate.quantity)
    confidence := Number(candidate.confidence)
    if (quantity <= 0 || quantity > 100000000)
        return {accepted: false, reason: "quantity-out-of-range"}
    ; Item templates should be conservative. Currency text readers may pass 1.0.
    if (confidence < 0.82)
        return {accepted: false, reason: "low-confidence"}
    return {accepted: true, reason: "confirmed"}
}
