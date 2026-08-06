@echo off
REM === DOUBLE-CLICK TO UNLOCK TABLET (PARENT MODE) ===
set PATH=%~dp0platform-tools;%PATH%

echo.
echo ====================================================
echo   ACTIVATING PARENT MODE (UNLOCKING TABLET)
echo ====================================================
echo.

adb.exe shell "echo true > /sdcard/Kiosk/parent_mode.txt; settings put secure status_bar_hidden 0; settings put secure navbar_hidden 0; settings put secure home_key_disabled 0; settings put secure back_key_disabled 0; settings put global power_menu_disabled 0; settings put global policy_control none; am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS"

echo.
echo [+] SUCCESS! Tablet is now UNLOCKED for Parent Mode.
echo     Full Android navigation bar and settings are available on the tablet.
echo.
pause
