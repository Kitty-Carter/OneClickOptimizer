@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ClashOptimizer.ps1" -RequirePackage
set "rc=%errorlevel%"
if not "%rc%"=="0" pause
exit /b %rc%
