@echo off
setlocal
chcp 65001 >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0OneClickOptimizer.ps1"
set "RC=%ERRORLEVEL%"
echo Exit code: %RC% (0=confirmed, 1=failed/cancelled, 2=partial)
pause
exit /b %RC%
