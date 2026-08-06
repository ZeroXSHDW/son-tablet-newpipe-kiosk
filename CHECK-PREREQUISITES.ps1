#Requires -Version 5.1
<#
.SYNOPSIS
  Check host tools and local artifacts before deploying the Android kiosk.

.DESCRIPTION
  This is a read-only preflight. It does not connect to, modify, or install
  anything on an Android device. Use -RequireArtifacts for the full deployment
  gate and -CheckDevice after connecting a tablet over USB or Wi-Fi ADB.
#>
[CmdletBinding()]
param(
    [switch]$RequireArtifacts,
    [switch]$CheckDevice
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Failures = [System.Collections.Generic.List[string]]::new()
$Warnings = [System.Collections.Generic.List[string]]::new()

function Write-Result([string]$Label, [bool]$Passed, [string]$Detail) {
    $mark = if ($Passed) { '[OK]' } else { '[FAIL]' }
    $colour = if ($Passed) { 'Green' } else { 'Red' }
    Write-Host "$mark $Label — $Detail" -ForegroundColor $colour
}

function Require-Command([string]$Name, [string]$Purpose) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        Write-Result $Name $true "$Purpose ($($command.Source))"
    } else {
        Write-Result $Name $false "$Purpose is not installed or not on PATH"
        $Failures.Add("Install or expose '$Name' before continuing.")
    }
}

function Require-File([string]$RelativePath, [string]$Purpose) {
    $path = Join-Path $Root $RelativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Write-Result $RelativePath $true $Purpose
    } else {
        Write-Result $RelativePath $false "$Purpose is missing"
        $Failures.Add("Restore or build '$RelativePath'.")
    }
}

Write-Host 'Kiosk deployment preflight' -ForegroundColor Cyan
Write-Host "Repository: $Root"
Write-Host "Mode: $(if ($RequireArtifacts) { 'deployment' } else { 'source and host tools' })"
Write-Host ''

$psVersion = $PSVersionTable.PSVersion
$psPassed = $psVersion -ge [version]'5.1'
Write-Result 'PowerShell' $psPassed "version $psVersion (5.1 or newer required)"
if (-not $psPassed) { $Failures.Add('Use Windows PowerShell 5.1+ or PowerShell 7+.') }

Require-Command 'git' 'source checkout management'
Require-Command 'python' 'repository validation'
Require-Command 'bash' 'repository validation and shell checks'

$adb = Join-Path $Root 'platform-tools\adb.exe'
if (Test-Path -LiteralPath $adb -PathType Leaf) {
    Write-Result 'platform-tools\adb.exe' $true 'Android Debug Bridge is available'
} else {
    Write-Result 'platform-tools\adb.exe' $false 'required for deployment'
    $Failures.Add("Restore or build 'platform-tools\adb.exe'.")
}

if ($RequireArtifacts) {
    Write-Host ''
    Write-Host 'Deployment artifacts' -ForegroundColor Cyan
    Require-File 'termux_scripts\kioskhelper.jar' 'Termux helper JAR'
    Require-File 'termux_scripts\LiveWallpaperSetter.jar' 'live-wallpaper helper JAR'
    Require-File 'termux_scripts\kioskbooter\kioskbooter-signed.apk' 'Kiosk Booter support APK'
    Require-File 'termux_scripts\calmwallpaper\calmwallpaper-signed.apk' 'calm wallpaper support APK'
}

if ($CheckDevice) {
    Write-Host ''
    Write-Host 'Connected device' -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
        $Failures.Add('Cannot check a device until platform-tools\adb.exe is available.')
    } else {
        $devices = @(& $adb devices 2>$null | Where-Object { $_ -match "\t(device|unauthorized)$" })
        if ($devices.Count -gt 0) {
            Write-Result 'ADB device' $true (($devices -join '; ').Trim())
        } else {
            Write-Result 'ADB device' $false 'no authorized or pending device detected'
            $Warnings.Add('Unlock the tablet, enable USB debugging, and accept the authorization prompt.')
        }
    }
}

Write-Host ''
if ($Warnings.Count -gt 0) {
    Write-Host "Warnings: $($Warnings.Count)" -ForegroundColor Yellow
    foreach ($warning in $Warnings) { Write-Host "  - $warning" -ForegroundColor Yellow }
}
if ($Failures.Count -gt 0) {
    Write-Host "Preflight failed: $($Failures.Count) issue(s)" -ForegroundColor Red
    foreach ($failure in $Failures | Select-Object -Unique) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Preflight passed. You can continue with WAIT-AND-DEPLOY.ps1.' -ForegroundColor Green
exit 0
