#Requires AutoHotkey v2.0

; Roomy editor workspace without changing the compact layout of the other tabs.
; The monitor keys off the editor canvas visibility instead of CurrentTab so it
; remains safe during startup/bootstrap and while Capture temporarily hides MainGui.

global LabEditorWorkspaceActive := false
global LabEditorWorkspaceLastExpanded := ""
global LabEditorWorkspaceGuiW := 1000
global LabEditorWorkspaceGuiH := 690
global LabEditorCompactGuiW := 700
global LabEditorCompactGuiH := 565
global LabEditorWorkspaceCanvasW := 640
global LabEditorWorkspaceCanvasH := 340
global LabEditorWorkspaceExpandedW := 960
global LabEditorWorkspaceExpandedH := 440

; A short poll keeps tab transitions feeling immediate without tying the module to
; Main.ahk's initialization order.
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
    global LabEditorCanvasBg, LabEditorSnapshot, LabEditorCanvasHint
    global LabEditorAssetBadge, LabEditorMapLabel
    global LabEditorInfoPanel, LabEditorTowerPortrait, LabEditorTowerName, LabEditorTowerMeta, LabEditorList
    global LabEditorCoordLabel, LabEditorDirtyLabel, LabEditorXCtrl, LabEditorYCtrl
    global LabEditorApplyBtn, LabEditorSaveBtn, LabEditorOverwriteBtn, LabEditorDirty, LabEditorStatus

    wantedW := LabEditorExpanded ? LabEditorWorkspaceExpandedW : LabEditorWorkspaceCanvasW
    wantedH := LabEditorExpanded ? LabEditorWorkspaceExpandedH : LabEditorWorkspaceCanvasH
    geometryChanged := (LabEditorCanvasW != wantedW || LabEditorCanvasH != wantedH)

    LabEditorCanvasW := wantedW
    LabEditorCanvasH := wantedH
    LabEditorWorkspaceLastExpanded := LabEditorExpanded

    ; Header metadata gets the extra horizontal breathing room.
    try LabEditorAssetBadge.Move(760, 103, 220, 18)
    try LabEditorMapLabel.Move(740, 181, 240, 18)

    ; Main tactical canvas.
    try LabEditorCanvasBg.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    try LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    try LabEditorCanvasHint.Move(
        LabEditorCanvasX + 54,
        LabEditorCanvasY + Floor(LabEditorCanvasH / 2) - 28,
        Max(260, LabEditorCanvasW - 108),
        56
    )

    ; Roomier right-hand placement/details pane in normal editor mode.
    try LabEditorInfoPanel.Move(680, 205, 300, 340)
    try LabEditorTowerPortrait.Move(696, 220, 82, 82)
    try LabEditorTowerName.Move(792, 220, 174, 40)
    try LabEditorTowerMeta.Move(792, 263, 174, 38)
    try LabEditorList.Move(696, 312, 270, 218)
    try {
        LabEditorList.ModifyCol(1, 30)
        LabEditorList.ModifyCol(2, 150)
        LabEditorList.ModifyCol(3, 42)
        LabEditorList.ModifyCol(4, 42)
    }

    ; Editing/save row and status area.
    try LabEditorCoordLabel.Move(20, 558, 124, 20)
    try LabEditorXCtrl.Move(146, 554, 72, 26)
    try LabEditorYCtrl.Move(224, 554, 72, 26)
    try LabEditorApplyBtn.Move(302, 552, 92, 30)
    try LabEditorSaveBtn.Move(402, 552, 92, 30)
    try LabEditorDirtyLabel.Move(680, 558, 300, 20)
    try LabEditorOverwriteBtn.Move(680, 584, 300, 30)
    try LabEditorDirty.Move(20, 594, 640, 20)
    try LabEditorStatus.Move(20, 620, 960, 42)

    if (geometryChanged || rerender)
        try StrategyEditorRenderBackground()
}
