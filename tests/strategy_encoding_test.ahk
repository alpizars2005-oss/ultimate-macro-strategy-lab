#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

root := A_Temp "\StrategyLabEncodingTest-" A_TickCount
DirCreate(root)
baseText := "[Settings]`r`nRequiredTowers=Scout`r`n`r`n[Steps]`r`nSpawnTower(100, 200, 1, 123)`r`n"

try {
    fixtures := [
        {Name: "utf8-raw", Path: root "\utf8-raw.strat", Encoding: "UTF-8-RAW", TerminalNuls: 0},
        {Name: "utf8-bom", Path: root "\utf8-bom.strat", Encoding: "UTF-8", TerminalNuls: 0},
        {Name: "utf16-raw", Path: root "\utf16-raw.strat", Encoding: "UTF-16-RAW", TerminalNuls: 0},
        {Name: "utf16-bom", Path: root "\utf16-bom.strat", Encoding: "UTF-16", TerminalNuls: 0},
        {Name: "utf8-terminal-null", Path: root "\utf8-terminal-null.strat", Encoding: "UTF-8-RAW", TerminalNuls: 1},
        {Name: "utf16-terminal-null", Path: root "\utf16-terminal-null.strat", Encoding: "UTF-16-RAW", TerminalNuls: 1}
    ]

    FileAppend(baseText, fixtures[1].Path, "UTF-8-RAW")
    FileAppend(baseText, fixtures[2].Path, "UTF-8")
    FileAppend(baseText, fixtures[3].Path, "UTF-16-RAW")
    FileAppend(baseText, fixtures[4].Path, "UTF-16")
    FileAppend(baseText Chr(0), fixtures[5].Path, "UTF-8-RAW")
    FileAppend(baseText Chr(0), fixtures[6].Path, "UTF-16-RAW")

    for fixture in fixtures {
        result := LabStrategyValidate(fixture.Path)
        if (result.Encoding != fixture.Encoding)
            throw Error(fixture.Name ": expected encoding " fixture.Encoding ", got " result.Encoding)
        if (result.TerminalNuls != fixture.TerminalNuls)
            throw Error(fixture.Name ": expected terminal NUL count " fixture.TerminalNuls ", got " result.TerminalNuls)
        if (result.Placements != 1)
            throw Error(fixture.Name ": expected one SpawnTower placement.")
    }

    bad := root "\embedded-null.strat"
    FileAppend("[Steps]`r`nSpawn" Chr(0) "Tower(100, 200, 1, 123)`r`n", bad, "UTF-8-RAW")
    rejected := false
    try LabStrategyValidate(bad)
    catch Error {
        rejected := true
    }
    if !rejected
        throw Error("Embedded NUL fixture was not rejected.")

    DirDelete(root, 1)
    ExitApp(0)
} catch Error as err {
    try FileAppend(err.Message "`r`n", root "\failure.txt", "UTF-8")
    try FileAppend(err.Message "`r`n", "*", "UTF-8")
    ExitApp(1)
}

#Include "%A_ScriptDir%\..\channel\stable\files\lib__StrategyLab__LabStrategyValidation.ahk"
