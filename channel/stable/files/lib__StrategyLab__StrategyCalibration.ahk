#Requires AutoHotkey v2.0

; Lightweight bridge between Main_Lab and the isolated calibration worker.
; The worker lives in its own AutoHotkey process so capturing a map never interrupts
; PlayStrategy() timing or the recorder's input hooks.

global LabCalibrationWorkerPid := 0

global LabCalibrationWorkerRetryMs := 30000

LabCalibrationWorkerPath() => A_ScriptDir "\submacros\lab_calibration_worker.ahk"

LabCalibrationEnsureWorker(*) {
    global LabCalibrationWorkerPid, LabCalibrationWorkerRetryMs

    if (LabCalibrationWorkerPid && ProcessExist(LabCalibrationWorkerPid)) {
        SetTimer(LabCalibrationEnsureWorker, -LabCalibrationWorkerRetryMs)
        return
    }

    worker := LabCalibrationWorkerPath()
    if !FileExist(worker) {
        SetTimer(LabCalibrationEnsureWorker, -LabCalibrationWorkerRetryMs)
        return
    }

    parentPid := DllCall("GetCurrentProcessId")
    cmd := '"' A_AhkPath '" "' worker '" --parent ' parentPid
    try Run(cmd, A_ScriptDir, "Hide", &LabCalibrationWorkerPid)
    catch
        LabCalibrationWorkerPid := 0

    SetTimer(LabCalibrationEnsureWorker, -LabCalibrationWorkerRetryMs)
}

; Let the main GUI finish bootstrapping before starting the passive worker.
SetTimer(LabCalibrationEnsureWorker, -1500)
