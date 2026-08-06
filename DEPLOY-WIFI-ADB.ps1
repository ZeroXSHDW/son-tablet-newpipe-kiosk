#Requires -Version 5.1
<#
.SYNOPSIS
  Configure son's tablet for Wi‑Fi ADB + supervised Termux/NewPipe daytime autoplay.

.DESCRIPTION
  1) Connect via USB ADB (first time) OR reconnect known Wi‑Fi ADB
  2) Enable wireless debugging (tcpip 5555) and switch to Wi‑Fi ADB
  3) Push Termux scripts, playlist (Ms Rachel / Tractor Ted / Teletubbies /
     edubuzzkids / WildBrain), and channel config
  4) Install Kiosk Booter as the single boot-to-Termux command owner
  5) Volume by time is enforced by volume_guard.sh (12/15 day, 3/15 sleep)

.PARAMETER TabletIp
  Optional fixed tablet IP. If omitted, discovers via USB then uses wlan0 IP.

.PARAMETER CheckOnly
  Only verify connection and current state; do not push or change settings.

.PARAMETER SkipUsb
  Only try Wi‑Fi (use with -TabletIp or saved state).

.PARAMETER ForceUsb
  Use the authorized USB serial for the entire deployment and do not switch
  the deployment transport to Wi‑Fi ADB.

.PARAMETER DeviceSerial
  Explicit ADB serial to use when more than one authorized device is present.
