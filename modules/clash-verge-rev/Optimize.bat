@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ClashOptimizer.ps1" -RequirePackage -Action Optimize
set "rc=%errorlevel%"
pause
exit /b %rc%
