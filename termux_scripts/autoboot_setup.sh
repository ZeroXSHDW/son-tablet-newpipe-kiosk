#!/system/bin/sh
#
# AUTO-BOOT SERVICE SETUP v2.0
# Ensures all services and MacroDroid macros auto-boot on device startup
# Runs automatically from .termux/boot/start.sh
#

set -eu

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:$PATH

LOG_FILE="$HOME/autoboot_setup.log"
BOOT_STATE_FILE="/sdcard/Kiosk/autoboot_state.json"

log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

echo "" >> "$LOG_FILE"
log_msg "=== AUTO-BOOT SERVICE SETUP ==="

# ============================================================================
# STEP 1: VERIFY TERMUX:BOOT SERVICE IS ACTIVE
# ============================================================================

log_msg "Step 1: Verifying Termux:Boot service..."

# Check if boot service directory exists
if [ ! -d "$HOME/.termux/boot" ]; then
    log_msg "Creating boot service directory..."
    mkdir -p "$HOME/.termux/boot"
    chmod 755 "$HOME/.termux/boot"
fi

# Create/verify boot starter script
BOOT_SCRIPT="$HOME/.termux/boot/start.sh"
if [ ! -f "$BOOT_SCRIPT" ]; then
    log_msg "Creating boot starter script..."
    cat > "$BOOT_SCRIPT" << 'BOOTEOF'
#!/system/bin/sh
# Auto-boot starter for Termux:Boot service

HOME=/data/data/com.termux/files/home
export HOME
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:$PATH

sleep 10

if [ -f "$HOME/boot_orchestrator_v2_integrated.sh" ]; then
    exec /data/data/com.termux/files/usr/bin/bash "$HOME/boot_orchestrator_v2_integrated.sh"
elif [ -f "$HOME/boot_orchestrator_v2.sh" ]; then
    exec /data/data/com.termux/files/usr/bin/bash "$HOME/boot_orchestrator_v2.sh"
elif [ -f "$HOME/boot_orchestrator.sh" ]; then
    exec /data/data/com.termux/files/usr/bin/bash "$HOME/boot_orchestrator.sh"
else
    echo "[ERROR] No boot orchestrator found" >> "$HOME/autoboot_setup.log"
fi
BOOTEOF
    chmod 755 "$BOOT_SCRIPT"
    log_msg "Boot script created and made executable"
else
    log_msg "Boot script already exists"
fi

# Keep a compatibility boot launcher for MacroDroid and manual recovery
if [ ! -f "$HOME/boot_script.sh" ]; then
    log_msg "Creating compatibility boot_script.sh..."
    cat > "$HOME/boot_script.sh" << 'BOOTCOMPAT'
#!/system/bin/sh
exec /data/data/com.termux/files/usr/bin/bash /data/data/com.termux/files/home/boot_orchestrator_v2_integrated.sh
BOOTCOMPAT
    chmod 755 "$HOME/boot_script.sh"
fi

# ============================================================================
# STEP 2: VERIFY ALL REQUIRED SERVICES EXIST
# ============================================================================

log_msg "Step 2: Verifying required service scripts..."

REQUIRED_SERVICES=(
    "boot_orchestrator_v2.sh:Boot Orchestrator"
    "kiosk_watchdog_v2.sh:Kiosk Watchdog"
    "network_monitor.sh:Network Monitor"
    "fullscreen_enforcer.sh:Fullscreen Enforcer"
    "download_scheduler.sh:Download Scheduler"
    "volume_guard.sh:Volume Guard"
    "sync_wifi.py:WiFi Sync"
)

MISSING_COUNT=0
for service_info in "${REQUIRED_SERVICES[@]}"; do
    IFS=':' read -r script_name service_name <<< "$service_info"
    if [ -f "$HOME/$script_name" ]; then
        log_msg "  ✓ $service_name found"
    else
        log_msg "  ✗ $service_name MISSING"
        ((MISSING_COUNT++))
    fi
done

if [ "$MISSING_COUNT" -gt 0 ]; then
    log_msg "WARNING: $MISSING_COUNT services missing - run setup_v2.sh"
fi

# ============================================================================
# STEP 3: VERIFY CONFIGURATION FILES
# ============================================================================

log_msg "Step 3: Verifying configuration files..."

CONFIG_DIR="/sdcard/Kiosk"
mkdir -p "$CONFIG_DIR"