#>
param(
    [string]$TabletIp = "",
    [switch]$CheckOnly,
    [switch]$SkipUsb,
    [switch]$ForceUsb,
    [int]$AdbPort = 5555,
    [string]$DeviceSerial = ""
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ADB = Join-Path $Root "platform-tools\adb.exe"
$StateFile = Join-Path $Root "tablet-wifi-adb.state.json"
$ScriptsDir = Join-Path $Root "termux_scripts"
$TermuxHome = "/data/data/com.termux/files/home"
$KioskRemote = "/sdcard/Kiosk"

function Write-Banner($msg) {
    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    & $ADB @Args
}

function Get-AuthorizedSerials {
    $out = & $ADB devices
    $lines = $out -split "`r?`n" | Where-Object { $_ -match '\tdevice$' }
    $serials = @()
    foreach ($l in $lines) {
        $serials += ($l -split '\s+')[0]
    }
    return $serials
}

function Save-WifiState($ip, $port) {
    $obj = @{
        tablet_ip   = $ip
        adb_port    = $port
        updated     = (Get-Date).ToString("o")
        notes       = "Wi-Fi ADB for son's tablet kiosk"
    } | ConvertTo-Json
    Set-Content -Path $StateFile -Value $obj -Encoding UTF8
    Write-Host "[+] Saved Wi-Fi ADB state -> $StateFile ($ip`:$port)" -ForegroundColor Green
}

function Load-WifiState {
    if (Test-Path $StateFile) {
        try {
            return Get-Content $StateFile -Raw | ConvertFrom-Json
        } catch { return $null }
    }
    return $null
}

function Get-DeviceIp {
    param([string]$Serial = "")
    $prefix = @()
    if ($Serial) { $prefix = @("-s", $Serial) }

    # Prefer wlan0
    $ipLine = (& $ADB @prefix shell "ip -f inet addr show wlan0 2>/dev/null | grep 'inet '" 2>$null) -join "`n"
    if ($ipLine -match 'inet\s+(\d+\.\d+\.\d+\.\d+)') {
        return $Matches[1]
    }
    $ipLine = (& $ADB @prefix shell "ip route get 8.8.8.8 2>/dev/null" 2>$null) -join "`n"
    if ($ipLine -match 'src\s+(\d+\.\d+\.\d+\.\d+)') {
        return $Matches[1]
    }
    return $null
}

function Ensure-Connected {
    param([switch]$CheckOnly)
    Write-Banner "ADB CONNECTION (USB then Wi-Fi)"

    if (-not (Test-Path $ADB)) {
        Write-Error "adb not found at $ADB"
        exit 1
    }

    & $ADB start-server | Out-Null

    # Try saved Wi-Fi first
    $saved = Load-WifiState
    if ($TabletIp) {
        Write-Host "Connecting to -TabletIp $TabletIp`:$AdbPort ..." -ForegroundColor Yellow
        & $ADB connect "${TabletIp}:$AdbPort" | Write-Host
    } elseif ($saved -and $saved.tablet_ip) {
        $p = if ($saved.adb_port) { $saved.adb_port } else { $AdbPort }
        Write-Host "Reconnecting saved Wi-Fi ADB $($saved.tablet_ip):$p ..." -ForegroundColor Yellow
        & $ADB connect "$($saved.tablet_ip):$p" | Write-Host
    }

    $serials = @(Get-AuthorizedSerials)
    if ($serials.Count -eq 0 -and -not $SkipUsb) {
        Write-Host ""
        Write-Host "No authorized device yet. Plug tablet USB and enable USB debugging." -ForegroundColor Yellow
        Write-Host "Waiting up to 120s for USB authorization..." -ForegroundColor Yellow
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            $serials = @(Get-AuthorizedSerials)
            if ($serials.Count -gt 0) { break }
            $all = & $ADB devices
            if ($all -match "unauthorized") {
                Write-Host '[!]  Unauthorized - tap ALLOW on tablet (Always allow from this computer)' -ForegroundColor Red
            }
            Start-Sleep -Seconds 3
        }
    }

    $serials = @(Get-AuthorizedSerials)
    if ($serials.Count -eq 0) {
        Write-Host ""
        Write-Host '[!]  NO ADB DEVICE. Steps:' -ForegroundColor Red
        Write-Host "  1. Same Wi-Fi as PC (PC is on your LAN)" -ForegroundColor White
        Write-Host "  2. USB: Developer options > USB debugging ON, accept prompt" -ForegroundColor White
        Write-Host "  3. Re-run: .\DEPLOY-WIFI-ADB.ps1" -ForegroundColor White
        Write-Host "  4. Or with known IP: .\DEPLOY-WIFI-ADB.ps1 -TabletIp 192.168.1.XX" -ForegroundColor White
        exit 2
    }

    Write-Host "[+] Authorized device(s): $($serials -join ', ')" -ForegroundColor Green

    if ($DeviceSerial -and $serials -notcontains $DeviceSerial) {
        Write-Host "[!] Requested -DeviceSerial '$DeviceSerial' is not an authorized connected device." -ForegroundColor Red
        exit 2
    }

    # Prefer USB serial for enable-wifi, else use first
    $usbSerials = @($serials | Where-Object { $_ -notmatch ':' })
    $usbSerial = if ($DeviceSerial -and $DeviceSerial -notmatch ':') {
        $DeviceSerial
    } elseif ($usbSerials.Count -eq 1) {
        $usbSerials[0]
    } elseif ($usbSerials.Count -gt 1) {
        Write-Host "[!] Multiple USB devices are authorized. Use -DeviceSerial <serial>." -ForegroundColor Red
        exit 2
    } else {
        $null
    }
    $serial = if ($DeviceSerial) { $DeviceSerial } elseif ($usbSerial) { $usbSerial } else { $serials[0] }

    # An explicit Wi-Fi serial is already the requested transport. Do not
    # silently replace it with an unrelated authorized USB device.
    if ($DeviceSerial -and $DeviceSerial -match ':') {
        return $DeviceSerial
    }

    if ($ForceUsb -and -not $usbSerial) {
        Write-Host "[!] -ForceUsb requires an authorized USB device." -ForegroundColor Red
        exit 2
    }

    # Enable wireless ADB if we have USB. CheckOnly deliberately stops before
    # tcpip/settings changes so it really is a read-only status operation.
    if ($usbSerial) {
        if ($CheckOnly) {
            return $usbSerial
        }
        if ($ForceUsb) {
            Write-Host "Using USB serial for the entire deployment (-ForceUsb)." -ForegroundColor Yellow
            return $usbSerial
        }
        Write-Host "Enabling wireless ADB (tcpip $AdbPort) on USB device $usbSerial ..." -ForegroundColor Yellow
        & $ADB -s $usbSerial tcpip $AdbPort | Write-Host
        Start-Sleep -Seconds 2
        $ip = Get-DeviceIp -Serial $usbSerial
        if (-not $ip) {
            Write-Host '[!]  Could not read tablet Wi-Fi IP. Is Wi-Fi on?' -ForegroundColor Red
            Write-Host "    Continuing on USB only for this session." -ForegroundColor Yellow
            return $usbSerial
        }
        Write-Host "Tablet Wi-Fi IP: $ip" -ForegroundColor Green
        & $ADB connect "${ip}:$AdbPort" | Write-Host
        Start-Sleep -Seconds 1
        $wifiSerial = "${ip}:$AdbPort"
        $check = & $ADB -s $wifiSerial get-state 2>$null
        if ($check -match "device") {
            Save-WifiState $ip $AdbPort
            Write-Host "[+] Wi-Fi ADB active: $wifiSerial (you may unplug USB)" -ForegroundColor Green
            return $wifiSerial
        }
        Write-Host '[!]  Wi-Fi connect failed; staying on USB $usbSerial' -ForegroundColor Yellow
        return $usbSerial
    }

    # Already Wi-Fi only
    if ($serial -match '^([\d.]+):(\d+)$') {
        Save-WifiState $Matches[1] ([int]$Matches[2])
    }
    return $serial
}

