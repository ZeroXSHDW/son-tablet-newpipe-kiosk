#!/system/bin/sh
# Uptime & Performance Tracker
# Monitors system uptime, crash rates, and generates statistics

set -u

HOME_DIR="/data/data/com.termux/files/home"
if mkdir -p /sdcard/Kiosk 2>/dev/null && touch /sdcard/Kiosk/.write_test 2>/dev/null; then
    KIOSK_DIR="/sdcard/Kiosk"
    rm -f /sdcard/Kiosk/.write_test
else
    KIOSK_DIR="$HOME_DIR"
fi
UPTIME_LOG="$HOME_DIR/uptime_tracker.log"
UPTIME_JSON="$KIOSK_DIR/uptime_stats.json"
HOURLY_LOG="$KIOSK_DIR/hourly_stats.log"

# Initialize uptime tracker
init_tracker() {
    if [ ! -f "$UPTIME_JSON" ]; then
        cat > "$UPTIME_JSON" << 'EOF'
{
  "boot_count": 0,
  "total_uptime_hours": 0,
  "crashes_today": 0,
  "crashes_total": 0,
  "recovery_rate_percent": 100,
  "avg_crash_interval_hours": 0,
  "network_availability_percent": 100,
  "last_boot_timestamp": null,
  "current_session_uptime_seconds": 0
}
EOF
    fi
}

# Update boot count
record_boot() {
    init_tracker
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local boot_count=1
    
    if [ -f "$UPTIME_JSON" ]; then
        boot_count=$(grep -o '"boot_count": [0-9]*' "$UPTIME_JSON" | head -1 | cut -d: -f2 | tr -d ' ')
        boot_count=$((boot_count + 1))
    fi
    
    echo "[$timestamp] [INFO] Boot #$boot_count recorded" >> "$UPTIME_LOG"
    
    # This is simplified - in production would use jq to update JSON properly
    cat > "$UPTIME_JSON" << EOF
{
  "boot_count": $boot_count,
  "last_boot_timestamp": "$timestamp",
  "current_session_uptime_seconds": 0
}
EOF
}

# Track crash
record_crash() {
    local app=$1
    local reason=$2
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    echo "[$timestamp] [CRASH] App: $app | Reason: $reason" >> "$UPTIME_LOG"
}

# Get current session uptime
get_session_uptime() {
    if [ -f "$UPTIME_LOG" ]; then
        local boot_time=$(grep "Boot #" "$UPTIME_LOG" | tail -1 | cut -d' ' -f1)
        local now=$(date '+%s')
        local boot_epoch=$(date -d "$boot_time" '+%s' 2>/dev/null || date '+%s')
        
        local uptime=$((now - boot_epoch))
        echo "$uptime"
    else
        echo "0"
    fi
}

# Generate hourly report
generate_hourly_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hour=$(date +%H)
    local session_uptime=$(get_session_uptime)
    local session_hours=$((session_uptime / 3600))
    
    {
        echo "$timestamp [HOURLY_REPORT]"
        echo "  Hour: $hour"
        echo "  Session Uptime: ${session_hours}h $(($session_uptime % 3600 / 60))m"
        
        if [ -f "/sdcard/Kiosk/crash_summary.txt" ]; then
            grep "Crashes" "/sdcard/Kiosk/crash_summary.txt" | head -2
        fi
        
        echo ""
        
    } >> "$HOURLY_LOG"
}

# Show statistics
show_stats() {
    init_tracker
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local session_uptime=$(get_session_uptime)
    local hours=$((session_uptime / 3600))
    local minutes=$(($session_uptime % 3600 / 60))
    local seconds=$(($session_uptime % 60))
    
    {
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║          UPTIME & PERFORMANCE STATISTICS                  ║"
        echo "║          $timestamp                          ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        echo "⏱️  CURRENT SESSION"
        echo "──────────────────────────────────────────────────────────"
        echo "Uptime: ${hours}h ${minutes}m ${seconds}s"
        echo ""
        
        if [ -f "$UPTIME_JSON" ]; then
            echo "📊 LIFETIME STATISTICS"
            echo "──────────────────────────────────────────────────────────"
            grep -o '"[^"]*": [^,}]*' "$UPTIME_JSON" | while read line; do
                echo "  $line"
            done
            echo ""
        fi
        
        echo "📈 DAILY TRENDS"
        echo "──────────────────────────────────────────────────────────"
        if [ -f "$HOURLY_LOG" ]; then
            tail -20 "$HOURLY_LOG" | head -10
        else
            echo "  No hourly data yet"
        fi
        
        echo ""
        
    }
}

# Generate daily report
generate_daily_report() {
    local report_file="$KIOSK_DIR/uptime_report_$(date +%Y%m%d).txt"
    
    {
        echo "Daily Uptime Report - $(date '+%Y-%m-%d')"
        echo "================================================"
        echo ""
        show_stats
        echo ""
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    } > "$report_file"
    
    echo "Report saved: $report_file"
    cat "$report_file"
}

# Cleanup old uptime data
cleanup_old_data() {
    find "$KIOSK_DIR" -name "uptime_report_*.txt" -mtime +30 -delete
    echo "Cleaned up uptime data older than 30 days"
}

# Cleanup
trap 'exit 0' SIGTERM SIGINT

# Handle commands
case "${1:-stats}" in
    stats)
        show_stats
        ;;
    boot)
        record_boot
        ;;
    crash)
        record_crash "$2" "$3"
        ;;
    hourly)
        generate_hourly_report
        ;;
    daily)
        generate_daily_report
        ;;
    cleanup)
        cleanup_old_data
        ;;
    *)
        echo "Usage: $0 {stats|boot|crash|hourly|daily|cleanup}"
        echo ""
        echo "Commands:"
        echo "  stats              - Show uptime statistics"
        echo "  boot               - Record a boot event"
        echo "  crash APP REASON   - Record a crash"
        echo "  hourly             - Generate hourly report"
        echo "  daily              - Generate daily report"
        echo "  cleanup            - Clean old data"
        ;;
esac
