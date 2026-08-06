#!/system/bin/sh
#
# NETWORK MONITOR & FALLBACK SERVICE v1.0
# Monitors network connectivity and automatically switches between:
# - NewPipe (online mode) when network available
# - Just Player (offline videos) when network unavailable
#

set -eu

# ============================================================================
# CONFIGURATION
# ============================================================================

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:$PATH

LOG_DIR="/data/data/com.termux/files/home"
NETWORK_LOG="$LOG_DIR/network_monitor.log"

if mkdir -p /sdcard/Kiosk 2>/dev/null && touch /sdcard/Kiosk/.write_test 2>/dev/null; then
    KIOSK_DIR="/sdcard/Kiosk"
    rm -f /sdcard/Kiosk/.write_test
else
    KIOSK_DIR="$LOG_DIR"
fi

NETWORK_STATE="$KIOSK_DIR/network_state.txt"
PARENT_MODE_VAR="$KIOSK_DIR/parent_mode.txt"
CHECK_INTERVAL=5  # Check network every 5 seconds
NETWORK_TIMEOUT=3  # Timeout for network check

# Track state
LAST_STATUS="unknown"
STATUS_CHANGED=false

# ============================================================================
# LOGGING
# ============================================================================

exec 1>>"$NETWORK_LOG" 2>&1
echo "" >> "$NETWORK_LOG"
echo "===============================================" >> "$NETWORK_LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] NETWORK MONITOR STARTED" >> "$NETWORK_LOG"
echo "===============================================" >> "$NETWORK_LOG"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $1"; }

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper "$@"
}

# ============================================================================
# NETWORK DETECTION
# ============================================================================

check_network_available() {
    # Method 1: Ping public DNS
    if ping -c 1 -W $NETWORK_TIMEOUT 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    
    # Method 2: Check DNS resolution
    if nslookup youtube.com >/dev/null 2>&1; then
        return 0
    fi
    
    # Method 3: Check network interfaces
    if ip route show | grep -q "via"; then
        return 0
    fi
    
    # Method 4: Check connectivity property
    CONNECTIVITY=$(kiosk_helper read-setting global connectivity_change 2>/dev/null || echo 0)
    if [ -n "$CONNECTIVITY" ] && [ "$CONNECTIVITY" != "0" ]; then
        return 0
    fi
    
    return 1
}

get_network_status() {
    if check_network_available; then
        echo "ONLINE"
        return 0
    else
        echo "OFFLINE"
        return 1
    fi
}

is_parent_mode() {
    if [ -f "$PARENT_MODE_VAR" ]; then
        local mode=$(cat "$PARENT_MODE_VAR" 2>/dev/null)
        [ "$mode" = "true" ] && return 0
    fi
    return 1
}

# ============================================================================
# CONTENT SWITCHING
# ============================================================================

get_online_url() {
    local playlist_file="/sdcard/Kiosk/online_playlist.json"
    
    if [ -f "$playlist_file" ]; then
        local urls=$(grep -o -E 'https://www.youtube.com/watch\?v=[a-zA-Z0-9_-]{11}' "$playlist_file" 2>/dev/null || true)
        if [ -n "$urls" ]; then
            local count=$(echo "$urls" | wc -l)
            local random_idx=$(( (RANDOM % count) + 1 ))
            echo "$urls" | sed -n "${random_idx}p"
            return 0
        fi
    fi
    
    echo "https://www.youtube.com/watch?v=2dDpryw3z5w"
}

switch_to_newpipe() {
    # Network recovery only restores NewPipe UI — autoplay is Termux:Boot only
    log_info "Switching to NewPipe UI (online mode; no re-autoplay)..."

    am force-stop com.brouken.player 2>/dev/null || true
    sleep 1

    am start -n org.schabi.newpipe/.MainActivity >/dev/null 2>&1 && {
        log_success "NewPipe MainActivity restored"
        return 0
    }

    log_error "Failed to launch NewPipe"
    return 1
}

