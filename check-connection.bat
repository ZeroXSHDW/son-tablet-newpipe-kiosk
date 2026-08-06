@echo off
REM === Tablet connection checker ===
set PATH=%~dp0platform-tools;%PATH%
echo Checking for tablet configuration...
powershell -ExecutionPolicy Bypass -File "%~dp0configure-tablet.ps1" -CheckOnly
echo.
pause

