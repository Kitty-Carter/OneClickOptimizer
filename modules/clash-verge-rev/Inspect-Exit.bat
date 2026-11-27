@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnose-Clash.ps1" -ExitPrompt
set "rc=%errorlevel%"
pause
exit /b %rc%
