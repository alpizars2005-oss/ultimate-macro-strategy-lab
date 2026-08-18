@echo off
setlocal
cd /d "%~dp0"

if exist "submacros\lab_preflight.ps1" (
  rem %~dp0 ends with a backslash. After cd /d, %CD% is the same directory
  rem without the trailing-slash quoting ambiguity that older launchers hit.
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "submacros\lab_preflight.ps1" -InstallDir "%CD%"
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

rem Parse the real Main_Lab plus every included Strategy Lab module in a temporary,
rem immediate-exit copy before opening the GUI. This catches syntax, include and known
rem function-arity errors without running any macro/gameplay code.
if exist "submacros\lab_syntax_probe.ps1" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "submacros\lab_syntax_probe.ps1" -InstallDir "%CD%" -Quiet
  if errorlevel 1 (
    echo.
    echo Strategy Lab did not start because its integrated syntax check failed.
    echo Your macro was NOT executed.
    echo See %%APPDATA%%\Ultimate_Macro\StrategyEditor\syntax-probe.log for the exact error.
    echo Run the Strategy Lab repair tool before trying again.
    pause
    exit /b 1
  )
)

start "" "submacros\AutoHotkey64.exe" "Main_Lab.ahk"
endlocal
