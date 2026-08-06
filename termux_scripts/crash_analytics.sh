#!/system/bin/sh
# Crash Analytics & Tracking System
# Collects crash data, analyzes patterns, detects recurring issues

set -u

HOME_DIR="/data/data/com.termux/files/home"
if mkdir -p /sdcard/Kiosk 2>/dev/null && touch /sdcard/Kiosk/.write_test 2>/dev/null; then
    KIOSK_DIR="/sdcard/Kiosk"
    rm -f /sdcard/Kiosk/.write_test
else
    KIOSK_DIR="$HOME_DIR"
fi
CRASH_LOG="$KIOSK_DIR/crash_analytics.json"
CRASH_SUMMARY="$KIOSK_DIR/crash_summary.txt"

# Initialize crash log
init_crash_log() {
    if [ ! -f "$CRASH_LOG" ]; then
        mkdir -p "$KIOSK_DIR"
        cat > "$CRASH_LOG" << 'EOF'
{
  "version": "2.0",
  "crashes": [],
  "statistics": {
    "total_crashes": 0,
    "recovery_rate": 100,
    "avg_recovery_time_ms": 0,
    "most_crashed_app": "none",
    "last_crash": null
  }
}
EOF
    fi
}

# Log a crash event
log_crash() {
    local app=$1
    local reason=$2
    local recovery_action=$3
    local recovery_time=${4:-0}
    local attempt=${5:-1}
    local success=${6:-"true"}
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local hour=$(date +%H)
    local day=$(date +%a)
    
    # Append to crash log (simplified JSON append)
    # In production, would use jq for proper JSON manipulation
    echo "CRASH_EVENT|$timestamp|$app|$reason|$recovery_action|$recovery_time|$attempt|$success|$hour|$day" >> "${CRASH_LOG}.raw"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Crash logged: app=$app reason=$reason recovery_time=${recovery_time}ms" | tee -a "$HOME_DIR/crash_analytics.log"
}

# Analyze crash patterns
analyze_patterns() {
    if [ ! -f "${CRASH_LOG}.raw" ]; then
        return
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    {
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║          CRASH ANALYTICS REPORT - $timestamp          ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        echo "📊 CRASH STATISTICS"
        echo "──────────────────────────────────────────────────────────"
        local total=$(wc -l < "${CRASH_LOG}.raw" 2>/dev/null || echo 0)
        echo "Total Crashes (24h): $total"
        
        echo ""
        echo "🎯 TOP CRASHED APPS"
        echo "──────────────────────────────────────────────────────────"
        cut -d'|' -f3 "${CRASH_LOG}.raw" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | while read count app; do
            echo "  $app: $count crashes"
        done || echo "  No crashes recorded"
        
        echo ""
        echo "💥 CRASH REASONS"
        echo "──────────────────────────────────────────────────────────"
        cut -d'|' -f4 "${CRASH_LOG}.raw" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | while read count reason; do
            echo "  $reason: $count times"
        done || echo "  No crash reasons recorded"
        
        echo ""
        echo "⏰ CRASHES BY HOUR"
        echo "──────────────────────────────────────────────────────────"
        cut -d'|' -f9 "${CRASH_LOG}.raw" 2>/dev/null | sort | uniq -c | sort -rn | while read count hour; do
            echo "  ${hour}:00 - $count crashes"
        done || echo "  No hourly data"
        
        echo ""
        echo "📈 RECOVERY ANALYSIS"
        echo "──────────────────────────────────────────────────────────"
        local successful=$(grep "|true|" "${CRASH_LOG}.raw" 2>/dev/null | wc -l)
        local total_attempts=$(wc -l < "${CRASH_LOG}.raw" 2>/dev/null || echo 0)
        if [ "$total_attempts" -gt 0 ]; then
            local recovery_rate=$((successful * 100 / total_attempts))
            echo "Recovery Rate: $recovery_rate% ($successful/$total_attempts)"
        else
            echo "Recovery Rate: 100% (No crashes)"
        fi
        
        echo ""
        echo "⚠️  ALERTS"
        echo "──────────────────────────────────────────────────────────"
        
        # Check for crash spike
        local recent=$(grep "$(date -d '-1 hour' '+%Y-%m-%dT%H' 2>/dev/null || date -u '+%Y-%m-%dT%H')" "${CRASH_LOG}.raw" 2>/dev/null | wc -l)
        if [ "$recent" -gt 5 ]; then
            echo "⚠️  HIGH CRASH RATE: $recent crashes in last hour"
        fi
        
        # Check for specific app repeated crashes
        local most_crashed=$(cut -d'|' -f3 "${CRASH_LOG}.raw" 2>/dev/null | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
        local crash_count=$(cut -d'|' -f3 "${CRASH_LOG}.raw" 2>/dev/null | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')
        if [ "$crash_count" -gt 3 ]; then
            echo "⚠️  RECURRING ISSUE: $most_crashed crashed $crash_count times"
        fi
        
        echo ""
        
    } > "$CRASH_SUMMARY"
    
    cat "$CRASH_SUMMARY"
}

# Generate daily report
generate_daily_report() {
    local report_file="$KIOSK_DIR/crash_report_$(date +%Y%m%d).txt"
    analyze_patterns > "$report_file"
    echo "Report saved to: $report_file"
}

# Cleanup old crash data (keep 7 days)
cleanup_old_crashes() {
    find "$KIOSK_DIR" -name "crash_report_*.txt" -mtime +7 -delete 2>/dev/null
    find "$HOME_DIR" -name "*.crash.*" -mtime +7 -delete 2>/dev/null
    echo "Cleaned up crash data older than 7 days"
}

# Main
init_crash_log

case "${1:-analyze}" in
    log)
        log_crash "$2" "$3" "$4" "${5:-0}" "${6:-1}" "${7:-true}"
        ;;
    analyze)
        analyze_patterns
        ;;
    report)
        generate_daily_report
        ;;
    cleanup)
        cleanup_old_crashes
        ;;
    *)
        echo "Usage: $0 {log|analyze|report|cleanup}"
        echo "  log <app> <reason> <action> [time] [attempt] [success]"
        echo "  analyze  - Show crash analysis"
        echo "  report   - Generate daily report"
        echo "  cleanup  - Remove old crash data"
        ;;
esac
