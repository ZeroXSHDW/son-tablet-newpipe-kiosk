#!/system/bin/sh
#
# ENHANCED BOOT ORCHESTRATOR v2.0
# Complete rewrite with:
# - Multiple boot attempts with exponential backoff
# - Comprehensive health checking
# - Phase-aware content selection
# - Robust error handling and recovery
# - Centralized logging for diagnostics
#

set -eu

# ============================================================================
# CONFIGURATION & LOGGING
# ============================================================================

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib

LOG_DIR="/data/data/com.termux/files/home"
BOOT_LOG="$LOG_DIR/boot_orchestrator.log"
HEALTH_CHECK_FILE="/sdcard/Kiosk/boot_health.txt"
STATE_FILE="/sdcard/Kiosk/boot_state.json"

# Ensure directories exist
mkdir -p "$LOG_DIR"
mkdir -p "/sdcard/Kiosk"

# Initialize logging
exec 1>>"$BOOT_LOG" 2>&1
echo "" >> "$BOOT_LOG"
echo "===============================================" >> "$BOOT_LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] BOOT ORCHESTRATOR STARTING" >> "$BOOT_LOG"
echo "===============================================" >> "$BOOT_LOG"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $1"; }

# ============================================================================
# HEALTH CHECKS
# ============================================================================

check_system_ready() {
    log_info "Performing system readiness checks..."
    
    # Check if system server is responding
    if ! pgrep -f "system_server" >/dev/null 2>&1; then
        log_warn "system_server not running yet"
        return 1
    fi
    
    # Check if we can query package manager
    if ! pm list packages >/dev/null 2>&1; then
        log_warn "Package manager not ready"
        return 1
    fi
    
    log_success "System is ready"
    return 0
}

check_required_apps() {
    log_info "Checking required applications..."
    local required_apps=(
        "org.schabi.newpipe"
        "com.brouken.player"
        "net.gcompris.full"
        "com.arlosoft.macrodroid"
    )
    
    local missing=0
    for app in "${required_apps[@]}"; do
        if ! pm list packages | grep -q "^package:$app$"; then
            log_warn "Missing required app: $app"
            ((missing++))
        fi
    done
    
    if [ $missing -eq 0 ]; then
        log_success "All required apps present"
        return 0
    else
        log_warn "$missing required apps are missing"
        return 1
    fi
}

check_network() {
    log_info "Checking network connectivity..."
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        log_success "Network is available"
        return 0
    else
        log_warn "Network is not available (will use offline mode)"
        return 1
    fi
}

# ============================================================================
# BYPASS & WAKE LOCK
# ============================================================================

setup_awbms_bypass() {
    log_info "Setting up AWBMS bypass..."
    
    CURRENT_UID=$(id -u)
    IS_TERMUX=false
    IS_MACRODROID=false
    
    if [ "$CURRENT_UID" -ne 2000 ] && [ "$CURRENT_UID" -ne 0 ]; then
        CURRENT_PACKAGES=$(pm list packages --uid "$CURRENT_UID" 2>/dev/null || true)
        if echo "$CURRENT_PACKAGES" | grep -q "com.termux"; then
            IS_TERMUX=true
        elif echo "$CURRENT_PACKAGES" | grep -q "com.arlosoft.macrodroid"; then
            IS_MACRODROID=true
        fi
    fi
    
    if [ "$IS_TERMUX" = "true" ]; then
        log_info "Running as Termux. Executing AWBMS bypass for com.termux..."
        export CLASSPATH=/data/local/tmp/bypass.jar
        if app_process /data/local/tmp Bypass com.termux >/dev/null 2>&1; then
            log_success "AWBMS bypass executed for Termux"
        else
            log_warn "AWBMS bypass failed for Termux (may not be critical)"
        fi
    elif [ "$IS_MACRODROID" = "true" ]; then
        log_info "Running as MacroDroid. Executing AWBMS bypass..."
        export CLASSPATH=/data/local/tmp/bypass.jar
        if app_process /data/local/tmp Bypass com.arlosoft.macrodroid >/dev/null 2>&1; then
            log_success "AWBMS bypass executed for MacroDroid"
        else
            log_warn "AWBMS bypass failed for MacroDroid"
        fi
    fi
}

setup_wake_lock() {
    log_info "Acquiring wake lock..."
    if termux-wake-lock >/dev/null 2>&1; then
        log_success "Wake lock acquired"
    else
        log_warn "Could not acquire wake lock (may not be available)"
    fi
}

# ============================================================================
# DISPLAY & SYSTEM SETTINGS
# ============================================================================

configure_display() {
    log_info "Configuring display and system settings..."
    
    # Screen timeout: 10 minutes
    settings put system screen_off_timeout 600000 >/dev/null 2>&1 || true
    
    # Brightness: 180/255 (70%)
    settings put system screen_brightness 180 >/dev/null 2>&1 || true
    
    # Landscape orientation
    settings put system user_rotation 0 >/dev/null 2>&1 || true
    
    # Disable adaptive sleep
    settings put secure adaptive_sleep 0 >/dev/null 2>&1 || true
    
    # Manual brightness mode
    settings put system screen_brightness_mode 0 >/dev/null 2>&1 || true
    
    # Maintenance
    cmd activity idle-maintenance >/dev/null 2>&1 || true
    
    log_success "Display configured"
}

