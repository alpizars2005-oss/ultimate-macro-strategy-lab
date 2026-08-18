#Requires AutoHotkey v2.0

; Defensive strategy decoder. Read the raw bytes first so encoding decisions are based
; on the file itself instead of on a failed text decode. This is important for older
; Ultimate Macro strategies, which may be UTF-8, ANSI, UTF-16LE with/without a BOM,
; and may contain one or more harmless terminal NUL code units.

LabStrategyTrimTerminalNuls(text) {
    removed := 0
    while (StrLen(text) > 0 && SubStr(text, -1) = Chr(0)) {
        text := SubStr(text, 1, StrLen(text) - 1)
        removed += 1
    }
    return {Text: text, Removed: removed}
}

LabStrategyGuessUtf16(raw) {
    sampleSize := Min(raw.Size, 4096)
    pairCount := Floor(sampleSize / 2)
    if (pairCount < 4)
        return ""

    evenZeros := 0
    oddZeros := 0
    Loop pairCount {
        offset := (A_Index - 1) * 2
        if (NumGet(raw, offset, "UChar") = 0)
            evenZeros += 1
        if (NumGet(raw, offset + 1, "UChar") = 0)
            oddZeros += 1
    }

    ; ASCII-heavy UTF-16 text has zero high bytes on most code units. Keep the
    ; threshold deliberately conservative so ordinary binary corruption is rejected.
    if (oddZeros >= Max(4, Floor(pairCount * 0.35)) && oddZeros > evenZeros * 2)
        return "LE"
    if (evenZeros >= Max(4, Floor(pairCount * 0.35)) && evenZeros > oddZeros * 2)
        return "BE"
    return ""
}

LabStrategyDecodeUtf16BE(raw, offset := 0) {
    byteCount := raw.Size - offset
    if (byteCount <= 0)
        return ""
    if (Mod(byteCount, 2) != 0)
        throw Error("UTF-16BE strategy has an odd byte count and appears truncated.")

    swapped := Buffer(byteCount + 2, 0)
    pairCount := Floor(byteCount / 2)
    Loop pairCount {
        src := offset + (A_Index - 1) * 2
        dst := (A_Index - 1) * 2
        NumPut("UChar", NumGet(raw, src + 1, "UChar"), swapped, dst)
        NumPut("UChar", NumGet(raw, src, "UChar"), swapped, dst + 1)
    }
    return StrGet(swapped, pairCount, "UTF-16")
}

LabStrategyReadFile(path) {
    if (path = "" || !FileExist(path))
        throw Error("Strategy file does not exist.")

    raw := FileRead(path, "RAW")
    if (raw.Size <= 0)
        return {Text: "", Encoding: "UTF-8-RAW", TerminalNuls: 0}

    b0 := raw.Size >= 1 ? NumGet(raw, 0, "UChar") : -1
    b1 := raw.Size >= 2 ? NumGet(raw, 1, "UChar") : -1
    b2 := raw.Size >= 3 ? NumGet(raw, 2, "UChar") : -1

    encoding := ""
    text := ""

    if (raw.Size >= 3 && b0 = 0xEF && b1 = 0xBB && b2 = 0xBF) {
        text := FileRead(path, "UTF-8")
        encoding := "UTF-8"
    } else if (raw.Size >= 2 && b0 = 0xFF && b1 = 0xFE) {
        text := FileRead(path, "UTF-16")
        encoding := "UTF-16"
    } else if (raw.Size >= 2 && b0 = 0xFE && b1 = 0xFF) {
        text := LabStrategyDecodeUtf16BE(raw, 2)
        ; AutoHotkey's normal text writers are UTF-16LE. Preserve edit safety by
        ; normalizing this uncommon legacy format to UTF-8 when intentionally saved.
        encoding := "UTF-8"
    } else {
        utf16Guess := LabStrategyGuessUtf16(raw)
        if (utf16Guess = "LE") {
            text := FileRead(path, "UTF-16-RAW")
            encoding := "UTF-16-RAW"
        } else if (utf16Guess = "BE") {
            text := LabStrategyDecodeUtf16BE(raw)
            encoding := "UTF-8"
        } else {
            text := FileRead(path, "UTF-8-RAW")
            encoding := "UTF-8-RAW"

            ; Legacy ANSI strategy files are valid too. A replacement character is a
            ; strong indication that the UTF-8 decode was not faithful, so retry CP0.
            if InStr(text, Chr(0xFFFD)) {
                ansi := FileRead(path, "CP0")
                if !InStr(ansi, Chr(0xFFFD)) {
                    text := ansi
                    encoding := "CP0"
                }
            }
        }
    }

    trimmed := LabStrategyTrimTerminalNuls(text)
    text := trimmed.Text

    if InStr(text, Chr(0))
        throw Error("Strategy contains embedded NUL bytes inside its text and cannot be edited safely.")

    return {Text: text, Encoding: encoding, TerminalNuls: trimmed.Removed}
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
    for rawLine in StrSplit(StrReplace(text, "`r"), "`n") {
        line := Trim(rawLine)
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

    return {
        Size: size,
        Placements: spawnCount,
        Encoding: loaded.Encoding,
        TerminalNuls: loaded.TerminalNuls
    }
}
