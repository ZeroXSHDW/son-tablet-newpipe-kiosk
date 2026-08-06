# PowerShell script for configuring Android Tablet via USB / ADB
param(
    [switch]$CheckOnly,
    [switch]$EnableFamilyDns,
    [switch]$OptimizePerformance,
    [string]$DnsProvider = "family.cloudflare-dns.com" # or "dns.adguard-dns.com"
)

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ADB = Join-Path $PSScriptRoot "platform-tools\adb.exe"

if (-not (Test-Path $ADB)) {
    Write-Error "ADB executable not found at $ADB"
    exit 1
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   ANDROID TABLET USB CONFIGURATION & DIAGNOSTIC    " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking for connected ADB devices..." -ForegroundColor Yellow
$devicesOutput = & $ADB devices -l
Write-Host $devicesOutput

$lines = $devicesOutput -split "`r`n" | Where-Object { $_ -and $_ -notlike "List of devices attached*" }

if (-not $lines) {
    Write-Host ""
    Write-Host "[!] NO ADB DEVICE DETECTED!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please complete the following steps on the tablet:" -ForegroundColor Yellow
    Write-Host "  1. Connect tablet to PC using a USB DATA cable." -ForegroundColor White
    Write-Host "  2. Go to Settings > About Tablet." -ForegroundColor White
    Write-Host "  3. Tap 'Build Number' 7 times until Developer Options are enabled." -ForegroundColor White
    Write-Host "  4. Go to Settings > Developer Options." -ForegroundColor White
    Write-Host "  5. Turn ON 'USB Debugging'." -ForegroundColor White
    Write-Host "  6. When the popup appears on the tablet, tap 'Allow USB debugging from this computer'." -ForegroundColor White
    Write-Host ""
    exit 0
}

# Check if device is unauthorized
if ($devicesOutput -match "unauthorized") {
    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Red
    Write-Host " [!] TABLET CONNECTED BUT ACTION REQUIRED ON TABLET " -ForegroundColor Red
    Write-Host "====================================================" -ForegroundColor Red
    Write-Host "The tablet screen is currently showing an authorization popup:" -ForegroundColor Yellow
    Write-Host "  -> Check the tablet screen now!" -ForegroundColor White
    Write-Host "  -> Check the box: 'Always allow from this computer'" -ForegroundColor White
    Write-Host "  -> Tap 'ALLOW' or 'OK'" -ForegroundColor White
    Write-Host ""
    exit 2
}

Write-Host "[+] Authorized ADB Device Detected!" -ForegroundColor Green
Write-Host ""

# Helper function to run ADB shell command safely
function Get-AdbProp($prop) {
    $val = & $ADB shell getprop $prop
    if ($val) { return $val.ToString().Trim() }
    return "Unknown"
}

# Query Device Information
Write-Host "--- Device Telemetry ---" -ForegroundColor Cyan
$model = Get-AdbProp "ro.product.model"
$manufacturer = Get-AdbProp "ro.product.manufacturer"
$androidVer = Get-AdbProp "ro.build.version.release"
$sdkVer = Get-AdbProp "ro.build.version.sdk"
$brand = Get-AdbProp "ro.product.brand"

Write-Host "Manufacturer  : $manufacturer" -ForegroundColor White
Write-Host "Model         : $model" -ForegroundColor White
Write-Host "Brand         : $brand" -ForegroundColor White
Write-Host "Android Ver   : $androidVer (API $sdkVer)" -ForegroundColor White

# Battery info
$battery = & $ADB shell dumpsys battery
if ($battery) {
    $levelLine = $battery | Select-String "level:"
    if ($levelLine) {
        Write-Host "Battery Level : $($levelLine.ToString().Trim())%" -ForegroundColor White
    }
}

Write-Host ""

if ($CheckOnly) {
    Write-Host "Check completed successfully." -ForegroundColor Green
    exit 0
}

# 1. Performance Optimizations
Write-Host "Applying UI Performance Optimizations (Animation Scale 0.5x)..." -ForegroundColor Yellow
& $ADB shell settings put global window_animation_scale 0.5
& $ADB shell settings put global transition_animation_scale 0.5
& $ADB shell settings put global animator_duration_scale 0.5
Write-Host "[+] Animations optimized for smoother UI." -ForegroundColor Green

# 2. Family / Child-Safe Private DNS Setup
Write-Host "Setting up Family Private DNS ($DnsProvider)..." -ForegroundColor Yellow
& $ADB shell settings put global private_dns_mode hostname
& $ADB shell settings put global private_dns_specifier $DnsProvider
Write-Host "[+] Private DNS configured to $DnsProvider (Blocks adult content & malicious domains)." -ForegroundColor Green

# 3. APK Sideloading (if apks folder exists and contains .apk files)
$apksFolder = Join-Path $PSScriptRoot "apks"
if (Test-Path $apksFolder) {
    $apks = Get-ChildItem -Path $apksFolder -Filter "*.apk"
    if ($apks) {
        Write-Host "Found $($apks.Count) APK(s) to install in $apksFolder..." -ForegroundColor Yellow
        foreach ($apk in $apks) {
            Write-Host "Installing $($apk.Name)..." -ForegroundColor White
            & $ADB install -r $apk.FullName
        }
        Write-Host "[+] APK installation complete." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "       TABLET CONFIGURATION SUCCESSFULLY APPLIED!   " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
