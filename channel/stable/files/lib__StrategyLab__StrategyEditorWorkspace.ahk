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

; Decorative/semantic labels are created lazily only for the Editor workspace so
; the compact upstream tabs keep their original visual footprint.
global LabEditorSelectedTitle := ""
global LabEditorPlacementsTitle := ""
global LabEditorPositionTitle := ""
global LabEditorSaveTitle := ""
global LabEditorPanelAccent := ""

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

StrategyEditorWorkspaceEnsureDecor() {
    global MainGui
    global LabEditorSelectedTitle, LabEditorPlacementsTitle, LabEditorPositionTitle, LabEditorSaveTitle, LabEditorPanelAccent

    if IsObject(LabEditorSelectedTitle)
        return

    MainGui.SetFont("s7 w700 c6D7785", "Segoe UI")
    LabEditorSelectedTitle := MainGui.Add("Text", "x700 y213 w264 h18 Hidden Background171717", "SELECTED UNIT")
    LabEditorPlacementsTitle := MainGui.Add("Text", "x700 y347 w264 h18 Hidden Background171717", "PLACEMENTS")
    LabEditorPositionTitle := MainGui.Add("Text", "x20 y558 w180 h18 Hidden", "POSITION")
    LabEditorSaveTitle := MainGui.Add("Text", "x682 y558 w298 h18 Hidden Right", "SAFE SAVE")
    LabEditorPanelAccent := MainGui.Add("Progress", "x682 y205 w3 h348 Hidden Background4CA3FF", 0)
}

StrategyEditorWorkspaceDecorVisible(show := true) {
    global LabEditorSelectedTitle, LabEditorPlacementsTitle, LabEditorPositionTitle, LabEditorSaveTitle, LabEditorPanelAccent
    for ctrl in [LabEditorSelectedTitle, LabEditorPlacementsTitle, LabEditorPositionTitle, LabEditorSaveTitle, LabEditorPanelAccent] {
        if IsObject(ctrl)
            ctrl.Visible := show
    }
}

StrategyEditorWorkspaceEnter() {
    global MainGui, LabEditorWorkspaceActive, LabEditorWorkspaceGuiW, LabEditorWorkspaceGuiH
    if LabEditorWorkspaceActive
        return

    try MainGui.Move(, , LabEditorWorkspaceGuiW, LabEditorWorkspaceGuiH)
    LabEditorWorkspaceActive := true
    StrategyEditorWorkspaceEnsureDecor()
    StrategyEditorWorkspaceApply(true)
}

