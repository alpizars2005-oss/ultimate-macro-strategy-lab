#Requires AutoHotkey v2.0

; Conservative .strat document editor.
; It only rewrites the first two arguments of a selected SpawnTower line.
; Every other line remains byte-for-byte equivalent apart from newline normalization
; when the file is intentionally saved.

class LabStratDocument {
    __New(path) {
        if !FileExist(path)
            throw Error("Strategy file does not exist.")
        this.Path := path
        this.Text := FileRead(path, "UTF-8")
        this.Newline := InStr(this.Text, "`r`n") ? "`r`n" : "`n"
        normalized := StrReplace(this.Text, "`r")
        this.Lines := StrSplit(normalized, "`n")
        this.Placements := []
        this.Settings := Map()
        this.Meta := Map()
        this.RequiredTowers := []
        this.UndoStack := []
        this.RedoStack := []
        this.Dirty := false
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

            if RegExMatch(line, "^\s*([^=]+?)\s*=\s*(.*)$", &kv) {
                key := StrLower(Trim(kv[1]))
                value := Trim(kv[2])
                if (section = "settings")
                    this.Settings[key] := value
                else if (section = "do not edit")
                    this.Meta[key] := value
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

        this.StrategyWidth := (this.Meta.Has("width") && IsNumber(this.Meta["width"])) ? Max(1, Integer(this.Meta["width"])) : 1920
        this.StrategyHeight := (this.Meta.Has("height") && IsNumber(this.Meta["height"])) ? Max(1, Integer(this.Meta["height"])) : 1009
    }

    TowerNameForSlot(slotText) {
        if !RegExMatch(String(slotText), "^\d+$")
            return ""
        slot := Integer(slotText)
        return (slot >= 1 && slot <= this.RequiredTowers.Length) ? this.RequiredTowers[slot] : ""
    }

    PlacementLabel(placement) {
        tower := this.TowerNameForSlot(placement.slot)
        return placement.towerId " | slot " placement.slot (tower != "" ? " | " tower : "")
    }

    RewritePlacement(placement, newX, newY) {
        newX := Integer(newX)
        newY := Integer(newY)
        line := this.Lines[placement.lineNo]
        if !RegExMatch(
            line,
            "i)^(\s*SpawnTower\(\s*)-?\d+(\s*,\s*)-?\d+(.*)$",
            &parts
        )
            throw Error("Could not rewrite SpawnTower coordinates on line " placement.lineNo ".")
        updated := parts[1] newX parts[2] newY parts[3]
        this.Lines[placement.lineNo] := updated
        placement.x := newX
        placement.y := newY
        this.Dirty := true
    }

    MovePlacement(placement, newX, newY, recordHistory := true) {
        newX := Max(0, Min(this.StrategyWidth, Integer(newX)))
        newY := Max(0, Min(this.StrategyHeight, Integer(newY)))
        oldX := placement.x
        oldY := placement.y
        if (oldX = newX && oldY = newY)
            return false

        if recordHistory {
            this.UndoStack.Push({
                placement: placement,
                oldX: oldX, oldY: oldY,
                newX: newX, newY: newY
            })
            this.RedoStack := []
        }
        this.RewritePlacement(placement, newX, newY)
        return true
    }

    CanUndo() => this.UndoStack.Length > 0
    CanRedo() => this.RedoStack.Length > 0

    Undo() {
        if !this.CanUndo()
            return false
        item := this.UndoStack.Pop()
        this.RewritePlacement(item.placement, item.oldX, item.oldY)
        this.RedoStack.Push(item)
        return item.placement
    }

    Redo() {
        if !this.CanRedo()
            return false
        item := this.RedoStack.Pop()
        this.RewritePlacement(item.placement, item.newX, item.newY)
        this.UndoStack.Push(item)
        return item.placement
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
        return path
    }

    OverwriteWithBackup() {
        stamp := FormatTime(, "yyyyMMdd-HHmmss")
        SplitPath(this.Path, &name, &dir, &ext, &nameNoExt)
        backup := dir "\" nameNoExt ".backup-" stamp "." ext
        FileCopy(this.Path, backup, false)

        temp := this.Path ".strategy-lab.tmp"
        if FileExist(temp)
            FileDelete(temp)
        FileAppend(this.RenderText(), temp, "UTF-8-RAW")
        FileMove(temp, this.Path, 1)
        this.Dirty := false
        return backup
    }
}