function Push-KioskFiles {
    param([string]$Serial)

    Write-Banner "PUSH SCRIPTS + PLAYLIST (via run-as com.termux)"
    $adbS = @("-s", $Serial)

    # Android blocks adb push into Termux private data — stage tar in /data/local/tmp and extract with run-as
    & $ADB @adbS shell "mkdir -p $KioskRemote" | Out-Null

    $stage = Join-Path $env:TEMP "kiosk_stage_deploy"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage | Out-Null

    $files = @(
        "boot_orchestrator_v2_integrated.sh", "start.sh", "kiosk_config.sh",
        "daemon_lib.sh", "volume_guard.sh", "fullscreen_enforcer.sh",
        "newpipe_24x7.sh", "wallpaper_live.sh",
        "wifi_keepalive.sh",
        "playlist_lib.sh",
        "download_scheduler.sh", "download_videos.py",
        "ParentToggle.sh", "toggle_parent.sh", "service_monitor.sh",
        "restart_kiosk_stack.sh", "test_suite.sh"
    )
    foreach ($f in $files) {
        $local = Join-Path $ScriptsDir $f
        if (Test-Path $local) {
            Copy-Item $local (Join-Path $stage $f)
            Write-Host "  stage $f" -ForegroundColor Gray
        }
    }

    foreach ($dirName in @("Kiosk", "kioskbooter", "calmwallpaper")) {
        $sourceDir = Join-Path $ScriptsDir $dirName
        if (Test-Path $sourceDir) {
            Copy-Item -LiteralPath $sourceDir -Destination (Join-Path $stage $dirName) -Recurse
            Write-Host "  stage $dirName/" -ForegroundColor Gray
        }
    }

    $bootDir = Join-Path $stage "dot_termux_boot"
    New-Item -ItemType Directory -Path $bootDir | Out-Null
    $bootLauncher = @'
#!/data/data/com.termux/files/usr/bin/bash
# Kiosk Booter is the sole kiosk startup owner through Termux RUN_COMMAND.
# Compatibility entrypoint only; never launch a second daemon stack here.
exit 0
'@
    [System.IO.File]::WriteAllText((Join-Path $bootDir "start.sh"), $bootLauncher)

    $tarFile = Join-Path $env:TEMP "kiosk_scripts.tar"
    Push-Location $stage
    tar -cf $tarFile *
    Pop-Location
    & $ADB @adbS push $tarFile /data/local/tmp/kiosk_scripts.tar | Out-Null

    $extract = @'
cd files/home
tar -xf /data/local/tmp/kiosk_scripts.tar
mkdir -p .termux/boot Kiosk
if [ -f dot_termux_boot/start.sh ]; then cp -f dot_termux_boot/start.sh .termux/boot/start.sh; rm -rf dot_termux_boot; fi
chmod 755 .termux/boot/start.sh *.sh 2>/dev/null || true
# Remove only the legacy kiosk-generated shell autostart hooks. Backups remain
# available under Kiosk/legacy_shell_profiles/.
mkdir -p Kiosk/legacy_shell_profiles
for f in .bashrc .profile .bash_profile; do
  if [ -f "$f" ] && grep -q "Kiosk Boot Orchestrator Trigger" "$f" 2>/dev/null; then
    cp -f "$f" "Kiosk/legacy_shell_profiles/${f}.bak"
    printf '# Interactive Termux shell; Kiosk Booter exclusively owns kiosk startup.\n' > "$f"
  fi
done
cp /sdcard/Kiosk/online_playlist.json Kiosk/ 2>/dev/null || true
echo EXTRACT_OK
ls -la newpipe_24x7.sh playlist_lib.sh boot_orchestrator_v2_integrated.sh .termux/boot/start.sh
'@
    $extractPath = Join-Path $env:TEMP "kiosk_extract.sh"
    [System.IO.File]::WriteAllText($extractPath, ($extract -replace "`r`n", "`n"))
    & $ADB @adbS push $extractPath /data/local/tmp/kiosk_extract.sh | Out-Null
    & $ADB @adbS shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash /data/local/tmp/kiosk_extract.sh" | Write-Host

    $kioskSource = Join-Path $ScriptsDir "Kiosk"
    if (Test-Path $kioskSource) {
        & $ADB @adbS push "$kioskSource\." "$KioskRemote/" | Out-Null
        Write-Host "  [+] playlist, schedule, and wallpaper assets" -ForegroundColor Green
    }

    $helper = Join-Path $ScriptsDir "kioskhelper.jar"
    if (Test-Path $helper) {
        & $ADB @adbS push $helper /data/local/tmp/kioskhelper.jar | Out-Null
        Write-Host "  [+] kioskhelper.jar" -ForegroundColor Green
    }

    # Writable state files for Termux (sdcard often owned by media_rw)
    & $ADB @adbS shell "mkdir -p $KioskRemote; chmod 777 $KioskRemote; touch $KioskRemote/last_played_url.txt $KioskRemote/last_launch_epoch.txt $KioskRemote/health_24x7.json $KioskRemote/play_history.txt $KioskRemote/play_events.log; chmod 666 $KioskRemote/*.txt $KioskRemote/*.json $KioskRemote/*.log 2>/dev/null; rm -f $KioskRemote/parent_mode.txt" | Out-Null
    Write-Host "  [+] Termux home scripts installed via run-as" -ForegroundColor Green
}

