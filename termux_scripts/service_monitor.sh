#!/data/data/com.termux/files/usr/bin/bash
# Service Health Monitor v3.1 — NewPipe 24/7 core services only
# Restarts dead daemons every 45s

set +u

HOME_DIR="/data/data/com.termux/files/home"
LOG_FILE="$HOME_DIR/service_monitor.log"
PID_FILE="$HOME_DIR/service_monitor.pid"
STATUS_HOME="$HOME_DIR/Kiosk/service_status.txt"
CHECK_INTERVAL=45

export PATH="/data/data/com.termux/files/usr/bin:/system/bin:$PATH"

# Core stack. newpipe_24x7 remains the sole playback recovery owner; the
# downloader is storage/network work only and never launches a player. Wi-Fi
# keepalive is supervised as a recovery service but never owns playback.
SERVICES=(
    "newpipe_24x7.sh:NewPipe 24x7"
    "fullscreen_enforcer.sh:Fullscreen Enforcer"
    "volume_guard.sh:Volume Guard"
    "wallpaper_live.sh:ADHD Wallpaper"
    "wifi_keepalive.sh:Wi-Fi Keepalive"
    "download_scheduler.sh:Offline Downloader"
)

. "$HOME_DIR/daemon_lib.sh" 2>/dev/null || true
if type daemon_claim >/dev/null 2>&1; then
    daemon_claim "$PID_FILE" "service_monitor.sh" || exit 0
else
    echo $$ > "$PID_FILE"
fi
trap 'rm -f "$PID_FILE"' EXIT INT TERM

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"
}

is_service_running() {
    local needle="$1"
    local pidfile="$HOME_DIR/${needle%.sh}.pid"
    if type daemon_is_running >/dev/null 2>&1 && \
       daemon_is_running "$pidfile" "$needle"; then
        return 0
    fi
    # Fallback uses the exact command path. pgrep -f can match its own search
    # command on this firmware and falsely report a dead service as healthy.
    ps -ef 2>/dev/null | grep -F "bash $HOME_DIR/$needle" | grep -v grep >/dev/null 2>&1
}

start_service() {
    local script=$1
    local name=$2
    local pids
    log_message "INFO" "Starting $name..."
    if [ ! -f "$HOME_DIR/$script" ]; then
        log_message "ERROR" "Missing $script"
        return 1
    fi
    pids=$(ps -ef 2>/dev/null | grep -F "bash $HOME_DIR/$script" | grep -v "grep" | awk '{print $2}' || true)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
    setsid nohup /data/data/com.termux/files/usr/bin/bash "$HOME_DIR/$script" \
        >> "$HOME_DIR/${script%.sh}.log" 2>&1 &
    sleep 2
    if is_service_running "$script"; then
        log_message "INFO" "✓ $name up"
        return 0
    fi
    log_message "ERROR" "✗ $name failed to start"
    return 1
}

log_message "INFO" "Service monitor v3.1 started (NewPipe 24/7 core)"

while true; do
    # Skip aggressive restarts in parent mode
    if [ -f /sdcard/Kiosk/parent_mode.txt ] && \
       [ "$(cat /sdcard/Kiosk/parent_mode.txt 2>/dev/null | tr -d '\r')" = "true" ]; then
        sleep "$CHECK_INTERVAL"
        continue
    fi

    for entry in "${SERVICES[@]}"; do
        script="${entry%%:*}"
        name="${entry##*:}"
        if ! is_service_running "$script"; then
            log_message "WARN" "$name not running — restart"
            start_service "$script" "$name"
        fi
    done

    # Write the authoritative snapshot in Termux-private storage. On this
    # Android build Termux can read, but cannot reliably rewrite, the shared
    # /sdcard/Kiosk path after adb-created directories are present.
    mkdir -p "$(dirname "$STATUS_HOME")" 2>/dev/null || true
    {
        echo "time=$(date -Iseconds 2>/dev/null || date)"
        for entry in "${SERVICES[@]}"; do
            script="${entry%%:*}"
            name="${entry##*:}"
            if is_service_running "$script"; then
                echo "ok=$name"
            else
                echo "down=$name"
            fi
        done
        # pgrep -f is restricted/unreliable from the Termux service UID on this
        # Android build; pidof is the stable package-process check.
        if pidof org.schabi.newpipe >/dev/null 2>&1; then
            echo "ok=NewPipe process"
        else
            echo "note=NewPipe process not visible to Termux UID; verify with adb"
        fi
    } > "$STATUS_HOME" 2>/dev/null || true
    cp "$STATUS_HOME" /sdcard/Kiosk/service_status.txt 2>/dev/null || true

    sleep "$CHECK_INTERVAL"
done
