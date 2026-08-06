# Live USB device arrival monitor — logs every USB device Windows sees for a window of time.
$ErrorActionPreference = "SilentlyContinue"
$duration = 40  # seconds

Write-Host "=== USB MONITOR RUNNING for $duration seconds. PLUG THE TABLET IN NOW. ==="
Write-Host "(watching for ANY new USB/DeviceDir device arrivals)..."
Write-Host ""

$start = Get-Date
$before = Get-PnpDevice -PresentOnly | Select-Object -ExpandProperty InstanceId

$query = "SELECT * FROM __InstanceCreationEvent WITHIN 1 WHERE TargetSystem ISA 'Win32_PnPEntity'"
$startTime = (Get-Date)
$end = $startTime.AddSeconds($duration)

# Poll-based detection (more reliable than event registration for quick runs)
$seen = @{}
while ((Get-Date) -lt $end) {
    $now = Get-PnpDevice -PresentOnly
    foreach ($dev in $now) {
        if ($before -notcontains $dev.InstanceId) {
            if (-not $seen.ContainsKey($dev.InstanceId)) {
                $seen[$dev.InstanceId] = $true
                $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
                Write-Host ("[+{0,2}s] NEW: {1} | {2} | {3}" -f $elapsed, $dev.Status, $dev.Class, $dev.FriendlyName)
            }
        }
    }
    Start-Sleep -Milliseconds 700
}

Write-Host ""
if ($seen.Count -eq 0) {
    Write-Host "RESULT: Windows detected NO new USB device during the window."
    Write-Host "  -> This confirms the cable/port is not carrying data. Try a DATA cable and a different port."
} else {
    Write-Host ("RESULT: Windows detected {0} new device(s). Cable carries data." -f $seen.Count)
    Write-Host "  -> If none are 'Android/ADB', check the tablet's USB mode (set to File Transfer/MTP) and USB debugging."
}
