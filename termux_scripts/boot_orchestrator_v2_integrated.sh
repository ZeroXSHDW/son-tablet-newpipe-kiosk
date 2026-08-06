#!/data/data/com.termux/files/usr/bin/bash
#
# NEWPIPE 24/7 BOOT v4 — Subscriptions + Fullscreen only
#

set +e

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:/system/xbin:/vendor/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib

LOG_DIR="$HOME"
BOOT_LOG="$LOG_DIR/boot_orchestrator.log"
KIOSK_DIR="/sdcard/Kiosk"
ORCH_LOCK_DIR="$LOG_DIR/.boot_orchestrator_v2.lock"
ORCH_LOCK_PID_FILE="$ORCH_LOCK_DIR/pid"
ORCH_LOCK_STATE_FILE="$ORCH_LOCK_DIR/state"
CORE_STACK_SERVICES=(
    "newpipe_24x7.sh"
    "fullscreen_enforcer.sh"
    "volume_guard.sh"
    "wallpaper_live.sh"
    "wifi_keepalive.sh"
    "download_scheduler.sh"
)
STACK_MONITOR_SERVICE="service_monitor.sh"
KIOSK_STACK_SUPERVISOR="${KIOSK_STACK_SUPERVISOR:-1}"
KIOSK_SUPERVISOR_INTERVAL="${KIOSK_SUPERVISOR_INTERVAL:-45}"
mkdir -p "$LOG_DIR/Kiosk" "$KIOSK_DIR" 2>/dev/null || true

exec 1>>"$BOOT_LOG" 2>&1
echo ""
echo "==============================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] NEWPIPE BOOT v4 SUBSCRIPTIONS+FULLSCREEN"
echo "==============================================="

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $1"; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"; }

# The config is the single schedule/volume/brightness authority. Refuse to
# start a partial stack when it is malformed; otherwise different daemons can
# silently fall back to different defaults.
if [ ! -f "$HOME/kiosk_config.sh" ]; then
    log_warn "Missing authoritative kiosk_config.sh — refusing startup"
    exit 1
fi
. "$HOME/kiosk_config.sh"
if ! kiosk_validate_config; then
    log_warn "Authoritative kiosk configuration failed validation — refusing startup"
    exit 1
fi

service_is_alive() {
    local needle="$1"
    local pidfile="$HOME/${needle%.sh}.pid"
    if type daemon_is_running >/dev/null 2>&1; then
        if daemon_is_running "$pidfile" "$needle"; then
            return 0
        fi
        rm -f "$pidfile" 2>/dev/null || true
    fi
    # If daemon metadata is unavailable, use the exact Termux process path.
    # Avoid pgrep -f here: the pgrep command line itself can contain the
    # searched script name and create a false healthy result.
    ps -ef 2>/dev/null | grep -F "bash $HOME/$needle" | grep -v grep >/dev/null 2>&1 && return 0
    return 1
}

core_services_running_count() {
    local count=0
    local s
    for s in "${CORE_STACK_SERVICES[@]}"; do
        service_is_alive "$s" && count=$((count + 1))
    done
    echo "$count"
}

stack_fully_running() {
    local running_count
    running_count="$(core_services_running_count)"
    [ "$running_count" -eq "${#CORE_STACK_SERVICES[@]}" ] || return 1
    service_is_alive "$STACK_MONITOR_SERVICE" || return 1
    return 0
}

stack_running() {
    local running_count
    running_count="$(core_services_running_count)"
    if [ "$running_count" -gt 0 ]; then
        return 0
    fi
    service_is_alive "$STACK_MONITOR_SERVICE"
}

