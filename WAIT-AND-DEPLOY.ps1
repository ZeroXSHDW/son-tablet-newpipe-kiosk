#Requires -Version 5.1
<#
.SYNOPSIS
  Wait until tablet appears on ADB, then full deploy of NewPipe 24/7 kiosk.
#>
param(
    [int]$TimeoutMinutes = 30,
    [string]$TabletIp = ""
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ADB = Join-Path $Root "platform-tools\adb.exe"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  WAIT FOR TABLET → DEPLOY NEWPIPE 24/7 KIOSK" -ForegroundColor Cyan
Write-Host "  Timeout: $TimeoutMinutes min | Ctrl+C to cancel" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "On tablet: USB debugging ON, plug data cable, tap ALLOW." -ForegroundColor Yellow
Write-Host ""

& $ADB start-server | Out-Null

while ((Get-Date) -lt $deadline) {
    if ($TabletIp) {
        & $ADB connect "${TabletIp}:5555" 2>$null | Out-Null
    }
    if (Test-Path (Join-Path $Root "tablet-wifi-adb.state.json")) {
        try {
            $s = Get-Content (Join-Path $Root "tablet-wifi-adb.state.json") -Raw | ConvertFrom-Json
            if ($s.tablet_ip) { & $ADB connect "$($s.tablet_ip):$($s.adb_port)" 2>$null | Out-Null }
        } catch {}
    }

    $out = & $ADB devices 2>&1 | Out-String
    $ts = Get-Date -Format "HH:mm:ss"

    if ($out -match "unauthorized") {
        Write-Host "[$ts] UNAUTHORIZED — accept prompt on tablet" -ForegroundColor Yellow
    } elseif ($out -match "\tdevice") {
        Write-Host "[$ts] DEVICE READY — deploying..." -ForegroundColor Green
        Write-Host $out
        & powershell -ExecutionPolicy Bypass -File (Join-Path $Root "DEPLOY-WIFI-ADB.ps1")
        $code = $LASTEXITCODE
        if ($code -eq 0 -or $null -eq $code) {
            Write-Host ""
            Write-Host "Deploy finished. Health check:" -ForegroundColor Green
            & powershell -ExecutionPolicy Bypass -File (Join-Path $Root "HEALTH-CHECK.ps1")
        }
        exit $code
    } else {
        Write-Host "[$ts] waiting for ADB device..."
    }
    Start-Sleep -Seconds 4
}

Write-Host "Timeout — tablet never appeared on ADB." -ForegroundColor Red
exit 2
