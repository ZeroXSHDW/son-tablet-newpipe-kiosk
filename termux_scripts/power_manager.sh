#!/system/bin/sh
# Power Management - Battery-Aware Service Monitoring
# Reduces monitoring frequency when in low-power mode

set -u

HOME_DIR="/data/data/com.termux/files/home"
LOG_FILE="$HOME_DIR/power_manager.log"
STATE_FILE="$HOME_DIR/.power_state"
NORMAL_INTERVALS="watchdog:3 monitor:5 enforcer:3 scheduler:30 volume:2 sync:30"
LOW_POWER_INTERVALS="watchdog:30 monitor:60 enforcer:0 scheduler:60 volume:0 sync:60"
CRITICAL_POWER_INTERVALS="watchdog:60 monitor:120 enforcer:0 scheduler:0 volume:0 sync:120"

# Logging
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper "$@"
}

# Get battery percentage
get_battery_level() {
    local level=""
    level=$(CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper get-battery 2>/dev/null)
    if [ -z "$level" ]; then
        local capacity_file=$(ls /sys/class/power_supply/*/capacity 2>/dev/null | grep -E 'battery|bat' | head -n 1)
        if [ -n "$capacity_file" ] && [ -f "$capacity_file" ]; then
            level=$(cat "$capacity_file" 2>/dev/null)
        fi
    fi
    if [ -z "$level" ] && command -v dumpsys >/dev/null 2>&1; then
        level=$(dumpsys battery 2>/dev/null | grep "level:" | head -1 | awk '{print $2}')
    fi
    echo "${level:-50}"
}

# Check if screen is on
is_screen_on() {
    [ "$(kiosk_helper is-screen-on 2>/dev/null)" = "true" ] && return 0
    return 1
}

# Get WiFi status
is_wifi_connected() {
    # Check via ip route (rootless, highly reliable)
    if ip route show 2>/dev/null | grep -q "wlan0"; then
        return 0
    fi
    # Fallback to get-wifi-rssi
    local rssi=$(kiosk_helper get-wifi-rssi 2>/dev/null || echo "-127")
    if [ "$rssi" -gt -127 ]; then
        return 0
    fi
    return 1
}

# Determine power mode
get_power_mode() {
    local battery=$(get_battery_level)
    local screen_on=$(is_screen_on && echo 1 || echo 0)
    local wifi=$(is_wifi_connected && echo 1 || echo 0)
    
    # Critical battery
    if [ "$battery" -lt 10 ]; then
        echo "CRITICAL"
        return
    fi
    
    # Low battery
    if [ "$battery" -lt 20 ]; then
        echo "LOW_POWER"
        return
    fi
    
    # Screen off = low power
    if [ "$screen_on" -eq 0 ]; then
        echo "SLEEP"
        return
    fi
    
    # Normal mode
    echo "NORMAL"
}

# Get interval for service in given mode
get_interval() {
    local service=$1
    local mode=$2
    
    case "$mode" in
        NORMAL)
            echo "$NORMAL_INTERVALS" | grep -o "${service}:[0-9]*" | cut -d: -f2
            ;;
        LOW_POWER)
            echo "$LOW_POWER_INTERVALS" | grep -o "${service}:[0-9]*" | cut -d: -f2
            ;;
        CRITICAL)
            echo "$CRITICAL_POWER_INTERVALS" | grep -o "${service}:[0-9]*" | cut -d: -f2
            ;;
        *)
            echo "30"
            ;;
    esac
}

# Apply power mode settings
apply_power_mode() {
    local mode=$1
    local battery=$(get_battery_level)
    
    log_msg "INFO: Entering $mode mode (Battery: $battery%)"
    
    case "$mode" in
        NORMAL)
            log_msg "✓ Normal operation: Full monitoring"
            adjust_intervals "$NORMAL_INTERVALS"
            ;;
        LOW_POWER)
            log_msg "⚠️  Low power mode: Reduced monitoring"
            log_msg "   - Watchdog: 3s → 30s"
            log_msg "   - Monitor: 5s → 60s"
            log_msg "   - Fullscreen: disabled"
            adjust_intervals "$LOW_POWER_INTERVALS"
            ;;
        SLEEP)
            log_msg "💤 Sleep mode: Minimal monitoring"
            log_msg "   - Watchdog: 30s (app already running)"
            log_msg "   - Network: 60s"
            log_msg "   - UI: disabled (screen off)"
            adjust_intervals "$LOW_POWER_INTERVALS"
            ;;
        CRITICAL)
            log_msg "🔴 Critical power mode: Emergency limits"
            log_msg "   - Watchdog: 60s"
            log_msg "   - Monitor: 120s"
            log_msg "   - Sync: 120s only"
            adjust_intervals "$CRITICAL_POWER_INTERVALS"
            ;;
    esac
    
    echo "$mode" > "$STATE_FILE"
}

# Adjust monitoring intervals
adjust_intervals() {
    local intervals=$1
    # In production, would send signals to running services to adjust their sleep intervals
    # For now, just log what would be done
    log_msg "DEBUG: Would apply intervals: $intervals"
}

# Apply eye comfort and brightness based on time of day
apply_display_comfort() {
    local hm=$(date +%H%M 2>/dev/null | tr -d '\r' || echo 0)
    hm=$(echo "$hm" | sed 's/^0*//')
    [ -z "$hm" ] && hm=0
    
    # Disable auto-brightness so our manual settings stick
    kiosk_helper write-setting system screen_brightness_mode 0 >/dev/null 2>&1 || true

    # Morning / Learning (06:00 - 19:00)
    if [ "$hm" -ge 600 ] && [ "$hm" -lt 1900 ]; then
        kiosk_helper write-setting secure night_display_activated 0 >/dev/null 2>&1 || true
        kiosk_helper write-setting system screen_brightness 180 >/dev/null 2>&1 || true
    # Relaxing (19:00 - 20:30)
    elif [ "$hm" -ge 1900 ] && [ "$hm" -lt 2030 ]; then
        kiosk_helper write-setting secure night_display_activated 1 >/dev/null 2>&1 || true
        kiosk_helper write-setting secure night_display_color_temperature 3500 >/dev/null 2>&1 || true
        kiosk_helper write-setting system screen_brightness 80 >/dev/null 2>&1 || true
    # Sleep (20:30 - 06:00)
    else
        kiosk_helper write-setting secure night_display_activated 1 >/dev/null 2>&1 || true
        kiosk_helper write-setting secure night_display_color_temperature 2500 >/dev/null 2>&1 || true
        kiosk_helper write-setting system screen_brightness 10 >/dev/null 2>&1 || true
    fi
}

# Main monitoring loop
monitor_power() {
    local last_mode="UNKNOWN"
    
    log_msg "Starting Power Manager & Display Comfort Guard"
    
    while true; do
        local current_mode=$(get_power_mode)
        local battery=$(get_battery_level)
        
        if [ "$current_mode" != "$last_mode" ]; then
            log_msg "Power mode changed: $last_mode → $current_mode (Battery: $battery%)"
            apply_power_mode "$current_mode"
            last_mode="$current_mode"
        fi
        
        # Enforce display brightness and blue-light filter based on time of day
        apply_display_comfort
        
        # Check every 30 seconds
        sleep 30
    done
}

# Show current power state
show_status() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          POWER MANAGEMENT STATUS                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local battery=$(get_battery_level)
    local screen=$(is_screen_on && echo "ON" || echo "OFF")
    local wifi=$(is_wifi_connected && echo "Connected" || echo "Disconnected")
    local mode=$(get_power_mode)
    
    echo "Battery Level: $battery%"
    echo "Screen: $screen"
    echo "WiFi: $wifi"
    echo "Current Mode: $mode"
    echo ""
    
    echo "Monitoring Intervals:"
    case "$mode" in
        NORMAL)
            echo "  Watchdog: 3s"
            echo "  Monitor: 5s"
            echo "  Enforcer: 3s"
            echo "  Scheduler: 30s"
            echo "  Volume: 2s"
            echo "  Sync: 30s"
            ;;
        LOW_POWER)
            echo "  Watchdog: 30s"
            echo "  Monitor: 60s"
            echo "  Enforcer: disabled"
            echo "  Scheduler: 60s"
            echo "  Volume: disabled"
            echo "  Sync: 60s"
            ;;
        CRITICAL)
            echo "  Watchdog: 60s"
            echo "  Monitor: 120s"
            echo "  Enforcer: disabled"
            echo "  Scheduler: disabled"
            echo "  Volume: disabled"
            echo "  Sync: 120s"
            ;;
    esac
    echo ""
}

# Cleanup on signal
cleanup() {
    log_msg "Power Manager shutting down"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Handle commands
case "${1:-monitor}" in
    monitor)
        monitor_power
        ;;
    status)
        show_status
        ;;
    battery)
        echo "Battery: $(get_battery_level)%"
        ;;
    screen)
        is_screen_on && echo "Screen: ON" || echo "Screen: OFF"
        ;;
    *)
        show_status
        ;;
esac
