#Requires AutoHotkey v2.0

StrategyEditorSaveCopy(*) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc) {
        StrategyEditorSetStatus("Open a strategy first.", true)
        return
    }
    SplitPath(LabEditorDoc.Path, &name, &dir, &ext, &nameNoExt)
    suggested := dir "\" nameNoExt "_edited.strat"
    path := FileSelect("S16", suggested, "Save edited strategy copy", "Strategy (*.strat)")
    if (path = "")
        return
    if !RegExMatch(path, "i)\.strat$")
        path .= ".strat"
    try {
        LabEditorDoc.SaveCopy(path)
        StrategyEditorSetStatus("Saved edited copy: " path)
    } catch Error as err {
        StrategyEditorSetStatus("Save failed: " err.Message, true)
    }
}

StrategyEditorOverwrite(*) {
    global LabEditorDoc
    if !IsObject(LabEditorDoc) {
        StrategyEditorSetStatus("Open a strategy first.", true)
        return
    }
    answer := MsgBox("Overwrite the original strategy?`n`nA timestamped .backup file will be created first.", "Strategy Lab", "YesNo Icon!")
    if (answer != "Yes")
        return
    try {
        backup := LabEditorDoc.OverwriteWithBackup()
        StrategyEditorSetStatus("Original updated safely. Backup: " backup)
        StrategyEditorRefreshDirty()
    } catch Error as err {
        StrategyEditorSetStatus("Overwrite failed: " err.Message, true)
    }
}

StrategyEditorRefreshButtons() {
    global LabEditorDoc, LabEditorUndoBtn, LabEditorRedoBtn, LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn
    loaded := IsObject(LabEditorDoc)
    LabEditorUndoBtn.Enabled := loaded && LabEditorDoc.CanUndo()
    LabEditorRedoBtn.Enabled := loaded && LabEditorDoc.CanRedo()
    LabEditorApplyBtn.Enabled := loaded
    LabEditorSaveBtn.Enabled := loaded
    LabEditorOverwriteBtn.Enabled := loaded
}

StrategyEditorRefreshDirty() {
    global LabEditorDoc, LabEditorDirty
    if !IsObject(LabEditorDoc) {
        LabEditorDirty.Text := "No strategy loaded."
        return
    }
    LabEditorDirty.Text := (LabEditorDoc.Dirty ? "UNSAVED CHANGES - " : "Saved state - ") . LabEditorDoc.StrategyWidth "x" LabEditorDoc.StrategyHeight . " - " LabEditorDoc.Placements.Length " placements"
}

StrategyEditorSetStatus(text, isError := false) {
    global LabEditorStatus
    LabEditorStatus.SetFont("c" (isError ? "FF7777" : "AAAAAA"))
    LabEditorStatus.Text := text
}