switch_to_offline_video() {
    log_info "Switching to offline video (network unavailable)..."
    
    # Kill NewPipe first
    am force-stop org.schabi.newpipe 2>/dev/null || true
    sleep 1
    
    # Kill existing player
    am force-stop com.brouken.player 2>/dev/null || true
    sleep 2
    
    # Find random offline video
    local files=$(find /sdcard/Movies/ -name "*.mp4" 2>/dev/null | head -50 || true)
    if [ -n "$files" ]; then
        local count=$(echo "$files" | wc -l)
        local random_idx=$(( (RANDOM % count) + 1 ))
        local file_path=$(echo "$files" | sed -n "${random_idx}p")
        
        if [ -n "$file_path" ] && [ -f "$file_path" ]; then
            log_info "Launching offline video: $file_path"
            
            am start \
                -n com.brouken.player/.PlayerActivity \
                -a android.intent.action.VIEW \
                -d "file://$file_path" \
                -t "video/*" \
                -e com.brouken.player.fullscreen "true" \
                >/dev/null 2>&1 && {
                log_success "Offline video launched in fullscreen"
                return 0
            }
        fi
    fi
    
    log_error "No offline videos available, launching GCompris..."
    am start -n net.gcompris.full/net.gcompris.GComprisActivity >/dev/null 2>&1
    return 1
}

# ============================================================================
# STATE PERSISTENCE
# ============================================================================

save_network_state() {
    local status="$1"
    if touch "$NETWORK_STATE" 2>/dev/null; then
        echo "$status" > "$NETWORK_STATE" 2>/dev/null || true
    fi
}

get_current_app() {
    kiosk_helper get-foreground 2>/dev/null || echo "unknown"
}

# ============================================================================
# MAIN MONITORING LOOP
# ============================================================================

log_success "Network monitor initialized. Starting monitoring loop..."

LAST_SWITCH_TIME=0

while true; do
    # Skip checks if screen is off to conserve battery and CPU
    if [ "$(kiosk_helper is-screen-on 2>/dev/null)" = "false" ]; then
        sleep 10
        continue
    fi

    # Skip if parent mode active
    if is_parent_mode; then
        sleep 5
        continue
    fi

    # Determine dynamic interval based on power mode
    power_state="NORMAL"
    if [ -f "$LOG_DIR/.power_state" ]; then
        power_state=$(cat "$LOG_DIR/.power_state" 2>/dev/null || echo "NORMAL")
    fi

    current_interval=$CHECK_INTERVAL
    if [ "$power_state" = "LOW_POWER" ] || [ "$power_state" = "SLEEP" ]; then
        current_interval=60
    elif [ "$power_state" = "CRITICAL" ]; then
        current_interval=120
    fi
    
    # Get current network status
    CURRENT_STATUS=$(get_network_status || true)
    
    # Save state
    save_network_state "$CURRENT_STATUS"
    
    # Check if status changed
    if [ "$CURRENT_STATUS" != "$LAST_STATUS" ]; then
        STATUS_CHANGED=true
        LAST_STATUS="$CURRENT_STATUS"
    else
        STATUS_CHANGED=false
    fi
    
    # Get current foreground app
    CURRENT_APP=$(get_current_app || echo "unknown")
    
    # Handle status changes
    if [ "$STATUS_CHANGED" = "true" ]; then
        log_warn "Network status changed: $LAST_STATUS → $CURRENT_STATUS"
        
        # Avoid switching too frequently (debounce 30 seconds)
        CURRENT_TIME=$(date +%s)
        TIME_SINCE_LAST_SWITCH=$((CURRENT_TIME - LAST_SWITCH_TIME))
        
        if [ $TIME_SINCE_LAST_SWITCH -gt 30 ]; then
            if [ "$CURRENT_STATUS" = "ONLINE" ]; then
                log_info "Network is back, switching to NewPipe..."
                if switch_to_newpipe; then
                    LAST_SWITCH_TIME=$CURRENT_TIME
                    sleep 2  # Wait for app to start
                fi
            else
                log_warn "Network lost, switching to offline video..."
                if switch_to_offline_video; then
                    LAST_SWITCH_TIME=$CURRENT_TIME
                    sleep 2  # Wait for app to start
                fi
            fi
        else
            log_info "Debounce: skipping switch (only ${TIME_SINCE_LAST_SWITCH}s since last switch)"
        fi
    fi
    
    # Verify current state makes sense
    if [ "$CURRENT_STATUS" = "ONLINE" ]; then
        # Should be running NewPipe or GCompris
        if [ "$CURRENT_APP" = "com.brouken.player" ]; then
            log_warn "Online but running offline player, switching to NewPipe..."
            LAST_SWITCH_TIME=$(date +%s)
            switch_to_newpipe || true
        fi
    else
        # Should NOT be running NewPipe if offline
        if [ "$CURRENT_APP" = "org.schabi.newpipe" ]; then
            log_warn "Offline but running NewPipe, switching to offline video..."
            LAST_SWITCH_TIME=$(date +%s)
            switch_to_offline_video || true
        fi
    fi
    
    # Sleep before next check
    sleep $current_interval
done

log_error "Network monitor loop terminated unexpectedly"
