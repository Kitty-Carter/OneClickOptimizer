@echo off
if not exist "%~dp0bin\oco-clash-monitor.exe" (
  echo Native binary missing. Download the standalone Clash release ZIP.
  pause
  exit /b 2
)
"%~dp0bin\oco-clash-monitor.exe" --gui --lite
set "rc=%errorlevel%"
if not "%rc%"=="0" pause
exit /b %rc%
