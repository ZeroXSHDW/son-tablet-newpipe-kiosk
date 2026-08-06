# Discover this PC's IP and live hosts on the local subnet (for Wi-Fi ADB discovery)
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== PC IP(s) on LAN ==="
$ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' -and $_.PrefixOrigin -ne 'WellKnown' }
$ips | Select-Object IPAddress, InterfaceAlias, PrefixLength | Format-Table -AutoSize

# Prefer active Wi-Fi / DHCP subnet
$primary = $ips | Where-Object { $_.InterfaceAlias -match 'Wi-Fi|WLAN|Wireless' } | Select-Object -First 1
if (-not $primary) {
    $primary = $ips | Where-Object { $_.PrefixOrigin -eq 'Dhcp' } | Select-Object -First 1
}
if (-not $primary) {
    Write-Host "No suitable LAN interface found." -ForegroundColor Red
    exit 1
}

$parts = $primary.IPAddress.Split('.')
$prefix = "$($parts[0]).$($parts[1]).$($parts[2])"
Write-Host "Scanning subnet $prefix.0/24 (from $($primary.InterfaceAlias))..." -ForegroundColor Yellow

$jobs = 1..254 | ForEach-Object {
    $target = "$prefix.$_"
    [System.Net.NetworkInformation.Ping]::new().SendPingAsync($target, 80)
}
try {
    [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$jobs, 20000)
} catch {}

Start-Sleep -Milliseconds 500
Write-Host "=== Live hosts ==="
Get-NetNeighbor -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -like "$prefix.*" -and $_.State -match 'Reachable|Stale|Delay|Probe' } |
    Select-Object IPAddress, LinkLayerAddress, State |
    Sort-Object { [int]($_.IPAddress.Split('.')[3]) } |
    Format-Table -AutoSize

Write-Host "=== Try ADB Wi-Fi on port 5555 (skip this PC) ==="
$ADB = Join-Path $PSScriptRoot "platform-tools\adb.exe"
$me = $primary.IPAddress
$hosts = Get-NetNeighbor -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -like "$prefix.*" -and $_.State -match 'Reachable|Stale' } |
    Select-Object -ExpandProperty IPAddress

foreach ($h in $hosts) {
    if ($h -eq $me) { continue }
    Write-Host "adb connect ${h}:5555 ..." -NoNewline
    $r = & $ADB connect "${h}:5555" 2>&1
    Write-Host " $r"
}

Write-Host ""
Write-Host "Devices:" -ForegroundColor Cyan
& $ADB devices -l
