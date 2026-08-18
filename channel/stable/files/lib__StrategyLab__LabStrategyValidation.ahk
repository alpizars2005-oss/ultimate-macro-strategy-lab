#Requires AutoHotkey v2.0

; Defensive validation inspired by the strict-load contract in Macro-Recorder-JSON.
; Ultimate Macro strategies may exist as UTF-8 or UTF-16 depending on the writer/
; Windows environment. Detect the text encoding before validation instead of treating
; UTF-16's zero high-bytes as malicious NUL corruption.

LabStrategyReadText(path, &encoding := "") {
    if (path = "" || !FileExist(path))
        throw Error("Strategy file does not exist.")

    ; UTF-8 is the normal Strategy Lab/upstream path. If decoded text contains NULs,
    ; retry as UTF-16; this is the common signature of a valid UTF-16 strategy read as
    ; UTF-8. FileRead's UTF-16 mode honors a BOM and otherwise uses little-endian.
    text := FileRead(path, "UTF-8")
    if !InStr(text, Chr(0)) {
        encoding := "UTF-8"
        return text
    }

    try {
        text16 := FileRead(path, "UTF-16")
        if !InStr(text16, Chr(0)) {
            encoding := "UTF-16"
            return text16
        }
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

    encoding := ""
    text := LabStrategyReadText(path, &encoding)
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

    return {size: size, placements: spawnCount, encoding: encoding}
}
