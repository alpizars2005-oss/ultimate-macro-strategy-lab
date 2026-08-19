#Requires AutoHotkey v2.0

; Shared native-control lifecycle guards. The 0.4 editor has one composited Picture
; canvas, but timers can still outlive Gui.Controls briefly during updater/ExitApp.

global LabEditorShuttingDown := false

LabEditorControlAlive(ctrl) {
    if !IsObject(ctrl)
        return false
    hwnd := 0
    try hwnd := ctrl.Hwnd
    catch
        return false
    if !hwnd
        return false
    try return DllCall("user32\IsWindow", "Ptr", hwnd, "Int") != 0
    catch
        return false
}

LabEditorControlVisible(ctrl) {
    if !LabEditorControlAlive(ctrl)
        return false
    visible := false
    try visible := ctrl.Visible
    catch
        return false
    return !!visible
}

LabEditorRemoveLegacyVisualAssets() {
    ; Old 0.3.x footprint images are intentionally ignored by the 0.4 renderer. Remove
    ; the Lab-owned cache copy so an upgraded install cannot accidentally resurrect it.
    legacy := A_ScriptDir "\Resources\StrategyLab\Towers\footprint-guide.png"
    if FileExist(legacy)
        try FileDelete(legacy)
}

LabEditorLifecycleExit(*) {
    global LabEditorShuttingDown, LabEditorCanvasBg, LabEditorSnapshot, LabEditorHitRegions
    LabEditorShuttingDown := true

    try SetTimer(StrategyEditorWorkspaceMonitor, 0)
    try SetTimer(StrategyEditorInteractiveStateGuard, 0)
    try SetTimer(StrategyEditorInstallDirectNavigation, 0)
    try SetTimer(StrategyEditorWheelFlush, 0)
    try SetTimer(LabStatsRefresh, 0)

    LabEditorHitRegions := []
    LabEditorCanvasBg := ""
    LabEditorSnapshot := ""
}

LabEditorRemoveLegacyVisualAssets()
OnExit(LabEditorLifecycleExit)
