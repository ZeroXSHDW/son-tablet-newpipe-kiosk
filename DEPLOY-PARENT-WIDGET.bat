@echo off
REM ════════════════════════════════════════════════════════
REM  DEPLOY PARENT WIDGET — One-click setup
REM  Pushes toggle scripts and sets up home screen shortcut
REM  Run this ONCE from your PC while tablet is connected
REM ════════════════════════════════════════════════════════

set ADB=%~dp0platform-tools\adb.exe
set SCRIPTS=%~dp0termux_scripts
set TERMUX_HOME=/data/data/com.termux/files/home
set STAGING=/sdcard/Kiosk

echo.
echo ════════════════════════════════════════════════════
echo   PARENT WIDGET DEPLOYMENT
echo ════════════════════════════════════════════════════
echo.

REM ── Check ADB connection ─────────────────────────────────────────────────────
"%ADB%" devices | findstr /i "device" | findstr /v "List" >nul 2>&1
if errorlevel 1 (
    echo [!] No tablet detected. Please:
    echo     1. Connect tablet via USB
    echo     2. Enable USB Debugging
    echo     3. Tap "Allow" on tablet screen
    echo.
    pause
    exit /b 1
)
echo [✓] Tablet connected

REM ── Push scripts to staging area ────────────────────────────────────────────
echo [*] Pushing scripts to tablet...
"%ADB%" shell mkdir -p %STAGING% >nul 2>&1
"%ADB%" push "%SCRIPTS%\parent_toggle_widget.sh" "%STAGING%/parent_toggle_widget.sh" >nul 2>&1
"%ADB%" push "%SCRIPTS%\setup_parent_widget.sh" "%STAGING%/setup_parent_widget.sh" >nul 2>&1
echo [✓] Scripts uploaded

REM ── Copy from staging into Termux home ──────────────────────────────────────
echo [*] Installing into Termux...
"%ADB%" shell "cp %STAGING%/parent_toggle_widget.sh %TERMUX_HOME%/parent_toggle_widget.sh; chmod +x %TERMUX_HOME%/parent_toggle_widget.sh"
"%ADB%" shell "cp %STAGING%/setup_parent_widget.sh %TERMUX_HOME%/setup_parent_widget.sh; chmod +x %TERMUX_HOME%/setup_parent_widget.sh"
echo [✓] Scripts in Termux home

REM ── Create shortcut directory ─────────────────────────────────────────────
echo [*] Creating Termux shortcuts directory...
"%ADB%" shell "mkdir -p %TERMUX_HOME%/.shortcuts; chmod 700 %TERMUX_HOME%/.shortcuts"
"%ADB%" shell "cp %TERMUX_HOME%/parent_toggle_widget.sh '%TERMUX_HOME%/.shortcuts/Parent Toggle.sh'; chmod 755 '%TERMUX_HOME%/.shortcuts/Parent Toggle.sh'"
echo [✓] Shortcut installed in ~/.shortcuts/

REM ── Install Termux:API (for graphical PIN dialog) ───────────────────────────
echo [*] Installing Termux:API (for PIN dialog popup)...
"%ADB%" shell "su -c 'pm list packages' 2>/dev/null | grep termux.api || termux-run-command 'pkg install -y termux-api'" >nul 2>&1
echo [i] (Termux:API install runs in background — may take a minute)

REM ── Check if Termux:Widget is installed ──────────────────────────────────────
"%ADB%" shell "pm list packages 2>/dev/null | grep com.termux.widget" | findstr /i "widget" >nul 2>&1
if errorlevel 1 (
    echo.
    echo ════════════════════════════════════════════════════
    echo  [!] Termux:Widget NOT installed — Action Required
    echo ════════════════════════════════════════════════════
    echo.
    echo  To get the home screen toggle button:
    echo.
    echo  Option A ^(Recommended^) — F-Droid:
    echo    Open browser on tablet and go to:
    echo    https://f-droid.org/packages/com.termux.widget
    echo.
    echo  Option B — If you have the APK file:
    echo    Copy termux-widget.apk to this folder and run:
    echo    platform-tools\adb.exe install termux-widget.apk
    echo.
) else (
    echo [✓] Termux:Widget is installed
)

REM ── Final instructions ────────────────────────────────────────────────────────
echo.
echo ════════════════════════════════════════════════════
echo   DONE! Follow these steps on the TABLET:
echo ════════════════════════════════════════════════════
echo.
echo  1. Long-press the HOME SCREEN (empty area)
echo  2. Tap WIDGETS
echo  3. Scroll to find "Termux:Widget"
echo  4. Drag it to your home screen
echo  5. Select "Parent Toggle" from the list
echo.
echo  That's it! One tap on the widget = PIN prompt = toggle.
echo.
echo  Set a private PIN during tablet setup.
echo  To change PIN ^(from tablet Termux^): echo 'NEWPIN' ^> ~/.kiosk_pin
echo.
pause