StrategyEditorWorkspaceLeave() {
    global MainGui, LabEditorWorkspaceActive, LabEditorWorkspaceLastExpanded
    global LabEditorCompactGuiW, LabEditorCompactGuiH

    if !LabEditorWorkspaceActive
        return

    StrategyEditorWorkspaceDecorVisible(false)
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
    global LabEditorSelectedTitle, LabEditorPlacementsTitle, LabEditorPositionTitle, LabEditorSaveTitle, LabEditorPanelAccent

    StrategyEditorWorkspaceEnsureDecor()

    wantedW := LabEditorExpanded ? LabEditorWorkspaceExpandedW : LabEditorWorkspaceCanvasW
    wantedH := LabEditorExpanded ? LabEditorWorkspaceExpandedH : LabEditorWorkspaceCanvasH
    geometryChanged := (LabEditorCanvasW != wantedW || LabEditorCanvasH != wantedH)

    LabEditorCanvasX := 20
    LabEditorCanvasY := 205
    LabEditorCanvasW := wantedW
    LabEditorCanvasH := wantedH
    LabEditorWorkspaceLastExpanded := LabEditorExpanded

    ; Stronger type hierarchy: title/status read as a workspace, not a debug panel.
    try LabEditorTitle.SetFont("s12 w700 c55B7FF", "Segoe UI")
    try LabEditorSubtitle.SetFont("s7 w500 c83909C", "Segoe UI")
    try LabEditorAssetBadge.SetFont("s8 w600 c86C9D8", "Segoe UI")
    try LabEditorMapLabel.SetFont("s8 w600 cAAB7C4", "Segoe UI")
    try LabEditorTowerName.SetFont("s11 w700 cF4F7FA", "Segoe UI")
    try LabEditorTowerMeta.SetFont("s8 w400 c9CA8B4", "Segoe UI")
    try LabEditorDirty.SetFont("s8 w600 cAAB7C4", "Segoe UI")
    try LabEditorStatus.SetFont("s8 w400 c8794A0", "Segoe UI")

    ; Header: use the whole width instead of leaving a dead right half.
    try LabEditorTitle.Move(20, 92, 340, 26)
    try LabEditorSubtitle.Move(20, 118, 550, 17)
    try LabEditorAssetBadge.Move(690, 100, 290, 20)
    try LabEditorHeaderLine.Move(20, 137, 960, 1)

    ; Primary toolbar: workflow actions left, navigation/zoom grouped right.
    try LabEditorOpenBtn.Move(20, 145, 60, 28)
    try LabEditorCurrentBtn.Move(84, 145, 84, 28)
    try LabEditorSnapshotBtn.Move(172, 145, 80, 28)
    try {
        LabEditorCaptureBtn.Text := "Capture Map"
        LabEditorCaptureBtn.Move(256, 145, 92, 28)
    }
    try LabEditorUndoBtn.Move(364, 145, 60, 28)
    try LabEditorRedoBtn.Move(428, 145, 60, 28)
    try LabEditorZoomOutBtn.Move(718, 145, 32, 28)
    try LabEditorZoomLabel.Move(754, 145, 58, 28)
    try LabEditorZoomInBtn.Move(816, 145, 32, 28)
    try LabEditorFitBtn.Move(852, 145, 52, 28)
    try LabEditorExpandBtn.Move(910, 145, 70, 28)

    ; Secondary toolbar leaves breathing room between filtering and map identity.
    try LabEditorLayerLabel.Move(20, 181, 38, 18)
    try LabEditorLayerCtrl.Move(62, 177, 226, 24)
    try LabEditorSyncBtn.Move(298, 177, 104, 24)
    try LabEditorMapLabel.Move(680, 181, 300, 18)

    ; Main tactical canvas.
    try LabEditorCanvasBg.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    try LabEditorSnapshot.Move(LabEditorCanvasX, LabEditorCanvasY, LabEditorCanvasW, LabEditorCanvasH)
    try LabEditorCanvasHint.Move(
        LabEditorCanvasX + 58,
        LabEditorCanvasY + Floor(LabEditorCanvasH / 2) - 28,
        Max(280, LabEditorCanvasW - 116),
        56
    )

    ; Details card: full portrait preview, clear identity, then the placement table.
    try LabEditorInfoPanel.Move(682, 205, 298, 348)
    try LabEditorPanelAccent.Move(682, 205, 3, 348)
    try LabEditorSelectedTitle.Move(700, 212, 264, 18)
    try LabEditorTowerPortrait.Move(700, 234, 104, 104)
    try LabEditorTowerName.Move(816, 237, 148, 42)
    try LabEditorTowerMeta.Move(816, 282, 148, 54)
    try LabEditorPlacementsTitle.Move(700, 345, 264, 18)
    try LabEditorList.Move(700, 365, 264, 173)
    try {
        LabEditorList.ModifyCol(1, 32)
        LabEditorList.ModifyCol(2, 142)
        LabEditorList.ModifyCol(3, 42)
        LabEditorList.ModifyCol(4, 42)
    }

    ; Bottom command strip mirrors the two-column layout above.
    try LabEditorPositionTitle.Move(20, 557, 180, 18)
    try LabEditorSaveTitle.Move(682, 557, 298, 18)
    try {
        LabEditorCoordLabel.Text := "X / Y"
        LabEditorCoordLabel.Move(20, 579, 50, 20)
    }
    try LabEditorXCtrl.Move(76, 575, 82, 26)
    try LabEditorYCtrl.Move(164, 575, 82, 26)
    try LabEditorApplyBtn.Move(254, 573, 98, 30)
    try LabEditorSaveBtn.Move(360, 573, 104, 30)
    try {
        LabEditorDirtyLabel.Text := "Edits stay local until you save"
        LabEditorDirtyLabel.Move(682, 578, 298, 18)
    }
    try LabEditorOverwriteBtn.Move(682, 600, 298, 30)
    try LabEditorDirty.Move(20, 612, 646, 18)
    try LabEditorStatus.Move(20, 638, 960, 30)

    StrategyEditorWorkspaceDecorVisible(!LabEditorExpanded)

    if (geometryChanged || rerender) {
        try {
            if IsFunc(StrategyEditorRenderBackgroundBuffered)
                StrategyEditorRenderBackgroundBuffered()
            else
                StrategyEditorRenderBackground()
        } catch {
            try StrategyEditorRenderBackground()
        }
    }
}
