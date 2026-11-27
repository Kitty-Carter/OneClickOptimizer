@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize-Clash.ps1" -RestorePrompt
set "rc=%errorlevel%"
pause
exit /b %rc%