# ============================================================================
# BACKGROUND SERVICES
# ============================================================================

start_background_services() {
    log_info "Starting background services..."
    
    CURRENT_UID=$(id -u)
    IS_TERMUX=false
    
    if [ "$CURRENT_UID" -eq 0 ] || [ "$CURRENT_UID" -eq 2000 ]; then
        IS_TERMUX=true
    fi
    
    if [ "$IS_TERMUX" = "true" ]; then
        # Volume guard
        if ! pgrep -f "volume_guard.sh" >/dev/null 2>&1; then
            log_info "Starting volume_guard..."
            if [ -f "$HOME/volume_guard.sh" ]; then
                nohup /data/data/com.termux/files/usr/bin/bash "$HOME/volume_guard.sh" > "$LOG_DIR/volume_guard.log" 2>&1 &
                log_success "volume_guard started"
            else
                log_warn "volume_guard.sh not found"
            fi
        else
            log_info "volume_guard already running"
        fi
        
        # Network monitor (for NewPipe online/offline fallback)
        if ! pgrep -f "network_monitor.sh" >/dev/null 2>&1; then
            log_info "Starting network_monitor..."
            if [ -f "$HOME/network_monitor.sh" ]; then
                nohup /data/data/com.termux/files/usr/bin/bash "$HOME/network_monitor.sh" > "$LOG_DIR/network_monitor.log" 2>&1 &
                log_success "network_monitor started"
            else
                log_warn "network_monitor.sh not found"
            fi
        else
            log_info "network_monitor already running"
        fi
        
        # Fullscreen enforcer (ensures NewPipe stays fullscreen)
        if ! pgrep -f "fullscreen_enforcer.sh" >/dev/null 2>&1; then
            log_info "Starting fullscreen_enforcer..."
            if [ -f "$HOME/fullscreen_enforcer.sh" ]; then
                nohup /data/data/com.termux/files/usr/bin/bash "$HOME/fullscreen_enforcer.sh" > "$LOG_DIR/fullscreen_enforcer.log" 2>&1 &
                log_success "fullscreen_enforcer started"
            else
                log_warn "fullscreen_enforcer.sh not found"
            fi
        else
            log_info "fullscreen_enforcer already running"
        fi
        
        # Download scheduler (for 2am VODAFONE video downloads)
        if ! pgrep -f "download_scheduler.sh" >/dev/null 2>&1; then
            log_info "Starting download_scheduler..."
            if [ -f "$HOME/download_scheduler.sh" ]; then
                nohup /data/data/com.termux/files/usr/bin/bash "$HOME/download_scheduler.sh" > "$LOG_DIR/download_scheduler.log" 2>&1 &
                log_success "download_scheduler started"
            else
                log_warn "download_scheduler.sh not found"
            fi
        else
            log_info "download_scheduler already running"
        fi
        
        # WiFi sync daemon
        if ! pgrep -f "sync_wifi.py" >/dev/null 2>&1; then
            log_info "Starting sync_wifi daemon..."
            if [ -f "$HOME/sync_wifi.py" ]; then
                nohup /data/data/com.termux/files/usr/bin/sh -c '
                while true; do
                    echo "[$(date)] Starting sync_wifi.py" >> '"$LOG_DIR"'/sync_wifi.log
                    /data/data/com.termux/files/usr/bin/python3 -u '"$HOME"'/sync_wifi.py >> '"$LOG_DIR"'/sync_wifi.log 2>&1
                    echo "[$(date)] sync_wifi.py finished. Sleeping 4 hours..." >> '"$LOG_DIR"'/sync_wifi.log
                    sleep 14400
                done
                ' > "$LOG_DIR/sync_wifi_daemon.log" 2>&1 &
                log_success "sync_wifi daemon started"
            else
                log_warn "sync_wifi.py not found"
            fi
        else
            log_info "sync_wifi already running"
        fi
    fi
}

# ============================================================================
# CONTENT SELECTION BY PHASE
# ============================================================================

get_current_phase() {
    local hour=$(date +%H | sed 's/^0//')
    
    # 06:00 - 07:00: Morning Lessons
    if [ "$hour" -ge 6 ] && [ "$hour" -lt 7 ]; then
        echo "MORNING"
    # 07:00 - 19:00: Learning Phase
    elif [ "$hour" -ge 7 ] && [ "$hour" -lt 19 ]; then
        echo "LEARNING"
    # 19:00 - 20:30: Relaxing Phase
    elif [ "$hour" -ge 19 ] && [ "$hour" -lt 20 ]; then
        echo "RELAXING"
    # 20:30 - 06:00: Sleep Phase
    else
        echo "SLEEP"
    fi
}

