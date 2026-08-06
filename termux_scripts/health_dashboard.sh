#!/system/bin/sh
# System Health Dashboard
# Generates comprehensive health reports with trending

set -u

HOME_DIR="/data/data/com.termux/files/home"
KIOSK_DIR="/sdcard/Kiosk"
HEALTH_REPORT="$HOME_DIR/health_dashboard.txt"
HEALTH_JSON="$HOME_DIR/health_dashboard.json"
UPTIME_TRACK="$HOME_DIR/.uptime_tracking"

# Initialize tracking
init_tracking() {
    if [ ! -f "$UPTIME_TRACK" ]; then
        cat > "$UPTIME_TRACK" << 'EOF'
{
  "boot_count": 0,
  "total_uptime_seconds": 0,
  "crashes_today": 0,
  "crashes_total": 0,
  "recovery_rate": 100,
  "avg_crash_interval_hours": 0,
  "network_availability": 100,
  "last_boot": null,
  "last_update": null
}
EOF
    fi
}

# Get uptime
get_uptime() {
    uptime | awk '{print $1}' || echo "0"
}

# Generate health report
generate_health_report() {
    init_tracking
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local uptime=$(get_uptime)
    local battery=""
    battery=$(CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper get-battery 2>/dev/null)
    if [ -z "$battery" ]; then
        local capacity_file=$(ls /sys/class/power_supply/*/capacity 2>/dev/null | grep -E 'battery|bat' | head -n 1)
        if [ -n "$capacity_file" ] && [ -f "$capacity_file" ]; then
            battery=$(cat "$capacity_file" 2>/dev/null)
        fi
    fi
    [ -z "$battery" ] && battery=$(dumpsys battery 2>/dev/null | grep "level:" | awk '{print $2}')
    [ -z "$battery" ] && battery="?"
    local storage=$(df /sdcard 2>/dev/null | tail -1 | awk '{print int($3*100/$2)}' || echo "?")
    
    {
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║          SYSTEM HEALTH DASHBOARD                          ║"
        echo "║          $timestamp                          ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        echo "📊 SYSTEM METRICS"
        echo "──────────────────────────────────────────────────────────"
        echo "Current Uptime: $uptime"
        echo "Battery Level: ${battery}%"
        echo "Storage Used: ${storage}%"
        echo ""
        
        echo "🔧 SERVICE HEALTH"
        echo "──────────────────────────────────────────────────────────"
        
        local services=(
            "service_monitor.sh:Service Monitor"
            "kiosk_watchdog_v2.sh:Kiosk Watchdog"
            "network_monitor.sh:Network Monitor"
            "fullscreen_enforcer.sh:Fullscreen Enforcer"
            "download_scheduler.sh:Download Scheduler"
            "volume_guard.sh:Volume Guard"
            "parent_dashboard:Parent Dashboard"
        )
        
        local running=0
        for service_entry in "${services[@]}"; do
            local script=$(echo "$service_entry" | cut -d: -f1)
            local name=$(echo "$service_entry" | cut -d: -f2)
            
            if pgrep -f "$script" >/dev/null 2>&1; then
                echo "✓ $name"
                running=$((running + 1))
            else
                echo "✗ $name"
            fi
        done
        
        echo ""
        echo "Services: $running/${#services[@]} running"
        echo ""
        
        echo "📈 RELIABILITY METRICS"
        echo "──────────────────────────────────────────────────────────"
        
        if [ -f "/sdcard/Kiosk/crash_summary.txt" ]; then
            grep "Total Crashes\|Recovery Rate\|ALERTS" "/sdcard/Kiosk/crash_summary.txt" 2>/dev/null | head -10
        else
            echo "No crash data available"
        fi
        
        echo ""
        
        echo "🌐 NETWORK METRICS"
        echo "──────────────────────────────────────────────────────────"
        
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            echo "✓ Internet: ONLINE"
        else
            echo "✗ Internet: OFFLINE"
        fi
        
        if [ -f "/sdcard/Kiosk/network_quality.json" ]; then
            echo "Network Quality: Available"
        fi
        
        echo ""
        
        echo "💾 STORAGE ANALYSIS"
        echo "──────────────────────────────────────────────────────────"
        
        local offline_vids=$(find /sdcard/Kiosk/offline_videos -type f -name "*.mp4" 2>/dev/null | wc -l)
        echo "Offline Videos: $offline_vids"
        
        local video_size=$(du -sh /sdcard/Kiosk/offline_videos 2>/dev/null | awk '{print $1}')
        echo "Video Storage: $video_size"
        
        echo ""
        
        echo "⏱️  TIMING DATA"
        echo "──────────────────────────────────────────────────────────"
        
        if [ -f "$HOME_DIR/boot_orchestrator.log" ]; then
            local boots=$(grep -c "Boot orchestrator started" "$HOME_DIR/boot_orchestrator.log" 2>/dev/null || echo 0)
            echo "Total Boots: $boots"
            
            local last_boot=$(grep "Boot orchestrator started" "$HOME_DIR/boot_orchestrator.log" | tail -1 | cut -d' ' -f1-2)
            echo "Last Boot: $last_boot"
        fi
        
        echo ""
        
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║ Report generated: $timestamp"
        echo "╚════════════════════════════════════════════════════════════╝"
        
    } > "$HEALTH_REPORT"
    
    cat "$HEALTH_REPORT"
}

# Generate JSON report
generate_json_report() {
    init_tracking
    
    local battery=""
    battery=$(CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper get-battery 2>/dev/null)
    if [ -z "$battery" ]; then
        local capacity_file=$(ls /sys/class/power_supply/*/capacity 2>/dev/null | grep -E 'battery|bat' | head -n 1)
        if [ -n "$capacity_file" ] && [ -f "$capacity_file" ]; then
            battery=$(cat "$capacity_file" 2>/dev/null)
        fi
    fi
    [ -z "$battery" ] && battery=$(dumpsys battery 2>/dev/null | grep "level:" | awk '{print $2}')
    [ -z "$battery" ] && battery="0"
    local storage=$(df /sdcard 2>/dev/null | tail -1 | awk '{print int($3*100/$2)}' || echo "0")
    local online="false"
    
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        online="true"
    fi
    
    local running=0
    local total=7
    
    for script in "service_monitor.sh" "kiosk_watchdog_v2.sh" "network_monitor.sh" "fullscreen_enforcer.sh" "download_scheduler.sh" "volume_guard.sh" "server.sh"; do
        if pgrep -f "$script" >/dev/null 2>&1; then
            running=$((running + 1))
        fi
    done
    
    cat > "$HEALTH_JSON" << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "system": {
    "uptime": "$(get_uptime)",
    "battery_percent": $battery,
    "storage_used_percent": $storage
  },
  "services": {
    "running": $running,
    "total": $total,
    "health_percent": $((running * 100 / total))
  },
  "network": {
    "online": $online
  },
  "timestamp_unix": $(date +%s)
}
EOF
    
    cat "$HEALTH_JSON"
}

# Show trending
show_trending() {
    if [ -f "$HEALTH_JSON" ]; then
        echo "Trending data available in: $HEALTH_JSON"
        head -20 "$HEALTH_JSON"
    else
        echo "No trending data yet. Run health dashboard generation first."
    fi
}

# Cleanup
trap 'exit 0' SIGTERM SIGINT

# Handle commands
case "${1:-report}" in
    report)
        generate_health_report
        ;;
    json)
        generate_json_report
        ;;
    trending)
        show_trending
        ;;
    *)
        generate_health_report
        ;;
esac
