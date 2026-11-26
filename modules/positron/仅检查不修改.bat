@echo off
setlocal
chcp 65001 >nul
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT=%~dp0Optimize-Positron.ps1"
if not exist "%SCRIPT%" (
  echo ERROR: Optimize-Positron.ps1 must be in the same folder as this BAT.
  pause
  exit /b 1
)
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -CheckOnly
set "RC=%ERRORLEVEL%"
echo Check-only mode: no Positron settings were modified.
pause
exit /b %RC%
