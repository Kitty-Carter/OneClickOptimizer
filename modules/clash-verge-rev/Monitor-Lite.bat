@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Monitor-Clash.ps1" -Lite
set "rc=%errorlevel%"
if not "%rc%"=="0" pause
exit /b %rc%
