$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$preflightSource = Join-Path $repo 'channel\stable\files\submacros__lab_preflight.ps1'
if (!(Test-Path -LiteralPath $preflightSource -PathType Leaf)) {
    throw 'Stable preflight helper was not found.'
}

$root = Join-Path $env:TEMP ('strategy-lab-preflight-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null

try {
    $required = @(
        'lib\StrategyLab\StrategyEditorTab.ahk',
        'lib\StrategyLab\StrategyEditorPlacements.ahk',
        'lib\StrategyLab\StrategyEditorMaps046.ahk',
        'lib\StrategyLab\StrategyEditorInteraction.ahk',
        'lib\StrategyLab\MapLibrary.ahk',
        'lib\StrategyLab\LabAutoMapCapture.ahk',
        'lib\StrategyLab\LabFootprintGeometry.ahk',
        'lib\StrategyLab\LabEditorStability.ahk',
        'lib\StrategyLab\LabStatsTab.ahk',
        'lib\StrategyLab\LabSafety.ahk',
        'lib\StrategyLab\LabStrategyValidation.ahk',
        'lib\StrategyLab\LabTelemetry.ahk',
        'lib\StrategyLab\LabRewardCatalog.ahk',
        'lib\StrategyLab\LabRewardTracker.ahk',
        'lib\StrategyLab\LabRemoteGate.ahk',
        'submacros\lab_tower_assets.ps1',
        'submacros\lab_fingerprint.ps1',
        'submacros\lab_discord_worker.ps1',
        'submacros\lab_remote_settings.ps1'
    )

    foreach ($relative in $required) {
        $target = Join-Path $root $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        [IO.File]::WriteAllText($target,'; fixture',(New-Object Text.UTF8Encoding($false)))
    }

    $preflightTarget = Join-Path $root 'submacros\lab_preflight.ps1'
    Copy-Item -LiteralPath $preflightSource -Destination $preflightTarget -Force

    # This fixture mirrors the real Ultimate Macro baseline ordering supplied in the
    # clean package. There is deliberately NO LoadGame() call inside RunStrategy().
    # Start from a legacy 0.4.2 CheckTheMapF hook so migration is also exercised.
    $fixture = @'
#Requires AutoHotkey v2.0

StartStrategy(*) {
    if !IsSet(MainGui) or !MainGui
        return

    v := MainGui.Submit(false)
}

RunStrategy(stratFile := "", skipRestart := false) {
    switched := false

    if (!switched) {
        if (!skipRestart) {
            CheckRestart()
        } else {
            CloseRoblox()
            RunRoblox()
            JoinGame()
        }
    }

    if (readyX = 0 && readyY = 0) {
        waitReady()
    }

    if (!IsRestarting) {
        if (!InArray(SpecialMaps, gamemap)) {
            AlignCamera()
        }
        CheckTheMapF()
        ; <StrategyLabAutoMapCapture>
        try LabMapAutoCaptureIfMissing(gamemap)
        ; </StrategyLabAutoMapCapture>
    }

    activateTimescale()
    ClickReady()
    PlayStrategy()
}

PlayStrategy() {
    i := 1
    while (i <= RecordedSteps.Length) {
        step := RecordedSteps[i]
        i += 1
    }
}

SpawnTower(X, Y, slotNumber, towerID) {
    currentSlot := slotNumber
    return currentSlot
}
'@
    $main = Join-Path $root 'Main_Lab.ahk'
    [IO.File]::WriteAllText($main,$fixture,(New-Object Text.UTF8Encoding($false)))

    foreach ($pass in 1..2) {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $preflightTarget -InstallDir $root
        if ($LASTEXITCODE -ne 0) {
            $preflightLog = Join-Path $env:APPDATA 'Ultimate_Macro\StrategyEditor\preflight.log'
            if (Test-Path -LiteralPath $preflightLog) {
                Write-Host '----- preflight.log -----' -ForegroundColor Yellow
                Get-Content -LiteralPath $preflightLog | Select-Object -Last 80 | ForEach-Object { Write-Host $_ }
                Write-Host '-------------------------' -ForegroundColor Yellow
            }
            throw "preflight test pass $pass failed with exit code $LASTEXITCODE"
        }
    }

    $patched = [IO.File]::ReadAllText($main)
    $checks = @(
        '; <StrategyLabMainGuiGuard>',
        'try labMainHwnd := MainGui.Hwnd',
        'DllCall("user32\IsWindow", "Ptr", labMainHwnd, "Int")',
        '; <StrategyLabAutoMapCapture>',
        'try LabMapAutoCaptureAligned()',
        '; <StrategyLabRemoteBoundary>'
    )
    foreach ($needle in $checks) {
        if (!$patched.Contains($needle)) {
            throw "patched Main_Lab is missing: $needle"
        }
    }

    if ($patched.Contains('LabMapAutoCaptureIfMissing(gamemap)')) {
        throw 'legacy CheckTheMapF/lobby capture call remained after migration'
    }
    if ($patched.Contains('try LabMapAutoCaptureCurrent()')) {
        throw 'legacy SpawnTower deferred capture remained after migration'
    }

    $alignPos = $patched.IndexOf('AlignCamera()')
    $checkMapPos = $patched.IndexOf('CheckTheMapF()')
    $capturePos = $patched.IndexOf('try LabMapAutoCaptureAligned()')
    $timescalePos = $patched.IndexOf('activateTimescale()')
    $readyPos = $patched.IndexOf('ClickReady()')
    $playPos = $patched.IndexOf('PlayStrategy()')
    $firstStepPos = $patched.IndexOf('i := 1')

    if ($alignPos -lt 0 -or $checkMapPos -le $alignPos) {
        throw 'fixture no longer mirrors AlignCamera -> CheckTheMapF ordering'
    }
    if ($capturePos -le $checkMapPos) {
        throw 'automatic capture does not occur after camera/map verification'
    }
    if ($timescalePos -lt 0 -or $capturePos -ge $timescalePos) {
        throw 'automatic capture is not immediately before activateTimescale'
    }
    if ($readyPos -lt 0 -or $capturePos -ge $readyPos) {
        throw 'automatic capture does not occur before ClickReady'
    }
    if ($playPos -lt 0 -or $capturePos -ge $playPos) {
        throw 'automatic capture does not occur before PlayStrategy'
    }
    if ($firstStepPos -lt 0 -or $capturePos -ge $firstStepPos) {
        throw 'automatic capture does not occur before RecordedSteps begin'
    }

    foreach ($marker in @('; <StrategyLabMainGuiGuard>','; <StrategyLabAutoMapCapture>','; <StrategyLabRemoteBoundary>')) {
        $count = ([regex]::Matches($patched,[regex]::Escape($marker))).Count
        if ($count -ne 1) {
            throw "expected one $marker marker after two passes, found $count"
        }
    }

    Write-Host 'PASS: preflight uses the real pre-activateTimescale RunStrategy boundary and keeps all hooks idempotent.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
