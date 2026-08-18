@echo off
setlocal
cd /d "%~dp0"

if exist "submacros\lab_preflight.ps1" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "submacros\lab_preflight.ps1" -InstallDir "%~dp0"
  if errorlevel 1 (
    echo.
    echo Strategy Lab preflight detected a problem it could not safely repair.
    echo See %%APPDATA%%\Ultimate_Macro\StrategyEditor\preflight.log for details.
    pause
    exit /b 1
  )
)

if not exist "submacros\AutoHotkey64.exe" (
  echo Missing bundled AutoHotkey64.exe
  pause
  exit /b 1
)

start "" "submacros\AutoHotkey64.exe" "Main_Lab.ahk"
endlocal