acquire_boot_lock() {
    local stale_pid old live_cmd
    if [ -d "$ORCH_LOCK_DIR" ]; then
        if [ -f "$ORCH_LOCK_PID_FILE" ]; then
            stale_pid=$(cat "$ORCH_LOCK_PID_FILE" 2>/dev/null | tr -d '\r\n ')
            # A PID can be reused after Android/Termux restarts.  `kill -0`
            # alone is therefore unsafe: it can report an unrelated process
            # as the old owner (or return EPERM for another UID).  Confirm
            # the exact orchestrator command line before treating the lock as
            # live; otherwise clear the stale lock and recover at boot.
            live_cmd=$(ps -ef 2>/dev/null | awk -v pid="$stale_pid" '$2 == pid {print}')
            if [ -n "$stale_pid" ] && printf '%s\n' "$live_cmd" \
                    | grep -F "boot_orchestrator_v2_integrated.sh" >/dev/null 2>&1; then
                log_warn "Boot orchestrator already active (pid=$stale_pid); skip"
                exit 0
            fi
        fi
        rm -rf "$ORCH_LOCK_DIR" 2>/dev/null || true
    fi

    mkdir -p "$ORCH_LOCK_DIR" 2>/dev/null || true
    echo "$$" > "$ORCH_LOCK_PID_FILE" 2>/dev/null || true
    echo "starting" > "$ORCH_LOCK_STATE_FILE" 2>/dev/null || true
    trap 'rm -f "$ORCH_LOCK_PID_FILE" 2>/dev/null || true; rm -f "$ORCH_LOCK_STATE_FILE" 2>/dev/null || true; rmdir "$ORCH_LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
}

normalize_duplicate_processes() {
    local needle="$1"
    local pids pid keep
    pids=$(ps -ef 2>/dev/null | grep -F "bash $HOME/$needle" | grep -v "grep" | awk '{print $2}' | tr '\n' ' ')
    [ -z "$pids" ] && { rm -f "$HOME/${needle%.sh}.pid" 2>/dev/null || true; return; }
    keep=$(echo "$pids" | tr ' ' '\n' | tail -n 1)
    for pid in $pids; do
        [ -n "$pid" ] || continue
        [ "$pid" = "$keep" ] && continue
        kill -9 "$pid" 2>/dev/null || true
    done
    echo "$keep" > "$HOME/${needle%.sh}.pid" 2>/dev/null || true
}

killer() {
    local s
    for s in volume_guard.sh fullscreen_enforcer.sh wallpaper_live.sh newpipe_24x7.sh service_monitor.sh wifi_keepalive.sh download_scheduler.sh; do
        normalize_duplicate_processes "$s"
    done
}

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar \
        app_process / KioskHelper "$@"
}

. "$HOME/playlist_lib.sh" 2>/dev/null || true
. "$HOME/daemon_lib.sh" 2>/dev/null || true

# Sync subscription + channel configs into place NewPipe/import can see
sync_kiosk_files() {
    for f in channels.json newpipe_subscriptions.json online_playlist.json; do
        if [ -f "$HOME/Kiosk/$f" ]; then
            cp -f "$HOME/Kiosk/$f" "$KIOSK_DIR/$f" 2>/dev/null || true
            cp -f "$HOME/Kiosk/$f" /sdcard/Download/$f 2>/dev/null || true
        fi
        if [ -f "$KIOSK_DIR/$f" ]; then
            cp -f "$KIOSK_DIR/$f" "$HOME/Kiosk/$f" 2>/dev/null || true
        fi
    done
    # Import file for NewPipe previous-export import
    if [ -f "$KIOSK_DIR/newpipe_subscriptions.json" ]; then
        cp -f "$KIOSK_DIR/newpipe_subscriptions.json" /sdcard/Download/newpipe_subscriptions.json 2>/dev/null || true
    fi
}

configure_display() {
    log_info "Fullscreen + stay-awake display"
    settings put global stay_on_while_plugged_in 7 2>/dev/null || true
    settings put system screen_off_timeout 2147483647 2>/dev/null || true
    settings put system accelerometer_rotation 0 2>/dev/null || true
    settings put system user_rotation 0 2>/dev/null || true
    settings put global policy_control immersive.full=org.schabi.newpipe 2>/dev/null || true
    # Enforce key/button lock state immediately (watchdog keeps it repeated).
    kiosk_helper write-setting secure home_key_disabled 1 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure back_key_disabled 1 >/dev/null 2>&1 || true
    kiosk_helper write-setting global power_menu_disabled 1 >/dev/null 2>&1 || true
    kiosk_helper write-setting system screen_brightness_mode 0 >/dev/null 2>&1 || true
    input keyevent KEYCODE_WAKEUP 2>/dev/null || true
    # Keep termux+newpipe from routine background-idle kills when the system is
    # under memory or doze pressure.
    cmd deviceidle whitelist +com.termux >/dev/null 2>&1 || true
    cmd deviceidle whitelist +org.schabi.newpipe >/dev/null 2>&1 || true
    cmd deviceidle whitelist +com.android.kioskbooter >/dev/null 2>&1 || true
    if [ -d /sdcard ] && [ -w /sdcard/Kiosk ] 2>/dev/null; then
        printf 'locked\n' > /sdcard/Kiosk/touch_mode.txt 2>/dev/null || true
    fi
    am broadcast --user 0 -a com.android.kioskbooter.TOUCH_LOCK -n com.android.kioskbooter/.BootReceiver >/dev/null 2>&1 || true
    log_success "Display ready"
}

