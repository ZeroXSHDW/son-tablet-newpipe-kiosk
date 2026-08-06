# PowerShell script to continuously wait for USB ADB Tablet connection & authorization, then auto-configure
param(
    [int]$TimeoutSeconds = 300,
    [string]$DnsProvider = "family.cloudflare-dns.com"
)

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ADB = Join-Path $PSScriptRoot "platform-tools\adb.exe"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   WAITING FOR TABLET USB AUTHORIZATION (ADB)      " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Monitoring ADB for up to $TimeoutSeconds seconds..." -ForegroundColor Yellow
Write-Host ""

$startTime = Get-Date
$authorized = $false

while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
    $devicesOutput = & $ADB devices -l
    
    # Check if authorized device is present
    $deviceLine = $devicesOutput -split "`r`n" | Where-Object { $_ -and $_ -notlike "List of devices attached*" }

    if ($deviceLine) {
        if ($devicesOutput -match "unauthorized") {
            Write-Host "[!] TABLET DETECTED BUT UNAUTHORIZED! Check screen and tap 'ALLOW'..." -ForegroundColor Red
        } else {
            $authorized = $true
            Write-Host "[+] TABLET AUTHORIZED & READY!" -ForegroundColor Green
            Write-Host $deviceLine -ForegroundColor White
            Write-Host ""
            break
        }
    }

    Start-Sleep -Seconds 3
}

if ($authorized) {
    Write-Host "Executing auto-configuration on authorized tablet..." -ForegroundColor Cyan
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\configure-tablet.ps1" -DnsProvider $DnsProvider
} else {
    Write-Host "[!] Timeout reached ($TimeoutSeconds seconds)." -ForegroundColor Red
    Write-Host "    Please check tablet screen to accept the USB Debugging prompt." -ForegroundColor Yellow
}
