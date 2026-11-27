@echo off
call "%~dp0Clash-OneClick-Config.bat" --self-test
exit /b %ERRORLEVEL%
