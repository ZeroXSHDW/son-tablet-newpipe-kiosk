@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0GET-DEVICE-SERIAL.ps1" -Wait -Copy
echo.
pause
