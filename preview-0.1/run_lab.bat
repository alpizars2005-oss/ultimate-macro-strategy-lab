@echo off
setlocal
cd /d "%~dp0"
if not exist "submacros\AutoHotkey64.exe" (
  echo Missing bundled AutoHotkey64.exe
  pause
  exit /b 1
)
start "" "submacros\AutoHotkey64.exe" "Main_Lab.ahk"
endlocal
