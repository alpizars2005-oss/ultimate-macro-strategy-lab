#Requires AutoHotkey v2.0

; Defensive validation inspired by the strict-load contract in Macro-Recorder-JSON.
; Keep the file decoder deliberately simple and AutoHotkey-v2-compatible: it returns
; a small object instead of exposing a ByRef output parameter. This removes an entire
; class of parser mistakes such as passing object properties to & parameters.

LabStrategyReadFile(path) {
    if (path = "" || !FileExist(path))
        throw Error("Strategy file does not exist.")

    ; Ultimate Macro normally writes text strategies. UTF-8 is tried first. A valid
    ; UTF-16LE strategy read as UTF-8 contains NUL characters between many letters,
    ; so retry UTF-16 only when that signature is present.
    text := FileRead(path, "UTF-8")
    if !InStr(text, Chr(0))
        return {Text: text, Encoding: "UTF-8"}

    try {
        text16 := FileRead(path, "UTF-16")
        if !InStr(text16, Chr(0))
            return {Text: text16, Encoding: "UTF-16"}
    }

    throw Error("Strategy contains embedded NUL bytes and cannot be edited safely.")
}

LabStrategyValidate(path) {
    if (path = "" || !FileExist(path))
        throw Error("Strategy file does not exist.")

    size := FileGetSize(path)
    if (size <= 0)
        throw Error("Strategy file is empty.")
    if (size > 5 * 1024 * 1024)
        throw Error("Strategy file is larger than the 5 MB editor safety limit.")

    loaded := LabStrategyReadFile(path)
    text := loaded.Text

    if !RegExMatch(text, "im)^\s*\[Steps\]\s*$")
        throw Error("Strategy does not contain a [Steps] section.")

    spawnCount := 0
    suspicious := 0
    for raw in StrSplit(StrReplace(text, "`r"), "`n") {
        line := Trim(raw)
        if !RegExMatch(line, "i)^SpawnTower\(")
            continue

        spawnCount += 1
        if (spawnCount > 5000)
            throw Error("Strategy contains more than 5,000 SpawnTower placements.")

        if RegExMatch(line, "i)^SpawnTower\(\s*(-?\d+)\s*,\s*(-?\d+)", &m) {
            x := Integer(m[1])
            y := Integer(m[2])
            if (Abs(x) > 10000 || Abs(y) > 10000)
                suspicious += 1
        }
    }

    if (spawnCount = 0)
        throw Error("No SpawnTower placements were found in [Steps].")
    if (suspicious > 0)
        throw Error("Strategy contains placement coordinates outside the editor safety envelope.")

    return {Size: size, Placements: spawnCount, Encoding: loaded.Encoding}
}
