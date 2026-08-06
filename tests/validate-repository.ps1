[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Failures = [System.Collections.Generic.List[string]]::new()
$Warnings = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $Failures.Add($Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

function Add-Warning([string]$Message) {
    $Warnings.Add($Message)
    Write-Host "WARN: $Message" -ForegroundColor Yellow
}

function Require-File([string]$RelativePath) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $RelativePath) -PathType Leaf)) {
        Add-Failure "required file is missing: $RelativePath"
    }
}

function Get-ShellInteger([string]$Name, [string]$ConfigText) {
    $match = [regex]::Match($ConfigText, "(?m)^$([regex]::Escape($Name))=(\d+)")
    if (-not $match.Success) {
        Add-Failure "kiosk_config.sh is missing numeric setting: $Name"
        return $null
    }
    return [int]$match.Groups[1].Value
}

Write-Host "Validating $Root" -ForegroundColor Cyan

$requiredFiles = @(
    'README-KIOSK.md',
    'GOAL.md',
    'ACTIVE-STACK.md',
    'BUILD-AND-ARTIFACTS.md',
    'DEPLOY-WIFI-ADB.ps1',
    'HEALTH-CHECK.ps1',
    'termux_scripts/kiosk_config.sh',
    'termux_scripts/boot_orchestrator_v2_integrated.sh',
    'termux_scripts/daemon_lib.sh',
    'termux_scripts/test_suite.sh',
    'termux_scripts/Kiosk/channels.json',
    'termux_scripts/Kiosk/newpipe_subscriptions.json',
    'termux_scripts/Kiosk/online_playlist.json',
    'termux_scripts/Kiosk/phase_schedule.json',
    'termux_scripts/Kiosk/download_schedule.json',
    'termux_scripts/kioskbooter/AndroidManifest.xml',
    'termux_scripts/kioskbooter/res/xml/accessibility_service_config.xml'
)
foreach ($file in $requiredFiles) { Require-File $file }

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $tracked = @(& $git.Source -C $Root ls-files)
    $forbiddenTrackedPatterns = @(
        '(^|/)platform-tools/',
        '(^|/)tablet-wifi-adb\.state\.json$',
        '(^|/)\.tmp_',
        '\.(apk|idsig|keystore|log|pid)$',
        '(^|/)cookies\.txt$'
    )
    foreach ($path in $tracked) {
        foreach ($pattern in $forbiddenTrackedPatterns) {
            if ($path -match $pattern) {
                Add-Failure "device-local or generated artifact is tracked: $path"
                break
            }
        }
    }

    $diffOutput = @(& $git.Source -C $Root diff --check 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "git diff --check failed: $($diffOutput -join ' ')"
    }

    foreach ($capture in @(
        'termux_scripts/Kiosk/final_screen.png',
        'termux_scripts/Kiosk/live_state.png',
        'termux_scripts/Kiosk/postrestart_state.png',
        'termux_scripts/Kiosk/user_visible_full.png'
    )) {
        $capturePath = Join-Path $Root $capture
        if (Test-Path -LiteralPath $capturePath) {
            & $git.Source -C $Root check-ignore --quiet -- $capture
            if ($LASTEXITCODE -ne 0) {
                Add-Failure "device capture is not ignored: $capture"
            }
        }
    }
} else {
    Add-Warning 'git is unavailable; tracked-file and diff checks were skipped'
}

$psParser = [System.Management.Automation.Language.Parser]
foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1') {
    if ($file.FullName -match '\\.git\\') { continue }
    $tokens = $null
    $errors = $null
    $null = $psParser::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        Add-Failure "PowerShell parse failed: $($file.FullName): $($errors | ForEach-Object Message -join '; ')"
    }
}

foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.json') {
    if ($file.FullName -match '\\.git\\') { continue }
    try {
        $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    } catch {
        Add-Failure "JSON parse failed: $($file.FullName): $($_.Exception.Message)"
    }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.py') {
        if ($file.FullName -match '\\.git\\') { continue }
        & $python.Source -m py_compile -- $file.FullName
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "Python compilation failed: $($file.FullName)"
        }
    }
} else {
    Add-Failure 'python is required for Python source validation'
}

$bashPath = $null
$bashCommand = Get-Command bash -ErrorAction SilentlyContinue
if ($bashCommand) {
    $bashPath = $bashCommand.Source
}
if (-not $bashPath -and $IsWindows) {
    foreach ($candidate in @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files\Git\usr\bin\bash.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) {
            $bashPath = $candidate
            break
        }
    }
}
if ($bashPath) {
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.sh') {
        if ($file.FullName -match '\\.git\\') { continue }
        & $bashPath -n $file.FullName
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "shell syntax check failed: $($file.FullName)"
        }
    }

    $config = Join-Path $Root 'termux_scripts/kiosk_config.sh'
    & $bashPath -c 'set -eu; . "$1"; kiosk_validate_config; test "$(kiosk_volume_for_phase BEDTIME)" = 3; test "$(kiosk_volume_for_phase NIGHT)" = 3; test "$(kiosk_volume_for_phase LEARNING)" = 12; test "$(kiosk_brightness_for_phase NIGHT)" = 25' _ $config
    if ($LASTEXITCODE -ne 0) {
        Add-Failure 'kiosk_config.sh runtime smoke test failed'
    }

    $shellSmoke = Join-Path $Root 'tests/shell-smoke.sh'
    & $bashPath $shellSmoke
    if ($LASTEXITCODE -ne 0) {
        Add-Failure 'shell behavior smoke test failed'
    }
} else {
    Add-Failure 'bash is required for shell source validation'
}

