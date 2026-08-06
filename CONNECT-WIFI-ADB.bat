@echo off
cd /d "%~dp0"
echo ====================================================
echo   CONNECT SON TABLET VIA WI-FI ADB
echo ====================================================
echo.
echo If first time: plug USB, enable USB debugging, accept prompt.
echo Then this script enables tcpip 5555 and reconnects over Wi-Fi.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0DEPLOY-WIFI-ADB.ps1" %*
pause
