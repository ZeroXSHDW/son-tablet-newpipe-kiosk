#Requires -Version 5.1
<#
.SYNOPSIS
  Pull kiosk health from son's tablet over ADB (USB or Wi-Fi).
#>
param(
    [string]$TabletIp = "",
    [int]$AdbPort = 5555,
    [string]$DeviceSerial = ""
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ADB = Join-Path $Root "platform-tools\adb.exe"
$StateFile = Join-Path $Root "tablet-wifi-adb.state.json"
$script:Serial = ""

function Select-DeviceSerial {
    if ($DeviceSerial) {
        $explicit = @(& $ADB devices | Where-Object { $_ -match ("^" + [regex]::Escape($DeviceSerial) + "\s+device$") })
        if ($explicit.Count -eq 1) { return $DeviceSerial }
        Write-Host "Requested -DeviceSerial '$DeviceSerial' is not an authorized connected device." -ForegroundColor Red
        return $null
    }
    $lines = & $ADB devices | Where-Object { $_ -match '\tdevice$' }
    $serials = @($lines | ForEach-Object { ($_ -split '\s+')[0] })
    if ($serials.Count -eq 0) { return $null }
    if ($serials.Count -eq 1) { return $serials[0] }
    $usb = @($serials | Where-Object { $_ -notmatch ':' })
    if ($usb.Count -eq 1) { return $usb[0] }
    Write-Host "Multiple authorized ADB devices found. Re-run with -DeviceSerial <serial>." -ForegroundColor Red
    Write-Host ($serials -join ', ') -ForegroundColor Yellow
    return $null
}

function Connect-IfNeeded {
    $script:Serial = Select-DeviceSerial
    if ($script:Serial) { return $true }

    if ($TabletIp) {
        & $ADB connect "${TabletIp}:$AdbPort" | Out-Null
    } elseif (Test-Path $StateFile) {
        $s = Get-Content $StateFile -Raw | ConvertFrom-Json
        if ($s.tablet_ip) {
            & $ADB connect "$($s.tablet_ip):$($s.adb_port)" | Out-Null
        }
    }
    Start-Sleep -Seconds 1
    $script:Serial = Select-DeviceSerial
    return [bool]$script:Serial
}

Write-Host "=== TABLET KIOSK HEALTH ===" -ForegroundColor Cyan
$failures = @()

if (-not (Connect-IfNeeded)) {
    Write-Host "No ADB device. Plug USB or: .\DEPLOY-WIFI-ADB.ps1" -ForegroundColor Red
    exit 2
}

$adbS = @('-s', $script:Serial)
$model = (& $ADB @adbS shell getprop ro.product.model).Trim()
$bat = @(& $ADB @adbS shell dumpsys battery 2>$null | Select-String 'level:' | Select-Object -First 1)
$batteryText = if ($bat.Count -gt 0) { $bat[0].Line.Trim() } else { 'unknown' }
Write-Host "Model   : $model"
Write-Host "Battery : $batteryText"
Write-Host ""

Write-Host "--- Core processes ---" -ForegroundColor Yellow
$processSnapshot = @(& $ADB @adbS shell "run-as com.termux ps -ef 2>/dev/null")
function Test-TermuxScriptProcess {
    param([string]$Name)
    $pattern = [regex]::Escape("bash /data/data/com.termux/files/home/$Name.sh")
    return @($processSnapshot | Where-Object { $_ -match $pattern }).Count
}
foreach ($p in @('newpipe_24x7','fullscreen_enforcer','volume_guard','wallpaper_live','wifi_keepalive','download_scheduler','service_monitor')) {
    $count = Test-TermuxScriptProcess -Name $p
    $up = $count -eq 1
    $status = if ($up) { 'UP' } elseif ($count -gt 1) { "DUPLICATE ($count)" } else { 'DOWN' }
    $color = if ($up) { 'Green' } else { 'Red' }
    Write-Host ("  {0,-22} {1}" -f $p, $status) -ForegroundColor $color
    if ($count -eq 0) { $failures += "core process down: $p" }
    if ($count -gt 1) { $failures += "duplicate core processes: $p ($count)" }
}
$runnerCount = @($processSnapshot | Where-Object {
    $_ -match 'bash -c /data/data/com\.termux/files/home/boot_orchestrator_v2_integrated\.sh; exec /data/data/com\.termux/files/usr/bin/sleep infinity'
}).Count
Write-Host ("  {0,-22} {1}" -f 'RUN_COMMAND owner', $(if ($runnerCount -eq 1) { 'UP (single)' } elseif ($runnerCount -gt 1) { "DUPLICATE ($runnerCount)" } else { 'DOWN' })) -ForegroundColor $(if ($runnerCount -eq 1) { 'Green' } else { 'Red' })
if ($runnerCount -eq 0) { $failures += 'Kiosk Booter RUN_COMMAND owner is missing' }
if ($runnerCount -gt 1) { $failures += "duplicate Kiosk Booter RUN_COMMAND owners: $runnerCount" }

Write-Host ""
Write-Host "--- NewPipe ---" -ForegroundColor Yellow
$np = & $ADB @adbS shell "pidof org.schabi.newpipe >/dev/null && echo RUNNING || echo STOPPED"
Write-Host "  process: $($np.Trim())"
if (($np -join " ").Trim() -ne 'RUNNING') { $failures += 'NewPipe process is not running' }
$fg = & $ADB @adbS shell "dumpsys window 2>/dev/null | grep -E mCurrentFocus | head -1"
Write-Host "  focus  : $($fg.Trim())"
$focusText = ($fg -join " ")
$usingNewPipe = $focusText -match 'org\.schabi\.newpipe/(?:\.MainActivity|org\.schabi\.newpipe\.MainActivity)'
$usingVlc = $focusText -match 'org\.videolan\.vlc/'
if (-not $usingNewPipe -and -not $usingVlc) {
    $failures += 'Neither NewPipe online nor VLC offline fallback is foreground'
}
if ($usingVlc) {
    $vlc = & $ADB @adbS shell "pidof org.videolan.vlc >/dev/null && echo RUNNING || echo STOPPED"
    Write-Host "  owner  : VLC offline fallback ($($vlc.Trim()))"
    if (($vlc -join " ").Trim() -ne 'RUNNING') { $failures += 'VLC is focused but its process is not running' }
} else {
    Write-Host "  owner  : NewPipe online"
}
$mediaSession = (& $ADB @adbS shell "dumpsys media_session 2>/dev/null") -join "`n"
$mediaPackage = if ($usingVlc) { 'org.videolan.vlc' } else { 'org.schabi.newpipe' }
$mediaPlaying = ($mediaSession -match [regex]::Escape($mediaPackage)) -and
    ($mediaSession -match 'state=PlaybackState \{state=(3|6)')
Write-Host ("  playback: " + $(if ($mediaPlaying) { 'PLAYING' } else { 'NOT PLAYING' })) -ForegroundColor $(if ($mediaPlaying) { 'Green' } else { 'Red' })
if (-not $mediaPlaying) { $failures += "${mediaPackage} media session is not playing/buffering" }

Write-Host "--- Fullscreen / input lock ---" -ForegroundColor Yellow
$displayText = (& $ADB @adbS shell "wm size 2>/dev/null") -join "`n"
$displayMatch = [regex]::Match($displayText, 'Physical size:\s*(\d+)x(\d+)')
$displayWidth = 0
$displayHeight = 0
if ($displayMatch.Success) {
    $displayWidth = [int]$displayMatch.Groups[1].Value
    $displayHeight = [int]$displayMatch.Groups[2].Value
}
$uiDump = (& $ADB @adbS shell "uiautomator dump --compressed /sdcard/health_check.xml >/dev/null 2>&1; cat /sdcard/health_check.xml" 2>$null) -join ''
$playerPattern = if ($usingVlc) {
    'org\.videolan\.vlc:id/player_root[^>]*bounds="(\[[^"]+\])"'
} else {
    'org\.schabi\.newpipe:id/player_placeholder[^>]*bounds="(\[[^"]+\])"'
}
$playerMatch = [regex]::Match($uiDump, $playerPattern)
$playerBounds = if ($playerMatch.Success) { $playerMatch.Groups[1].Value } else { '' }
if (-not $usingVlc -and -not $playerMatch.Success) {
    # NewPipe's minimized tablet player is exposed as fragment_player_holder;
    # its embedded detail/queue layout can still span the full display, so use
    # detail_main_content as the measured player area when it is narrower.
    $holderMatch = [regex]::Match($uiDump,
        'org\.schabi\.newpipe:id/fragment_player_holder[^>]*bounds="(\[[^"]+\])"')
    $detailMatch = [regex]::Match($uiDump,
        'org\.schabi\.newpipe:id/detail_main_content[^>]*bounds="(\[[^"]+\])"')
    if ($holderMatch.Success) {
        $playerBounds = $holderMatch.Groups[1].Value
        if ($detailMatch.Success) {
            $detailBounds = $detailMatch.Groups[1].Value
            $detailParts = [regex]::Match($detailBounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
            if ($detailParts.Success -and
                ([int]$detailParts.Groups[3].Value - [int]$detailParts.Groups[1].Value) -lt ($displayWidth - 32)) {
                $playerBounds = $detailBounds
            }
        }
    }
}
Write-Host "  player : $playerBounds"
$boundsMatch = [regex]::Match($playerBounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
if (-not $boundsMatch.Success -or $displayWidth -le 0 -or $displayHeight -le 0) {
    $failures += 'Fullscreen player bounds could not be verified'
} else {
    $left = [int]$boundsMatch.Groups[1].Value
    $top = [int]$boundsMatch.Groups[2].Value
    $right = [int]$boundsMatch.Groups[3].Value
    $bottom = [int]$boundsMatch.Groups[4].Value
    if ($left -gt 32 -or $top -gt 48 -or ($right - $left) -lt ($displayWidth - 32) -or ($bottom - $top) -lt ($displayHeight - 80)) {
        $failures += "NewPipe player is not fullscreen: $playerBounds on ${displayWidth}x${displayHeight}"
    }
}
$rotation = ((& $ADB @adbS shell "settings get system user_rotation") -join '').Trim()
Write-Host "  rotation: $rotation"
if ($rotation -ne '0') { $failures += "rotation is $rotation instead of 0" }
$accessibility = (& $ADB @adbS shell "dumpsys accessibility 2>/dev/null") -join "`n"
if ($accessibility -match 'Enabled services:.*com\.android\.kioskbooter/com\.android\.kioskbooter\.InputBlockerService' -or
    $accessibility -match 'com\.android\.kioskbooter/com\.android\.kioskbooter\.InputBlockerService') {
    Write-Host "  input lock: ENABLED" -ForegroundColor Green
} else {
    Write-Host "  input lock: DISABLED" -ForegroundColor Red
    $failures += 'Kiosk Booter accessibility service is not enabled'
}

Write-Host ""
Write-Host "--- Playlist / health files ---" -ForegroundColor Yellow
& $ADB @adbS shell "echo 'home_last_url:'; run-as com.termux cat /data/data/com.termux/files/home/Kiosk/last_played_url.txt 2>/dev/null; echo; echo 'home_sleep_channel:'; run-as com.termux cat /data/data/com.termux/files/home/Kiosk/last_channel_url.txt 2>/dev/null; echo; echo 'home_health:'; run-as com.termux cat /data/data/com.termux/files/home/Kiosk/health_24x7.json 2>/dev/null; echo; echo 'services:'; run-as com.termux cat /data/data/com.termux/files/home/Kiosk/service_status.txt 2>/dev/null || cat /sdcard/Kiosk/service_status.txt 2>/dev/null; echo; echo 'wifi:'; cat /sdcard/Kiosk/wifi_status.txt 2>/dev/null; echo; echo 'parent:'; cat /sdcard/Kiosk/parent_mode.txt 2>/dev/null || echo child"
Write-Host "--- Termux authoritative health ---" -ForegroundColor Yellow
& $ADB @adbS shell "run-as com.termux sh -c 'echo home_health:; cat /data/data/com.termux/files/home/Kiosk/health_24x7.json 2>/dev/null; echo; echo home_sleep_channel:; cat /data/data/com.termux/files/home/Kiosk/last_channel_url.txt 2>/dev/null; echo; echo home_last_url:; cat /data/data/com.termux/files/home/Kiosk/last_played_url.txt 2>/dev/null'"
$parentMode = (& $ADB @adbS shell "cat /sdcard/Kiosk/parent_mode.txt 2>/dev/null || echo child").Trim()
if ($parentMode -ne 'child') { $failures += "parent mode is $parentMode instead of child" }

Write-Host ""
Write-Host "--- Volume (music stream) ---" -ForegroundColor Yellow
& $ADB @adbS shell "cmd media_session volume --stream 3 --get 2>/dev/null || media volume --stream 3 --get 2>/dev/null" | Select-Object -First 5

Write-Host ""
Write-Host "--- Display ---" -ForegroundColor Yellow
$phase = (& $ADB @adbS shell "run-as com.termux sh -c '. /data/data/com.termux/files/home/kiosk_config.sh; kiosk_current_phase'" 2>$null).Trim()
$brightness = switch ($phase) {
    "MORNING" { 160 }
    "LEARNING" { 180 }
    "RELAXING" { 120 }
    "BEDTIME" { 40 }
    "NIGHT" { 25 }
    default { "unknown" }
}
Write-Host "  phase   : $phase (target $brightness/255)"
& $ADB @adbS shell "settings get system screen_brightness; dumpsys display 2>/dev/null | grep -E 'Display Brightness=|mBrightnessState=' | head -2"

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "HEALTH: FAIL ($($failures.Count) gate(s))" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "HEALTH: PASS (all runtime gates)" -ForegroundColor Green
Write-Host "Done." -ForegroundColor Green
exit 0
