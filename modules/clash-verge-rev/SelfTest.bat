@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SelfTest.ps1" -RequirePackage
set "rc=%errorlevel%"
pause
exit /b %rc%
