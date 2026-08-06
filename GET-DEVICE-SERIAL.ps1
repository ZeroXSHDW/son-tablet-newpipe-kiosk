#Requires -Version 5.1
<#
.SYNOPSIS
  Show connected Android ADB devices and the serial to use with this project.

.DESCRIPTION
  This is a read-only helper. It starts the local ADB server, lists USB and
  Wi-Fi devices with friendly status labels, and prints copy-paste commands.
  Use -Wait when connecting a tablet for the first time or -Copy when exactly
  one authorized device should be copied to the Windows clipboard.
#>
[CmdletBinding()]
param(
    [switch]$Wait,
    [int]$TimeoutSeconds = 60,
    [switch]$Copy
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ADB = Join-Path $Root 'platform-tools\adb.exe'

function Get-DeviceRows {
    $lines = @(& $ADB devices -l 2>$null)
    foreach ($line in $lines) {
        if ($line -match '^List of devices attached' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^(?<serial>\S+)\s+(?<state>\S+)(?<details>.*)$') {
            $serial = $Matches.serial
            $state = $Matches.state
            $details = $Matches.details.Trim()
            $transport = if ($serial -match ':\d+$') { 'Wi-Fi' } else { 'USB' }
            [pscustomobject]@{
                Serial = $serial
                State = $state
                Transport = $transport
                Details = $details
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $ADB -PathType Leaf)) {
    Write-Host "ADB is missing: $ADB" -ForegroundColor Red
    Write-Host 'Restore platform-tools, then run .\CHECK-PREREQUISITES.ps1.' -ForegroundColor Yellow
    exit 1
}

& $ADB start-server | Out-Null
$deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
$rows = @()
do {
    $rows = @(Get-DeviceRows)
    $ready = @($rows | Where-Object { $_.State -eq 'device' })
    if (-not $Wait -or $ready.Count -gt 0 -or (Get-Date) -ge $deadline) { break }
    Write-Host 'Waiting for an ADB device. Unlock the tablet and accept USB debugging...' -ForegroundColor Yellow
    Start-Sleep -Seconds 2
} while ($true)

Write-Host ''
Write-Host 'Connected Android devices' -ForegroundColor Cyan
Write-Host ('{0,-28} {1,-14} {2,-12} {3}' -f 'SERIAL', 'STATE', 'TRANSPORT', 'DETAILS')
Write-Host ('-' * 86)
if ($rows.Count -eq 0) {
    Write-Host 'No device detected.' -ForegroundColor Yellow
    Write-Host 'Connect the tablet, enable USB debugging, unlock it, and accept the authorization prompt.'
    exit 2
}
foreach ($row in $rows) {
    $colour = if ($row.State -eq 'device') { 'Green' } elseif ($row.State -eq 'unauthorized') { 'Yellow' } else { 'Red' }
    Write-Host ('{0,-28} {1,-14} {2,-12} {3}' -f $row.Serial, $row.State, $row.Transport, $row.Details) -ForegroundColor $colour
}

$ready = @($rows | Where-Object { $_.State -eq 'device' })
Write-Host ''
if ($ready.Count -eq 0) {
    Write-Host 'No authorized device is ready yet.' -ForegroundColor Yellow
    Write-Host 'If the state is unauthorized, accept the USB debugging prompt on the tablet and run this command again.'
    exit 3
}

if ($ready.Count -eq 1) {
    $serial = $ready[0].Serial
    Write-Host "Use this serial: $serial" -ForegroundColor Green
    Write-Host ".\DEPLOY-WIFI-ADB.ps1 -DeviceSerial `"$serial`""
    Write-Host ".\HEALTH-CHECK.ps1 -DeviceSerial `"$serial`""
    if ($Copy) {
        if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $serial
            Write-Host 'Serial copied to the clipboard.' -ForegroundColor Green
        } else {
            Write-Host 'Clipboard copy is unavailable in this shell; copy the serial above.' -ForegroundColor Yellow
        }
    }
} else {
    Write-Host 'Multiple authorized devices found. Choose one serial and pass it explicitly:' -ForegroundColor Yellow
    foreach ($device in $ready) {
        Write-Host ".\DEPLOY-WIFI-ADB.ps1 -DeviceSerial `"$($device.Serial)`""
    }
}

exit 0
