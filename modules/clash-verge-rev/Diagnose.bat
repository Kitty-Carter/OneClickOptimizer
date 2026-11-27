@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnose-Clash.ps1" -Rounds 2
set "rc=%errorlevel%"
pause
exit /b %rc%
