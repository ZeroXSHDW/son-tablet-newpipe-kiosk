# PowerShell helper script to easily toggle Parent Mode (unlocking full tablet) or Child Mode (NewPipe Kiosk)
$ADB = Join-Path $PSScriptRoot "platform-tools\adb.exe"

if (-not (Test-Path $ADB)) {
    Write-Error "ADB executable not found at $ADB"
    exit 1
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "        PARENT / CHILD MODE TOGGLE UTILITY          " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

$modeFile = "/sdcard/Kiosk/parent_mode.txt"
$check = & $ADB shell "cat $modeFile 2>/dev/null"

if ($check -and $check.Trim() -eq "true") {
    Write-Host "Current Status: PARENT UNLOCKED MODE" -ForegroundColor Yellow
    Write-Host "Switching to: CHILD KIOSK MODE (NewPipe Only)..." -ForegroundColor Green
    & $ADB shell "rm $modeFile 2>/dev/null; am start -n org.schabi.newpipe/.MainActivity"
    Write-Host "[+] Child Kiosk Mode Enabled!" -ForegroundColor Green
} else {
    Write-Host "Current Status: CHILD KIOSK MODE" -ForegroundColor Green
    Write-Host "Switching to: PARENT UNLOCKED MODE..." -ForegroundColor Yellow
    & $ADB shell "echo true > $modeFile; settings put secure status_bar_hidden 0; settings put secure navbar_hidden 0; am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS"
    Write-Host "[+] Parent Unlocked Mode Enabled! System UI unlocked." -ForegroundColor Yellow
}

Write-Host ""
