#Requires AutoHotkey v2.0

; Roomy, balanced editor workspace without changing the compact layout of other tabs.
global LabEditorWorkspaceActive := false
global LabEditorWorkspaceLastExpanded := ""
global LabEditorWorkspaceGuiW := 1000
global LabEditorWorkspaceGuiH := 690
global LabEditorCompactGuiW := 700
global LabEditorCompactGuiH := 565
global LabEditorWorkspaceCanvasW := 646
global LabEditorWorkspaceCanvasH := 348
global LabEditorWorkspaceExpandedW := 960
global LabEditorWorkspaceExpandedH := 430

SetTimer(StrategyEditorWorkspaceMonitor, 75)

StrategyEditorWorkspaceMonitor(*) {
    global LabEditorWorkspaceActive, LabEditorWorkspaceLastExpanded, LabEditorExpanded
    global LabEditorCanvasBg, LabEditorSnapshot

    editorVisible := false
    try editorVisible := LabEditorCanvasBg.Visible || LabEditorSnapshot.Visible

    if editorVisible {
        if !LabEditorWorkspaceActive {
            StrategyEditorWorkspaceEnter()
            return
        }
        if (LabEditorWorkspaceLastExpanded != LabEditorExpanded)
            StrategyEditorWorkspaceApply(true)
        return
    }

    if LabEditorWorkspaceActive
        StrategyEditorWorkspaceLeave()
}

StrategyEditorWorkspaceEnter() {
    global MainGui, LabEditorWorkspaceActive, LabEditorWorkspaceGuiW, LabEditorWorkspaceGuiH
    if LabEditorWorkspaceActive
        return

    try MainGui.Move(, , LabEditorWorkspaceGuiW, LabEditorWorkspaceGuiH)
    LabEditorWorkspaceActive := true
    StrategyEditorWorkspaceApply(true)
}

StrategyEditorWorkspaceLeave() {
    global MainGui, LabEditorWorkspaceActive, LabEditorWorkspaceLastExpanded
    global LabEditorCompactGuiW, LabEditorCompactGuiH

    if !LabEditorWorkspaceActive
        return

    try MainGui.Move(, , LabEditorCompactGuiW, LabEditorCompactGuiH)
    LabEditorWorkspaceActive := false
    LabEditorWorkspaceLastExpanded := ""
}

StrategyEditorWorkspaceApply(rerender := false) {
    global LabEditorExpanded, LabEditorWorkspaceLastExpanded
    global LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH
    global LabEditorWorkspaceCanvasW, LabEditorWorkspaceCanvasH
    global LabEditorWorkspaceExpandedW, LabEditorWorkspaceExpandedH

    global LabEditorTitle, LabEditorSubtitle, LabEditorHeaderLine, LabEditorAssetBadge
    global LabEditorOpenBtn, LabEditorCurrentBtn, LabEditorSnapshotBtn, LabEditorCaptureBtn
    global LabEditorUndoBtn, LabEditorRedoBtn, LabEditorZoomOutBtn, LabEditorZoomLabel
    global LabEditorZoomInBtn, LabEditorFitBtn, LabEditorExpandBtn
    global LabEditorLayerLabel, LabEditorLayerCtrl, LabEditorSyncBtn, LabEditorMapLabel
    global LabEditorCanvasBg, LabEditorSnapshot, LabEditorCanvasHint
    global LabEditorInfoPanel, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList
    global LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl
    global LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus

    wantedW := LabEditorExpanded ? LabEditorWorkspaceExpandedW : LabEditorWorkspaceCanvasW
    wantedH := LabEditorExpanded ? LabEditorWorkspaceExpandedH : LabEditorWorkspaceCanvasH
    geometryChanged := (LabEditorCanvasW != wantedW || LabEditorCanvasH != wantedH)

    LabEditorCanvasX := 20
    LabEditorCanvasY := 205
    LabEditorCanvasW := wantedW
    LabEditorCanvasH := wantedH
    LabEditorWorkspaceLastExpanded := LabEditorExpanded

    ; Header: use the whole width instead of leaving a dead right half.
    try LabEditorTitle.Move(20, 94, 320, 24)
    try LabEditorSubtitle.Move(20, 116, 520, 18)
    try LabEditorAssetBadge.Move(700, 101, 280, 18)
    try LabEditorHeaderLine.Move(20, 137, 960, 1)

    ; Primary toolbar: commands on the left, precision controls aligned to the right.
    try LabEditorOpenBtn.Move(20, 145, 60, 28)
    try LabEditorCurrentBtn.Move(84, 145, 84, 28)
    try LabEditorSnapshotBtn.Move(172, 145, 76, 28)
    try LabEditorCaptureBtn.Move(252, 145, 72, 28)
    try LabEditorUndoBtn.Move(340, 145, 60, 28)
    try LabEditorRedoBtn.Move(404, 145, 60, 28)
    try LabEditorZoomOutBtn.Move(718, 145, 32, 28)
    try LabEditorZoomLabel.Move(754, 145, 58, 28)
    try LabEditorZoomInBtn.Move(816, 145, 32, 28)
    try LabEditorFitBtn.Move(852, 145, 52, 28)
    try LabEditorExpandBtn.Move(910, 145, 70, 28)

    ; Secondary toolbar.
    try LabEditorLayerLabel.Move(20, 181, 38, 18)
    try LabEditorLayerCtrl.Move(62, 177, 220, 24)
    try LabEditorSyncBtn.Move(292, 177, 100, 24)
    try LabEditorMapLabel.Move(700, 181, 280, 18)

    ; Main tactical canvas.
    try LabEditorCanvasBg.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    try LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    try LabEditorCanvasHint.Move(
        LabEditorCanvasX + 58,
        LabEditorCanvasY + Floor(LabEditorCanvasH / 2) - 28,
        Max(280, LabEditorCanvasW - 116),
        56
    )

    ; Details pane is a clean 298px column aligned with the canvas.
    try LabEditorInfoPanel.Move(682, 205, 298, 348)
    try LabEditorTowerPortrait.Move(700, 222, 88, 88)
    try LabEditorTowerName.Move(802, 222, 164, 40)
    try LabEditorTowerMeta.Move(802, 266, 164, 44)
    try LabEditorList.Move(700, 322, 264, 216)
    try {
        LabEditorList.ModifyCol(1, 32)
        LabEditorList.ModifyCol(2, 142)
        LabEditorList.ModifyCol(3, 42)
        LabEditorList.ModifyCol(4, 42)
    }

    ; Bottom command strip mirrors the two-column layout above.
    try LabEditorCoordLabel.Move(20, 566, 120, 20)
    try LabEditorXCtrl.Move(146, 562, 78, 26)
    try LabEditorYCtrl.Move(230, 562, 78, 26)
    try LabEditorApplyBtn.Move(316, 560, 92, 30)
    try LabEditorSaveBtn.Move(416, 560, 100, 30)
    try LabEditorDirtyLabel.Move(682, 566, 298, 18)
    try LabEditorOverwriteBtn.Move(682, 588, 298, 30)
    try LabEditorDirty.Move(20, 600, 646, 18)
    try LabEditorStatus.Move(20, 626, 960, 36)

    if (geometryChanged || rerender)
        try StrategyEditorRenderBackground()
}