# Create phase file if missing
if [ ! -f "$CONFIG_DIR/phase.txt" ]; then
    log_msg "Creating phase.txt..."
    HOUR=$(date +%H | sed 's/^0//')
    if [ "$HOUR" -ge 6 ] && [ "$HOUR" -lt 7 ]; then
        echo "MORNING" > "$CONFIG_DIR/phase.txt"
    elif [ "$HOUR" -ge 7 ] && [ "$HOUR" -lt 19 ]; then
        echo "LEARNING" > "$CONFIG_DIR/phase.txt"
    elif [ "$HOUR" -ge 19 ] && [ "$HOUR" -lt 20 ]; then
        echo "RELAXING" > "$CONFIG_DIR/phase.txt"
    else
        echo "SLEEP" > "$CONFIG_DIR/phase.txt"
    fi
fi

# Create download schedule if missing
if [ ! -f "$CONFIG_DIR/download_schedule.json" ]; then
    log_msg "Creating download_schedule.json..."
    cat > "$CONFIG_DIR/download_schedule.json" << 'JSONEOF'
{
  "enabled": true,
  "download_time": "02:00",
  "frequency": "bi-daily",
  "networks": ["VODAFONE"],
  "preferred_quality": "720p",
  "max_storage_mb": 5000,
  "playlists": [
    "https://www.youtube.com/@MsRachel/videos",
    "https://www.youtube.com/@TractorTed/videos",
    "https://www.youtube.com/@Teletubbies/videos",
    "https://www.youtube.com/@edubuzzkids/videos",
    "https://www.youtube.com/channel/UCrbHp6Xh0oEOhOozMk9t_wQ/videos"
  ]
}
JSONEOF
fi

# Create download state if missing
if [ ! -f "$CONFIG_DIR/download_state.json" ]; then
    log_msg "Creating download_state.json..."
    cat > "$CONFIG_DIR/download_state.json" << 'JSONEOF'
{
  "last_download": null,
  "next_scheduled": null,
  "total_videos": 0,
  "total_size_mb": 0,
  "last_success": null,
  "last_error": null
}
JSONEOF
fi

# Create offline videos directory
if [ ! -d "$CONFIG_DIR/offline_videos" ]; then
    log_msg "Creating offline_videos directory..."
    mkdir -p "$CONFIG_DIR/offline_videos"
fi

# Ensure wallpaper asset placeholder exists
if [ ! -f "$CONFIG_DIR/wallpaper_ready.txt" ]; then
    log_msg "Recording wallpaper readiness flag..."
    echo "wallpaper_asset=/sdcard/Download/wallpaper.png" > "$CONFIG_DIR/wallpaper_ready.txt"
fi

log_msg "Configuration files verified/created"

# ============================================================================
# STEP 4: ENABLE TERMUX:BOOT SERVICE (if available via ADB)
# ============================================================================

log_msg "Step 4: Termux:Boot service status..."
log_msg "NOTE: User must open Termux:Boot app on tablet once to enable auto-boot"

# ============================================================================
# STEP 5: RECORD BOOT STATE
# ============================================================================

log_msg "Step 5: Recording auto-boot state..."

cat > "$BOOT_STATE_FILE" << STATEEOF
{
  "autoboot_configured": true,
  "boot_time": "$(date -Iseconds)",
  "boot_script": "$BOOT_SCRIPT",
  "services": [
    "boot_orchestrator_v2.sh",
    "kiosk_watchdog_v2.sh",
    "network_monitor.sh",
    "fullscreen_enforcer.sh",
    "download_scheduler.sh",
    "volume_guard.sh",
    "sync_wifi.py"
  ],
  "config_files": [
    "$CONFIG_DIR/phase.txt",
    "$CONFIG_DIR/download_schedule.json",
    "$CONFIG_DIR/download_state.json"
  ]
}
STATEEOF

log_msg "Auto-boot state recorded to: $BOOT_STATE_FILE"

# ============================================================================
# STEP 6: VERIFY BOOT ORCHESTRATOR RUNS
# ============================================================================

log_msg "Step 6: Verifying boot orchestrator execution..."

if [ -f "$HOME/boot_orchestrator_v2.sh" ]; then
    log_msg "Executing boot_orchestrator_v2.sh..."
    exec /data/data/com.termux/files/usr/bin/bash "$HOME/boot_orchestrator_v2.sh" &
    log_msg "Boot orchestrator started"
else
    log_msg "ERROR: boot_orchestrator_v2.sh not found!"
fi

log_msg "=== AUTO-BOOT SETUP COMPLETE ==="
