@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ClashOptimizer.ps1" -Action Check
set "rc=%errorlevel%"
pause
exit /b %rc%