$configPath = Join-Path $Root 'termux_scripts/kiosk_config.sh'
$configText = Get-Content -LiteralPath $configPath -Raw
$phaseSchedule = Get-Content -LiteralPath (Join-Path $Root 'termux_scripts/Kiosk/phase_schedule.json') -Raw | ConvertFrom-Json
$phaseMap = @{
    MORNING  = @{ Start = (Get-ShellInteger 'MORNING_START' $configText); Volume = (Get-ShellInteger 'DAY_VOLUME' $configText); Brightness = (Get-ShellInteger 'MORNING_BRIGHTNESS' $configText) }
    LEARNING = @{ Start = (Get-ShellInteger 'LEARNING_START' $configText); Volume = (Get-ShellInteger 'DAY_VOLUME' $configText); Brightness = (Get-ShellInteger 'LEARNING_BRIGHTNESS' $configText) }
    RELAXING = @{ Start = (Get-ShellInteger 'RELAXING_START' $configText); Volume = (Get-ShellInteger 'DAY_VOLUME' $configText); Brightness = (Get-ShellInteger 'RELAXING_BRIGHTNESS' $configText) }
    BEDTIME  = @{ Start = (Get-ShellInteger 'BEDTIME_START' $configText); Volume = (Get-ShellInteger 'BEDTIME_VOLUME' $configText); Brightness = (Get-ShellInteger 'BEDTIME_BRIGHTNESS' $configText) }
    NIGHT    = @{ Start = (Get-ShellInteger 'NIGHT_START' $configText); Volume = (Get-ShellInteger 'NIGHT_VOLUME' $configText); Brightness = (Get-ShellInteger 'NIGHT_BRIGHTNESS' $configText) }
}
foreach ($phase in $phaseSchedule.phases) {
    if (-not $phaseMap.ContainsKey($phase.id)) {
        Add-Failure "phase schedule contains unknown phase: $($phase.id)"
        continue
    }
    $expected = $phaseMap[$phase.id]
    $start = '{0:D2}:{1:D2}' -f [int]($expected.Start / 100), [int]($expected.Start % 100)
    if ($phase.start -ne $start) { Add-Failure "$($phase.id) start differs from kiosk_config.sh ($($phase.start) vs $start)" }
    if ([int]$phase.volume -ne $expected.Volume) { Add-Failure "$($phase.id) volume differs from kiosk_config.sh" }
    if ([int]$phase.brightness -ne $expected.Brightness) { Add-Failure "$($phase.id) brightness differs from kiosk_config.sh" }
}

$channels = Get-Content -LiteralPath (Join-Path $Root 'termux_scripts/Kiosk/channels.json') -Raw | ConvertFrom-Json
if ($channels.mode -ne 'subscriptions_only') { Add-Failure 'channels.json is not subscriptions_only' }
if ($channels.allowed_channels.Count -ne 5) { Add-Failure "expected five allowed channels, found $($channels.allowed_channels.Count)" }
foreach ($channel in $channels.allowed_channels) {
    if (-not $channel.channel_videos.StartsWith('https://')) {
        Add-Failure "channel URL is not HTTPS: $($channel.name)"
    }
}

$downloadSchedule = Get-Content -LiteralPath (Join-Path $Root 'termux_scripts/Kiosk/download_schedule.json') -Raw | ConvertFrom-Json
if (-not ($downloadSchedule.networks -contains 'NETZ')) { Add-Failure 'download policy does not restrict downloads to NETZ' }
foreach ($source in $downloadSchedule.sources) {
    if (-not $source.StartsWith('https://')) { Add-Failure "download source is not HTTPS: $source" }
}

if ($configText -notmatch '(?m)^SUBSCRIPTIONS_ONLY=1\s*$') { Add-Failure 'SUBSCRIPTIONS_ONLY is not enabled' }
if ($configText -notmatch '(?m)^SLEEP_AUTOPLAY=1\s*$') { Add-Failure 'SLEEP_AUTOPLAY is not enabled' }
if ($configText -notmatch '(?m)^SLEEP_CHANNEL_URL="https://') { Add-Failure 'sleep channel URL is not HTTPS' }
if ($configText -notmatch '(?m)^SLEEP_FALLBACK_URL="https://') { Add-Failure 'sleep fallback URL is not HTTPS' }

$deployText = Get-Content -LiteralPath (Join-Path $Root 'DEPLOY-WIFI-ADB.ps1') -Raw
if ($deployText -notmatch '"test_suite\.sh"') {
    Add-Failure 'DEPLOY-WIFI-ADB.ps1 does not deploy the device-side test suite'
}

$licensePath = Join-Path $Root 'LICENSE'
if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) {
    Add-Warning 'no LICENSE file is present; choose and add the intended distribution license before publishing'
}

Write-Host ""
Write-Host "Validation failures: $($Failures.Count)" -ForegroundColor $(if ($Failures.Count) { 'Red' } else { 'Green' })
Write-Host "Validation warnings : $($Warnings.Count)" -ForegroundColor $(if ($Warnings.Count) { 'Yellow' } else { 'Green' })
if ($Failures.Count -gt 0) {
    Write-Host 'REPOSITORY VALIDATION: FAIL' -ForegroundColor Red
    exit 1
}
Write-Host 'REPOSITORY VALIDATION: PASS' -ForegroundColor Green
exit 0