function Apply-TabletSettings {
    param([string]$Serial)

    Write-Banner "TABLET SETTINGS (DNS, VOLUME BASELINE, KIOSK)"
    $adbS = @("-s", $Serial)

    # Do not force a hostname resolver on this firmware. It repeatedly marked
    # the saved WPA network as validation-failed and dropped its IP after a
    # few minutes, which interrupts NewPipe's 24/7 stream. Android's
    # opportunistic resolver keeps normal validation and uses the network DNS.
    & $ADB @adbS shell "settings put global private_dns_mode opportunistic"
    & $ADB @adbS shell "settings delete global private_dns_specifier"
    Write-Host "  [+] Opportunistic Private DNS (stable Wi-Fi validation)" -ForegroundColor Green

    # Animations
    & $ADB @adbS shell "settings put global window_animation_scale 0.5"
    & $ADB @adbS shell "settings put global transition_animation_scale 0.5"
    & $ADB @adbS shell "settings put global animator_duration_scale 0.5"

    # Keep Wi-Fi on (helps wireless ADB + NewPipe)
    & $ADB @adbS shell "settings put global wifi_on 1" 2>$null
    & $ADB @adbS shell "svc wifi enable" 2>$null

    # Stay awake while charging (optional for setup)
    & $ADB @adbS shell "settings put global stay_on_while_plugged_in 3" 2>$null

    # Child mode default
    & $ADB @adbS shell "rm -f $KioskRemote/parent_mode.txt" 2>$null

    # Read the phase from the tablet's local clock and the volumes from the
    # authoritative config. This avoids using the PC timezone or stale copies.
    $configText = Get-Content (Join-Path $ScriptsDir "kiosk_config.sh") -Raw
    $dayVolume = [int]([regex]::Match($configText, '(?m)^DAY_VOLUME=(\d+)').Groups[1].Value)
    $bedtimeVolume = [int]([regex]::Match($configText, '(?m)^BEDTIME_VOLUME=(\d+)').Groups[1].Value)
    $nightVolume = [int]([regex]::Match($configText, '(?m)^NIGHT_VOLUME=(\d+)').Groups[1].Value)
    $phase = (& $ADB @adbS shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c '. /data/data/com.termux/files/home/kiosk_config.sh; kiosk_current_phase'" 2>$null).Trim()
    $vol = switch ($phase) {
        "BEDTIME" { $bedtimeVolume; break }
        "NIGHT"   { $nightVolume; break }
        default   { $dayVolume; break }
    }
    & $ADB @adbS shell "cmd media_session volume --stream 3 --set $vol" 2>$null
    Write-Host "  [+] Volume baseline set to $vol (tablet phase: $phase; day $dayVolume/15, sleep $bedtimeVolume/15, night $nightVolume/15)" -ForegroundColor Green

    # Immersive NewPipe
    & $ADB @adbS shell "settings put global policy_control immersive.full=org.schabi.newpipe" 2>$null
    & $ADB @adbS shell "settings put secure immersive_mode_confirmations confirmed" 2>$null
    & $ADB @adbS shell "settings put secure home_key_disabled 1" 2>$null
    & $ADB @adbS shell "settings put secure back_key_disabled 1" 2>$null
    & $ADB @adbS shell "settings put global power_menu_disabled 1" 2>$null
    & $ADB @adbS shell "printf 'locked\n' > $KioskRemote/touch_mode.txt" 2>$null
    & $ADB @adbS shell "pm grant com.termux android.permission.WRITE_SECURE_SETTINGS" 2>$null
}

function Ensure-CalmLiveWallpaper {
    param([string]$Serial)
    Write-Banner "CALM ASMR LIVE WALLPAPER"
    $adbS = @("-s", $Serial)
    $termuxHomePath = "/data/data/com.termux/files/home"
    $wallpaperApk = Join-Path $ScriptsDir "calmwallpaper\calmwallpaper-signed.apk"
    $setterJar = Join-Path $ScriptsDir "LiveWallpaperSetter.jar"

    if (-not (Test-Path $wallpaperApk) -or -not (Test-Path $setterJar)) {
        Write-Host "  [!] Built wallpaper APK or setter helper is missing." -ForegroundColor Red
        return
    }

    & $ADB @adbS install -r $wallpaperApk | Write-Host
    & $ADB @adbS push $setterJar /data/local/tmp/LiveWallpaperSetter.jar | Out-Null
    & $ADB @adbS shell "CLASSPATH=/data/local/tmp/LiveWallpaperSetter.jar app_process / LiveWallpaperSetter com.android.calmwallpaper/.CalmWallpaperService" | Write-Host
    $wallState = & $ADB @adbS shell "dumpsys wallpaper" 2>$null

    if ($wallState -match "com.android.calmwallpaper") {
        & $ADB @adbS shell "run-as com.termux touch $termuxHomePath/Kiosk/live_wallpaper_enabled"
        Write-Host "  [+] Calm ASMR Live Wallpaper is active" -ForegroundColor Green
    } else {
        & $ADB @adbS shell "run-as com.termux rm -f $termuxHomePath/Kiosk/live_wallpaper_enabled"
        Write-Host "  [!] App installed, but Android requires selecting it once in Live Wallpapers." -ForegroundColor Yellow
    }
}

function Ensure-KioskSupportApp {
    param([string]$Serial)
    Write-Banner "KIOSK SUPPORT APP"
    $adbS = @("-s", $Serial)
    $supportApk = Join-Path $ScriptsDir "kioskbooter\kioskbooter-signed.apk"
    if (-not (Test-Path $supportApk)) {
        Write-Host "  [!] Built kiosk support APK is missing." -ForegroundColor Red
        return
    }

    & $ADB @adbS install -r $supportApk | Write-Host
    & $ADB @adbS shell "pm enable com.android.kioskbooter" | Out-Null
    $service = "com.android.kioskbooter/com.android.kioskbooter.InputBlockerService"
    $enabled = (& $ADB @adbS shell "settings get secure enabled_accessibility_services" 2>$null).Trim()
    $enabled = $enabled -replace '(^|:)none(?=:|$)', ''
    $enabled = $enabled.Trim(':')
    if (-not $enabled -or $enabled -eq "null") {
        $enabled = $service
    } elseif ($enabled -notmatch [regex]::Escape($service)) {
        $enabled = "$enabled`:$service"
    }
    & $ADB @adbS shell "settings put secure enabled_accessibility_services $enabled" | Out-Null
    & $ADB @adbS shell "settings put secure accessibility_enabled 1" | Out-Null
    & $ADB @adbS shell "printf 'locked\n' > $KioskRemote/touch_mode.txt" | Out-Null
    & $ADB @adbS shell "am broadcast -a com.android.kioskbooter.TOUCH_LOCK -n com.android.kioskbooter/.BootReceiver" | Out-Null
    & $ADB @adbS shell "am broadcast -a com.android.kioskbooter.WAKEUP -n com.android.kioskbooter/.BootReceiver" | Out-Null
    Write-Host "  [+] Boot helper, fullscreen lock, and child touch/button barrier installed" -ForegroundColor Green
}

function Ensure-Apps {
    param([string]$Serial)
    Write-Banner "CHECK APPS"
    $adbS = @("-s", $Serial)
    $pkgs = & $ADB @adbS shell "pm list packages" 2>$null

    $need = @{
        "org.schabi.newpipe"       = "NewPipe"
        "org.videolan.vlc"         = "VLC offline fallback"
        "com.termux"               = "Termux"
        "com.android.kioskbooter"  = "Kiosk Booter"
        "com.android.calmwallpaper" = "Calm live wallpaper"
    }
    foreach ($p in $need.Keys) {
        if ($pkgs -match [regex]::Escape("package:$p")) {
            Write-Host "  [+] $($need[$p]) installed" -ForegroundColor Green
        } else {
            Write-Host "  [!] $($need[$p]) MISSING ($p) - install from F-Droid / GitHub" -ForegroundColor Red
        }
    }

}

function Trigger-BootSequence {
    param([string]$Serial)
    Write-Banner "TRIGGER 24/7 NEWPIPE STACK"
    $adbS = @("-s", $Serial)
    Write-Host "Cleaning orphaned daemons and requesting one Kiosk Booter stack..." -ForegroundColor Yellow
    # Deployment explicitly establishes child mode. Clear the prior parent
    # state before the restart so the repaired stack starts with the intended
    # policy rather than briefly booting paused and relying on a later cleanup.
    & $ADB @adbS shell "rm -f /sdcard/Kiosk/parent_mode.txt" | Out-Null
    & $ADB @adbS shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash /data/data/com.termux/files/home/restart_kiosk_stack.sh" | Write-Host
    # restart_kiosk_stack.sh exercises the same retained RUN_COMMAND path used
    # after a cold boot, and waits for the guarded stack to settle.
    Start-Sleep -Seconds 3
    $fg = & $ADB @adbS shell "dumpsys window | grep mCurrentFocus" 2>$null
    Write-Host "Foreground: $fg" -ForegroundColor White
    if ($fg -match "newpipe") {
        Write-Host "[+] NewPipe is in foreground" -ForegroundColor Green
    } elseif ($fg -match "videolan.vlc") {
        Write-Host "[+] VLC offline fallback is in foreground" -ForegroundColor Green
    } else {
        Write-Host "Neither NewPipe nor VLC is focused yet - check tablet screen / open Termux once" -ForegroundColor Yellow
    }
}

function Show-Status {
    param([string]$Serial)
    Write-Banner "STATUS"
    $adbS = @("-s", $Serial)
    $model = (& $ADB @adbS shell getprop ro.product.model).Trim()
    $android = (& $ADB @adbS shell getprop ro.build.version.release).Trim()
    $ip = Get-DeviceIp -Serial $Serial
    Write-Host "  Model     : $model"
    Write-Host "  Android   : $android"
    Write-Host "  Serial    : $Serial"
    Write-Host "  Wi-Fi IP  : $ip"
    Write-Host "  Online    : NewPipe subscriptions; bedtime/night Edubuzzkids sleep channel"
    Write-Host "  Offline   : VLC permitted cached media fallback"
    Write-Host "  Wallpaper : Calm ASMR Live Wallpaper app"
    $configText = Get-Content (Join-Path $ScriptsDir "kiosk_config.sh") -Raw
    $dayVolume = [regex]::Match($configText, '(?m)^DAY_VOLUME=(\d+)').Groups[1].Value
    $nightVolume = [regex]::Match($configText, '(?m)^NIGHT_VOLUME=(\d+)').Groups[1].Value
    $bedtimeVolume = [regex]::Match($configText, '(?m)^BEDTIME_VOLUME=(\d+)').Groups[1].Value
    Write-Host "  Volume    : Day 06:00-20:30 = $dayVolume/15 | Sleep 20:30-06:00 = $bedtimeVolume/15"
    Write-Host ""
    Write-Host "  Boot owner : Kiosk Booter -> Termux RUN_COMMAND (single retained session)" -ForegroundColor Green
    Write-Host "  Reconnect later: .\DEPLOY-WIFI-ADB.ps1   or   adb connect ${ip}:$AdbPort" -ForegroundColor Cyan
}

# --- main ---
Write-Banner "SON'S TABLET - Wi-Fi ADB + NEWPIPE BOOT KIOSK"

if ($ForceUsb -and $SkipUsb) {
    Write-Error "-ForceUsb and -SkipUsb cannot be used together."
    exit 2
}
if ($ForceUsb -and $DeviceSerial -and $DeviceSerial -match ':') {
    Write-Error "-ForceUsb requires a USB serial; '$DeviceSerial' is a Wi-Fi serial."
    exit 2
}
if ($AdbPort -lt 1 -or $AdbPort -gt 65535) {
    Write-Error "-AdbPort must be between 1 and 65535."
    exit 2
}

$serial = Ensure-Connected -CheckOnly:$CheckOnly
if (-not $serial) { exit 2 }

if ($CheckOnly) {
    Show-Status -Serial $serial
    Ensure-Apps -Serial $serial
    exit 0
}

Push-KioskFiles -Serial $serial
Apply-TabletSettings -Serial $serial
Ensure-Apps -Serial $serial
Ensure-KioskSupportApp -Serial $serial
Ensure-CalmLiveWallpaper -Serial $serial
Trigger-BootSequence -Serial $serial
Show-Status -Serial $serial

Write-Banner "DONE"
Write-Host "Tablet configured: Wi-Fi ADB + NewPipe subscriptions-only fullscreen kiosk." -ForegroundColor Green
Write-Host "Cold-boot autoplay is owned by Kiosk Booter; child touch/navigation input is blocked." -ForegroundColor Green
