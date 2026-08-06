#!/system/bin/sh
# Quick Service Status Command
# Shows real-time status of all services and system health

set -u

HOME_DIR="/data/data/com.termux/files/home"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# Services to check
SERVICES=(
    "service_monitor.sh:Service Monitor"
    "newpipe_24x7.sh:NewPipe 24x7"
    "fullscreen_enforcer.sh:Fullscreen Enforcer"
    "volume_guard.sh:Volume Guard"
    "wallpaper_live.sh:ADHD Wallpaper"
    "wifi_keepalive.sh:Wi-Fi Keepalive"
    "download_scheduler.sh:Download Scheduler"
)

# Check service status
check_service() {
    local script=$1
    local name=$2
    
    if ps -ef 2>/dev/null | grep -F "$HOME_DIR/$script" | grep -v grep >/dev/null 2>&1; then
        echo "${GREEN}✓${NC} $name"
        return 0
    else
        echo "${RED}✗${NC} $name"
        return 1
    fi
}

# Get system info
get_system_info() {
    local device=$(getprop ro.product.model 2>/dev/null || echo "Unknown")
    local android=$(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
    
    echo "Device: $device"
    echo "Android: $android"
}

# Get storage info
get_storage_info() {
    if [ -d /sdcard ]; then
        local total=$(df /sdcard 2>/dev/null | tail -1 | awk '{print $2}')
        local used=$(df /sdcard 2>/dev/null | tail -1 | awk '{print $3}')
        local available=$(df /sdcard 2>/dev/null | tail -1 | awk '{print $4}')
        
        if [ -n "$total" ]; then
            local percent=$((used * 100 / total))
            echo "Storage: ${percent}% ($((used / 1024 / 1024))MB / $((total / 1024 / 1024))MB)"
        fi
    fi
}

# Get battery info
get_battery_info() {
    local level=""
    level=$(CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper get-battery 2>/dev/null)
    if [ -z "$level" ]; then
        local capacity_file=$(ls /sys/class/power_supply/*/capacity 2>/dev/null | grep -E 'battery|bat' | head -n 1)
        if [ -n "$capacity_file" ] && [ -f "$capacity_file" ]; then
            level=$(cat "$capacity_file" 2>/dev/null)
        fi
    fi
    if [ -z "$level" ] && command -v dumpsys >/dev/null 2>&1; then
        level=$(dumpsys battery 2>/dev/null | grep "level:" | awk '{print $2}')
    fi
    if [ -n "$level" ]; then
        echo "Battery: ${level}%"
    fi
}

# Get network info
get_network_info() {
    local status="UNKNOWN"
    
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        status="ONLINE"
    else
        status="OFFLINE"
    fi
    
    echo "Network: $status"
}

# Show full status
show_full_status() {
    clear
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          TABLET AUTOMATION SYSTEM STATUS                  ║"
    echo "║          $(date '+%Y-%m-%d %H:%M:%S')                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # System Info
    echo "📱 SYSTEM INFO"
    echo "─────────────────────────────────────────────────────────"
    get_system_info
    get_storage_info
    get_battery_info
    get_network_info
    echo ""
    
    # Services Status
    echo "🔧 SERVICE STATUS"
    echo "─────────────────────────────────────────────────────────"
    local running=0
    local total=${#SERVICES[@]}
    
    for service_entry in "${SERVICES[@]}"; do
        local script=$(echo "$service_entry" | cut -d: -f1)
        local name=$(echo "$service_entry" | cut -d: -f2)
        
        if check_service "$script" "$name"; then
            running=$((running + 1))
        fi
    done
    
    echo ""
    echo "Status: $running/$total services running"
    echo ""
    
    # Quick Diagnostics
    echo "🔍 QUICK DIAGNOSTICS"
    echo "─────────────────────────────────────────────────────────"
    
    if [ -f "$HOME_DIR/boot_orchestrator.log" ]; then
        local last_boot=$(grep "Boot orchestrator started" "$HOME_DIR/boot_orchestrator.log" | tail -1 | cut -d' ' -f1-2)
        if [ -n "$last_boot" ]; then
            echo "Last boot: $last_boot"
        fi
    fi
    
    if [ -f "$HOME_DIR/.service_state.json" ]; then
        echo "✓ Service state tracking active"
    fi
    
    if [ -f "/sdcard/Kiosk/crash_summary.txt" ]; then
        local crashes=$(grep "Total Crashes" "/sdcard/Kiosk/crash_summary.txt" | head -1)
        if [ -n "$crashes" ]; then
            echo "  $crashes"
        fi
    fi
    
    echo ""
    
    # Log suggestions
    if [ -f "$HOME_DIR/watchdog.log" ]; then
        local size=$(stat -f%z "$HOME_DIR/watchdog.log" 2>/dev/null || stat -c%s "$HOME_DIR/watchdog.log" 2>/dev/null || echo 0)
        if [ "$size" -gt 5242880 ]; then  # 5MB
            echo "${YELLOW}⚠️  WARNING: watchdog.log is getting large ($(($size / 1024 / 1024))MB)${NC}"
        fi
    fi
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║ Run './service_status.sh watch' to monitor continuously   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Watch mode (continuous refresh)
watch_mode() {
    while true; do
        show_full_status
        sleep 5
    done
}

# One-line status
one_line_status() {
    local running=0
    local total=${#SERVICES[@]}
    
    for service_entry in "${SERVICES[@]}"; do
        local script=$(echo "$service_entry" | cut -d: -f1)
        if ps -ef 2>/dev/null | grep -F "$HOME_DIR/$script" | grep -v grep >/dev/null 2>&1; then
            running=$((running + 1))
        fi
    done
    
    local battery=$(get_battery_info 2>/dev/null | cut -d: -f2 | tr -d ' ')
    local network=$(get_network_info | cut -d: -f2 | tr -d ' ')
    
    echo "Status: $running/$total services | Battery: $battery | Network: $network"
}

# Cleanup
cleanup() {
    exit 0
}

trap cleanup SIGTERM SIGINT

# Handle commands
case "${1:-show}" in
    show)
        show_full_status
        ;;
    watch)
        watch_mode
        ;;
    line)
        one_line_status
        ;;
    *)
        one_line_status
        ;;
esac