start_daemon() {
    local name="$1" script="$2" logfile="$3"
    local pidfile="$HOME/${name%.sh}.pid"
    if type daemon_is_running >/dev/null 2>&1 && \
       daemon_is_running "$pidfile" "$name"; then
        log_info "$name already running"
        return 0
    fi
    rm -f "$pidfile" 2>/dev/null || true
    [ -f "$script" ] || { log_warn "missing $script"; return 1; }
    chmod 755 "$script" 2>/dev/null || true
    setsid nohup /data/data/com.termux/files/usr/bin/bash "$script" >> "$logfile" 2>&1 &
    log_success "$name started pid=$!"
}

start_background_services() {
    log_info "Starting 24/7 services..."
    start_daemon "volume_guard.sh" "$HOME/volume_guard.sh" "$LOG_DIR/volume_guard.log"
    start_daemon "fullscreen_enforcer.sh" "$HOME/fullscreen_enforcer.sh" "$LOG_DIR/fullscreen_enforcer.log"
    start_daemon "wallpaper_live.sh" "$HOME/wallpaper_live.sh" "$LOG_DIR/wallpaper_live.log"
    start_daemon "newpipe_24x7.sh" "$HOME/newpipe_24x7.sh" "$LOG_DIR/newpipe_24x7.log"
    start_daemon "service_monitor.sh" "$HOME/service_monitor.sh" "$LOG_DIR/service_monitor.log"
    start_daemon "wifi_keepalive.sh" "$HOME/wifi_keepalive.sh" "$LOG_DIR/wifi_keepalive.log"
    start_daemon "download_scheduler.sh" "$HOME/download_scheduler.sh" "$LOG_DIR/download_scheduler.log"
}

kickstart() {
    log_info "Kickstart subscription channel autoplay (fullscreen)"
    if type play_next_coordinated >/dev/null 2>&1; then
        play_next_coordinated "boot" 1 "channel"
    else
        am start -a android.intent.action.VIEW \
            -d "https://www.youtube.com/@msrachel/videos" \
            -n org.schabi.newpipe/.RouterActivity -f 0x10000000 >/dev/null 2>&1 || true
    fi
    log_success "Kickstart issued"
}

start_stack_with_repair() {
    acquire_boot_lock
    log_warn "Core stack unhealthy or missing — running repair pass"
    # A supervisor repair must never silently exit parent mode. Deployment and
    # the explicit child-mode command own that state transition.
    if [ "${KIOSK_RESET_CHILD_MODE:-0}" = "1" ]; then
        rm -f "$KIOSK_DIR/parent_mode.txt" 2>/dev/null || true
        log_info "Explicit child-mode reset requested"
    elif [ -f "$KIOSK_DIR/parent_mode.txt" ]; then
        log_info "Preserving parent mode during repair"
    fi
    killer
    sync_kiosk_files
    configure_display
    start_background_services
    log_success "Boot/repair complete"
}

stack_supervisor() {
    if [ "$KIOSK_STACK_SUPERVISOR" != "1" ]; then
        return 0
    fi
    log_info "Supervising stack every ${KIOSK_SUPERVISOR_INTERVAL}s"
    while true; do
        sleep "$KIOSK_SUPERVISOR_INTERVAL"
        if stack_fully_running; then
            configure_display
            continue
        fi
        start_stack_with_repair
    done
}

log_info "Boot v4 starting"
if stack_fully_running; then
    log_warn "Kiosk core stack already running — running maintenance"
    acquire_boot_lock
    configure_display
    stack_supervisor
    exit 0
fi

if stack_running; then
    log_warn "Kiosk core stack partially running — repairing"
fi
start_stack_with_repair
stack_supervisor
log_success "Boot complete — newpipe_24x7 owns the single autoplay launch"
