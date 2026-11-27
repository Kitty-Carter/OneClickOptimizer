@echo off
call "%~dp0Clash-OneClick-Config.bat" --check
exit /b %ERRORLEVEL%
