#!/system/bin/sh
# Network Quality Monitoring
# Enhanced network monitoring with signal strength, latency, packet loss

set -u

HOME_DIR="/data/data/com.termux/files/home"
KIOSK_DIR="/sdcard/Kiosk"
LOG_FILE="$HOME_DIR/network_quality.log"
QUALITY_REPORT="$KIOSK_DIR/network_quality.json"
SIGNAL_THRESHOLD_POOR=30
SIGNAL_THRESHOLD_GOOD=60
LATENCY_THRESHOLD_POOR=200
LATENCY_THRESHOLD_GOOD=50

# Logging
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper "$@"
}

# Get WiFi signal strength
get_signal_strength() {
    kiosk_helper get-wifi-rssi 2>/dev/null || echo "-100"
}

# Calculate signal quality percentage
signal_to_quality() {
    local rssi=$1
    
    # Ensure it's treated as a number
    if ! echo "$rssi" | grep -qE "^-?[0-9]+$"; then
        echo "0"
        return
    fi
    
    # RSSI typical range is -50 (excellent) to -100 (poor/unusable)
    # We map it to 0-100% using: Quality = 2 * (RSSI + 100)
    local quality=$((2 * (rssi + 100)))
    
    if [ "$quality" -lt 0 ]; then
        echo "0"
    elif [ "$quality" -gt 100 ]; then
        echo "100"
    else
        echo "$quality"
    fi
}

# Get network latency
get_latency() {
    local host=${1:-8.8.8.8}
    
    if ! command -v ping >/dev/null 2>&1; then
        echo "0"
        return
    fi
    
    # Try ping with timeout
    local result=$(ping -c 1 -W 2 "$host" 2>/dev/null | grep "time=" | head -1)
    
    if [ -n "$result" ]; then
        echo "$result" | grep -o "time=[0-9]*" | cut -d= -f2
    else
        echo "0"
    fi
}

# Get packet loss
get_packet_loss() {
    local host=${1:-8.8.8.8}
    
    if ! command -v ping >/dev/null 2>&1; then
        echo "0"
        return
    fi
    
    local result=$(ping -c 5 -W 1 "$host" 2>/dev/null | grep "% packet loss")
    
    if [ -n "$result" ]; then
        echo "$result" | grep -o "[0-9]*%" | head -1 | tr -d '%'
    else
        echo "0"
    fi
}

# Determine network quality
get_network_quality() {
    local signal=$1
    local latency=$2
    local packet_loss=$3
    
    # Quality calculation
    if [ "$packet_loss" -gt 20 ]; then
        echo "POOR"
        return
    fi
    
    if [ "$signal" -lt "$SIGNAL_THRESHOLD_POOR" ]; then
        echo "POOR"
        return
    fi
    
    if [ "$latency" -gt "$LATENCY_THRESHOLD_POOR" ]; then
        echo "FAIR"
        return
    fi
    
    if [ "$signal" -lt "$SIGNAL_THRESHOLD_GOOD" ] || [ "$latency" -gt "$LATENCY_THRESHOLD_GOOD" ]; then
        echo "GOOD"
        return
    fi
    
    echo "EXCELLENT"
}

# Monitor network quality
monitor_quality() {
    log_msg "Starting Network Quality Monitor"
    
    local consecutive_poor=0
    local consecutive_good=0
    
    while true; do
        local signal=$(get_signal_strength)
        local quality=$(signal_to_quality "$signal")
        local latency=$(get_latency "8.8.8.8")
        local packet_loss=$(get_packet_loss "8.8.8.8")
        local network_quality=$(get_network_quality "$quality" "$latency" "$packet_loss")
        
        log_msg "Quality: $network_quality | Signal: $quality% | Latency: ${latency}ms | Loss: ${packet_loss}%"
        
        # Detect network quality changes
        case "$network_quality" in
            POOR|FAIR)
                consecutive_poor=$((consecutive_poor + 1))
                consecutive_good=0
                
                if [ "$consecutive_poor" -eq 3 ]; then
                    log_msg "⚠️  ALERT: Poor network quality detected (3 consecutive checks)"
                    # Could trigger actions here
                fi
                ;;
            GOOD|EXCELLENT)
                consecutive_good=$((consecutive_good + 1))
                consecutive_poor=0
                ;;
        esac
        
        # Save to report file
        cat > "$QUALITY_REPORT" << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "quality": "$network_quality",
  "signal_strength_percent": $quality,
  "latency_ms": $latency,
  "packet_loss_percent": $packet_loss,
  "consecutive_poor_checks": $consecutive_poor,
  "consecutive_good_checks": $consecutive_good
}
EOF
        
        # Check every 10 seconds
        sleep 10
    done
}

# Show quality report
show_report() {
    if [ -f "$QUALITY_REPORT" ]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║          NETWORK QUALITY REPORT                           ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Parse and display (simplified)
        cat "$QUALITY_REPORT" | grep -o '"[^"]*": [^,}]*' | while read line; do
            echo "  $line"
        done
        
        echo ""
    else
        echo "No quality report available yet"
    fi
}

# Cleanup
cleanup() {
    log_msg "Network Quality Monitor shutting down"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main
case "${1:-monitor}" in
    monitor)
        monitor_quality
        ;;
    report)
        show_report
        ;;
    signal)
        echo "Signal strength: $(get_signal_strength) RSSI"
        ;;
    latency)
        echo "Latency: $(get_latency 8.8.8.8)ms"
        ;;
    loss)
        echo "Packet loss: $(get_packet_loss 8.8.8.8)%"
        ;;
    *)
        show_report
        ;;
esac
