#Requires AutoHotkey v2.0

; Defensive validation inspired by the strict-load contract in Macro-Recorder-JSON.
; The editor still preserves unknown/future strategy actions; this only rejects files
; that are clearly malformed or unreasonably large before they enter the visual editor.

LabStrategyValidate(path) {
    if (path = "" || !FileExist(path))
        throw Error("Strategy file does not exist.")

    size := FileGetSize(path)
    if (size <= 0)
        throw Error("Strategy file is empty.")
    if (size > 5 * 1024 * 1024)
        throw Error("Strategy file is larger than the 5 MB editor safety limit.")

    text := FileRead(path, "UTF-8")
    if InStr(text, Chr(0))
        throw Error("Strategy contains NUL bytes and cannot be edited safely.")
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
            x := Integer(m[1]), y := Integer(m[2])
            if (Abs(x) > 10000 || Abs(y) > 10000)
                suspicious += 1
        }
    }

    if (spawnCount = 0)
        throw Error("No SpawnTower placements were found in [Steps].")
    if (suspicious > 0)
        throw Error("Strategy contains placement coordinates outside the editor safety envelope.")

    return {size: size, placements: spawnCount}
}
