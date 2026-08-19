#Requires AutoHotkey v2.0

; Strategy Editor lifecycle + visual safety guard.
;
; Windows/AHK can leave Gui.Control objects alive briefly after their HWND has already
; been destroyed during updater/ExitApp transitions. IsObject() is therefore not a
; sufficient liveness test. All timer/message-loop checks should use these helpers.
;
; 0.3.11 also intentionally disables the old footprint Picture-HWND overlay. A
; transparent child/sibling Static control does not alpha-composite against the map
; Picture underneath on all Windows builds; its transparent pixels can reveal the GUI
; parent instead and produce the black/square visual tearing seen in live testing.
; Markers remain one circular HWND per placement. Footprints will return only when they
; are composited into the map frame itself, never as a second sibling control.

global LabEditorShuttingDown := false
global LabEditorFootprintUiAttempts := 0

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

LabEditorDisableSiblingFootprints() {
    global LabEditorRingMode, LabEditorRingTemplatePath
    ; Stop shipping/runtime leftovers from being picked up by StrategyEditorRingImagePath.
    ; Deleting the Lab-owned cosmetic asset is safe and prevents a second Picture HWND
    ; from ever being created on an updated installation.
    legacy := A_ScriptDir "\Resources\StrategyLab\Towers\footprint-guide.png"
    if FileExist(legacy)
        try FileDelete(legacy)
    LabEditorRingTemplatePath := ""
    LabEditorRingMode := "off"
}

LabEditorApplySafeFootprintUi(*) {
    global LabEditorRingsBtn, LabEditorFootprintUiAttempts, LabEditorShuttingDown
    if LabEditorShuttingDown
        return

    LabEditorFootprintUiAttempts += 1
    if !IsSet(LabEditorRingsBtn) || !LabEditorControlAlive(LabEditorRingsBtn) {
        if (LabEditorFootprintUiAttempts < 24)
            SetTimer(LabEditorApplySafeFootprintUi, -250)
        return
    }

    ; Keep the control visible as an explicit status indicator, but do not let a click
    ; re-enable the retired sibling-HWND code path.
    try LabEditorRingsBtn.Text := "Footprint: Safe Off"
    try LabEditorRingsBtn.Enabled := false
}

LabEditorLifecycleExit(*) {
    global LabEditorShuttingDown, LabEditorCanvasBg, LabEditorSnapshot
    LabEditorShuttingDown := true

    ; Prevent timers from touching controls while AutoHotkey tears down the GUI.
    try SetTimer(StrategyEditorWorkspaceMonitor, 0)
    try SetTimer(StrategyEditorInteractiveStateGuard, 0)
    try SetTimer(LabSimpleFootprintsApply, 0)
    try SetTimer(LabEditorApplySafeFootprintUi, 0)

    ; IsObject(control) remains true after native destruction. Clearing the two active
    ; sentinels makes any late message/timer fail closed instead of dereferencing them.
    LabEditorCanvasBg := ""
    LabEditorSnapshot := ""
}

LabEditorDisableSiblingFootprints()
SetTimer(LabEditorApplySafeFootprintUi, -250)
OnExit(LabEditorLifecycleExit)
