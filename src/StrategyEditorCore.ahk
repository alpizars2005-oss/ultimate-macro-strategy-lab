#Requires AutoHotkey v2.0

class StratDocument {
    __New(path) {
        this.Path := path
        this.Text := FileRead(path, "UTF-8")
        this.Newline := InStr(this.Text, "`r`n") ? "`r`n" : "`n"
        normalized := StrReplace(this.Text, "`r")
        this.Lines := StrSplit(normalized, "`n")
        this.Placements := []
        this.Settings := Map()
        this.RequiredTowers := []
        this.Parse()
    }

    Parse() {
        section := ""
        for lineNo, line in this.Lines {
            trimmed := Trim(line)
            if RegExMatch(trimmed, "^\[([^\]]+)\]$", &sectionMatch) {
                section := StrLower(Trim(sectionMatch[1]))
                continue
            }

            if (section = "settings" && RegExMatch(line, "^\s*([^=]+?)\s*=\s*(.*)$", &settingMatch)) {
                key := StrLower(Trim(settingMatch[1]))
                value := Trim(settingMatch[2])
                this.Settings[key] := value
                continue
            }

            if (section != "steps")
                continue

            if RegExMatch(line, "i)^\s*SpawnTower\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*([^,]+?)\s*,\s*([^)]+?)\s*\)\s*$", &m) {
                this.Placements.Push({
                    lineNo: lineNo,
                    x: Integer(m[1]),
                    y: Integer(m[2]),
                    slot: Trim(m[3]),
                    towerId: Trim(m[4]),
                    originalLine: line
                })
            }
        }

        towersText := this.Settings.Has("requiredtowers") ? this.Settings["requiredtowers"] : ""
        if (towersText != "") {
            for tower in StrSplit(towersText, ",") {
                tower := Trim(tower)
                if (tower != "")
                    this.RequiredTowers.Push(tower)
            }
        }
    }

    TowerNameForSlot(slotText) {
        if !RegExMatch(String(slotText), "^\d+$")
            return ""
        slot := Integer(slotText)
        return (slot >= 1 && slot <= this.RequiredTowers.Length) ? this.RequiredTowers[slot] : ""
    }

    UpdatePlacement(placement, newX, newY) {
        placement.x := Integer(newX)
        placement.y := Integer(newY)
        line := this.Lines[placement.lineNo]
        replacement := "$1" placement.x "$2" placement.y
        updated := RegExReplace(
            line,
            "i)^(\s*SpawnTower\(\s*)-?\d+(\s*,\s*)-?\d+",
            replacement,
            &count,
            1
        )
        if (count != 1)
            throw Error("Could not rewrite SpawnTower coordinates on line " placement.lineNo ".")
        this.Lines[placement.lineNo] := updated
    }

    RenderText() {
        output := ""
        for index, line in this.Lines
            output .= (index = 1 ? "" : this.Newline) line
        return output
    }

    SaveCopy(path) {
        if FileExist(path)
            FileDelete(path)
        FileAppend(this.RenderText(), path, "UTF-8-RAW")
    }

    OverwriteWithBackup() {
        stamp := FormatTime(, "yyyyMMdd-HHmmss")
        SplitPath(this.Path, &name, &dir, &ext, &nameNoExt)
        backup := dir "\\" nameNoExt ".backup-" stamp "." ext
        FileCopy(this.Path, backup, false)
        temp := this.Path ".editor.tmp"
        if FileExist(temp)
            FileDelete(temp)
        FileAppend(this.RenderText(), temp, "UTF-8-RAW")
        FileMove(temp, this.Path, 1)
        return backup
    }
}
