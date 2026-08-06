#!/system/bin/sh
# Log Rotation & Management Utilities
# Prevents unbounded log growth, keeps 7-day history

set -u

HOME_DIR="/data/data/com.termux/files/home"
KIOSK_DIR="/sdcard/Kiosk"
MAX_LOG_SIZE=10485760  # 10MB
KEEP_DAYS=7

# Log files to manage
LOG_FILES=(
    "$HOME_DIR/boot_orchestrator.log"
    "$HOME_DIR/kiosk_watchdog.log"
    "$HOME_DIR/network_monitor.log"
    "$HOME_DIR/fullscreen_enforcer.log"
    "$HOME_DIR/download_scheduler.log"
    "$HOME_DIR/volume_guard.log"
    "$HOME_DIR/watchdog.log"
    "$HOME_DIR/service_monitor.log"
    "$HOME_DIR/crash_analytics.log"
    "$KIOSK_DIR/crash_summary.txt"
)

# Get file size in bytes
get_file_size() {
    if [ -f "$1" ]; then
        stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Rotate a single log file
rotate_log() {
    local log_file=$1
    local base_name=$(basename "$log_file")
    local dir=$(dirname "$log_file")
    
    if [ ! -f "$log_file" ]; then
        return
    fi
    
    local size=$(get_file_size "$log_file")
    
    if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local rotated="${log_file}.${timestamp}"
        
        mv "$log_file" "$rotated"
        touch "$log_file"
        
        # Compress old log
        if command -v gzip >/dev/null 2>&1; then
            gzip "$rotated" &
        fi
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Rotated $base_name (size: $((size/1024/1024))MB)"
    fi
}

# Cleanup old logs (keep only 7 days)
cleanup_old_logs() {
    local timestamp=$(date '+%Y-%m-%d')
    
    echo "[$timestamp $(date +%H:%M:%S)] [INFO] Cleaning logs older than $KEEP_DAYS days..."
    
    for log_file in "${LOG_FILES[@]}"; do
        local dir=$(dirname "$log_file")
        local base_name=$(basename "$log_file")
        
        if [ -d "$dir" ]; then
            # Remove old rotated/gzipped logs
            find "$dir" -name "${base_name}.*" -mtime +$KEEP_DAYS -delete 2>/dev/null
            find "$dir" -name "${base_name}.*.gz" -mtime +$KEEP_DAYS -delete 2>/dev/null
        fi
    done
    
    echo "[$timestamp $(date +%H:%M:%S)] [INFO] Cleanup complete"
}

# Show log statistics
show_stats() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              LOG FILE STATISTICS                           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local total_size=0
    
    for log_file in "${LOG_FILES[@]}"; do
        if [ -f "$log_file" ]; then
            local size=$(get_file_size "$log_file")
            local size_mb=$((size / 1024 / 1024))
            local size_kb=$((size / 1024))
            
            if [ "$size_mb" -gt 0 ]; then
                echo "  $(basename "$log_file"): ${size_mb}MB"
            else
                echo "  $(basename "$log_file"): ${size_kb}KB"
            fi
            
            total_size=$((total_size + size))
        fi
    done
    
    echo ""
    echo "Total log size: $((total_size / 1024 / 1024))MB"
    echo ""
}

# Main rotation loop (can be called by cron or as daemon)
main_loop() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Starting log rotation daemon"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Max log size: $((MAX_LOG_SIZE / 1024 / 1024))MB"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Keep logs: $KEEP_DAYS days"
    
    while true; do
        # Rotate logs every hour
        for log_file in "${LOG_FILES[@]}"; do
            rotate_log "$log_file"
        done
        
        # Cleanup every 24 hours (at midnight)
        local current_hour=$(date +%H)
        if [ "$current_hour" = "00" ]; then
            cleanup_old_logs
        fi
        
        # Wait 1 hour
        sleep 3600
    done
}

# Handle signal
cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Log rotation daemon shutting down"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Command handling
case "${1:-stats}" in
    daemon)
        main_loop
        ;;
    rotate)
        echo "Rotating all log files..."
        for log_file in "${LOG_FILES[@]}"; do
            rotate_log "$log_file"
        done
        echo "Done"
        ;;
    cleanup)
        cleanup_old_logs
        ;;
    stats)
        show_stats
        ;;
    daemon)
        main_loop
        ;;
    *)
        # Default: run as daemon (most useful when called from boot chain)
        main_loop
        ;;
esac