get_online_url() {
    local playlist_file="/sdcard/Kiosk/online_playlist.json"
    
    if [ -f "$playlist_file" ]; then
        local urls=$(grep -o -E 'https://www.youtube.com/watch\?v=[a-zA-Z0-9_-]{11}' "$playlist_file" || true)
        if [ -n "$urls" ]; then
            local count=$(echo "$urls" | wc -l)
            local random_idx=$(( (RANDOM % count) + 1 ))
            echo "$urls" | sed -n "${random_idx}p"
            return 0
        fi
    fi
    
    # Fallback URL
    echo "https://www.youtube.com/watch?v=2dDpryw3z5w"
}

play_offline_video() {
    log_info "Attempting to play offline video..."
    
    local files=$(find /sdcard/Movies/ -name "*.mp4" 2>/dev/null || true)
    if [ -n "$files" ]; then
        local count=$(echo "$files" | wc -l)
        local random_idx=$(( (RANDOM % count) + 1 ))
        local file_path=$(echo "$files" | sed -n "${random_idx}p")
        
        log_info "Playing offline video: $file_path"
        am start -n com.brouken.player/.PlayerActivity \
            -a android.intent.action.VIEW \
            -d "file://$file_path" \
            -t "video/*" \
            -e com.brouken.player.uri "file://$file_path" \
            -e com.brouken.player.fullscreen "true" \
            >/dev/null 2>&1 && return 0
        
        log_error "Failed to start offline video playback"
        return 1
    else
        log_warn "No offline videos found"
        return 1
    fi
}

play_online_video() {
    log_info "Attempting to play online video..."
    
    local url="$1"
    log_info "Playing online video: $url"
    
    # Force-stop any running instances for clean start
    am force-stop org.schabi.newpipe 2>/dev/null || true
    sleep 1
    
    # Launch with fullscreen enforcement
    am start \
        -a android.intent.action.VIEW \
        -d "$url" \
        -n org.schabi.newpipe/.RouterActivity \
        -e fullscreen "true" \
        >/dev/null 2>&1 && {
        log_success "NewPipe launched with fullscreen enforcement"
        return 0
    }
    
    log_error "Failed to start online video"
    return 1
}

play_gcompris() {
    log_info "Launching GCompris..."
    am start -n net.gcompris.full/net.gcompris.GComprisActivity >/dev/null 2>&1 && return 0
    log_error "Failed to launch GCompris"
    return 1
}

launch_content_for_phase() {
    local phase="$1"
    log_info "Launching content for phase: $phase"
    
    case "$phase" in
        MORNING)
            log_info "Morning phase: Looking for educational videos..."
            if play_offline_video; then
                return 0
            fi
            ;;
        LEARNING)
            log_info "Learning phase: Attempting online video..."
            if check_network; then
                local url=$(get_online_url)
                if play_online_video "$url"; then
                    return 0
                fi
            fi
            log_warn "Online failed, falling back to offline..."
            if play_offline_video; then
                return 0
            fi
            ;;
        RELAXING)
            log_info "Relaxing phase: Playing calming content..."
            if play_offline_video; then
                return 0
            fi
            ;;
        SLEEP)
            log_info "Sleep phase: Playing sleep content..."
            if play_offline_video; then
                return 0
            fi
            ;;
    esac
    
    # Ultimate fallback
    log_warn "All content playback failed, launching GCompris..."
    play_gcompris && return 0
    
    log_error "All content launch attempts failed!"
    return 1
}

# ============================================================================
# BOOT EXECUTION WITH RETRY LOGIC
# ============================================================================

execute_boot_with_retry() {
    local max_retries=3
    local retry_count=0
    local retry_delay=5
    
    log_info "Starting boot sequence (max retries: $max_retries)..."
    
    while [ $retry_count -lt $max_retries ]; do
        log_info "Boot attempt $((retry_count + 1))/$max_retries"
        
        # Wait for system to stabilize
        sleep 15
        
        # Health checks
        if ! check_system_ready; then
            log_warn "System not ready yet, retrying..."
            ((retry_count++))
            sleep $((retry_delay * (retry_count)))
            continue
        fi
        
        # Configure system
        setup_awbms_bypass
        setup_wake_lock
        configure_display
        start_background_services
        
        # Launch content
        local phase=$(get_current_phase)
        if launch_content_for_phase "$phase"; then
            log_success "Boot sequence completed successfully!"
            
            # Record boot success
            cat > "$HEALTH_CHECK_FILE" <<EOF
{
    "status": "success",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "phase": "$phase",
    "boot_attempts": $((retry_count + 1))
}
EOF
            
            return 0
        fi
        
        log_warn "Content launch failed, retrying boot sequence..."
        ((retry_count++))
        sleep $((retry_delay * retry_count))
    done
    
    log_error "Boot sequence failed after $max_retries attempts"
    cat > "$HEALTH_CHECK_FILE" <<EOF
{
    "status": "failed",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "error": "All boot attempts exhausted",
    "boot_attempts": $max_retries
}
EOF
    
    return 1
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

execute_boot_with_retry
log_success "Boot orchestrator execution finished (exit code: $?)"
