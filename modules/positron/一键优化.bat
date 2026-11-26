@echo off
setlocal
chcp 65001 >nul
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT=%~dp0Optimize-Positron.ps1"
if not exist "%SCRIPT%" (
  echo ERROR: Optimize-Positron.ps1 must be in the same folder as this BAT.
  pause
  exit /b 1
)
if not exist "%PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found.
  pause
  exit /b 1
)
echo Running built-in self-tests before modifying any settings...
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -SelfTest
if errorlevel 1 (
  echo Self-test failed. No Positron settings were modified.
  pause
  exit /b 1
)
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" echo Finished: all seven configuration goals were supported and verified.
if "%RC%"=="2" echo Partial: some settings were skipped. See the messages above.
if not "%RC%"=="0" if not "%RC%"=="2" echo Failed: review the error and backup path above.
pause
exit /b %RC%
