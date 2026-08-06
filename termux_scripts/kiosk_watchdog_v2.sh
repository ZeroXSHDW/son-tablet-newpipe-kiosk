#!/data/data/com.termux/files/usr/bin/bash
#
# KIOSK WATCHDOG v4 — NewPipe exclusive, subscription autoplay restore
#

set +e

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:$PATH

LOG_DIR="$HOME"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
PID_FILE="$LOG_DIR/kiosk_watchdog.pid"
KIOSK_DIR="/sdcard/Kiosk"
PARENT_MODE_VAR="$KIOSK_DIR/parent_mode.txt"
CHECK_INTERVAL=5
ALLOWED_APPS="org.schabi.newpipe com.termux com.termux.boot com.termux.api com.termux.widget"

# Compatibility shim: stable deployments assign playback recovery exclusively
# to newpipe_24x7.sh. Keep this filename for old launchers, but do not run a
# second independent recovery loop.
if [ -f "$HOME/kiosk_config.sh" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] watchdog retired; newpipe_24x7 owns recovery" \
        >> "$WATCHDOG_LOG"
    exit 0
fi

. "$HOME/playlist_lib.sh" 2>/dev/null || true

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper "$@"
}

. "$HOME/daemon_lib.sh" 2>/dev/null || true
if type daemon_claim >/dev/null 2>&1; then
    daemon_claim "$PID_FILE" "kiosk_watchdog_v2.sh" || exit 0
else
    if [ -f "$PID_FILE" ]; then
        old=$(cat "$PID_FILE" 2>/dev/null | tr -d '\r\n ')
        if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            cmd=$(tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null || true)
            echo "$cmd" | grep -q "kiosk_watchdog" && exit 0
        fi
    fi
    echo $$ > "$PID_FILE"
fi
trap 'rm -f "$PID_FILE"' EXIT INT TERM

exec 1>>"$WATCHDOG_LOG" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] WATCHDOG v4 SUBSCRIPTIONS"

log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"; }

is_parent_mode() {
    [ -f "$PARENT_MODE_VAR" ] || return 1
    [ "$(cat "$PARENT_MODE_VAR" 2>/dev/null | tr -d '\r')" = "true" ]
}

get_foreground_app() {
    kiosk_helper get-foreground 2>/dev/null | tr -d '\r' || echo "unknown"
}

restore_playback() {
    local reason="$1"
    log_warn "Restore subscription playback ($reason)"
    settings put global policy_control immersive.full=org.schabi.newpipe 2>/dev/null || true
    if type play_next_coordinated >/dev/null 2>&1; then
        play_next_coordinated "watchdog_$reason" 0 "channel"
    else
        am start -n org.schabi.newpipe/.MainActivity >/dev/null 2>&1 || true
    fi
}

kill_rivals() {
    for other in com.brouken.player com.google.android.apps.youtube.kids \
        com.google.android.youtube net.gcompris.full com.android.chrome; do
        am force-stop "$other" >/dev/null 2>&1 || true
    done
}

ensure_core_daemons() {
    if ! pgrep -f "newpipe_24x7.sh" >/dev/null 2>&1; then
        [ -f "$HOME/newpipe_24x7.sh" ] && nohup bash "$HOME/newpipe_24x7.sh" >> "$HOME/newpipe_24x7.log" 2>&1 &
    fi
    if ! pgrep -f "volume_guard.sh" >/dev/null 2>&1; then
        [ -f "$HOME/volume_guard.sh" ] && nohup bash "$HOME/volume_guard.sh" >> "$HOME/volume_guard.log" 2>&1 &
    fi
    if ! pgrep -f "fullscreen_enforcer.sh" >/dev/null 2>&1; then
        [ -f "$HOME/fullscreen_enforcer.sh" ] && nohup bash "$HOME/fullscreen_enforcer.sh" >> "$HOME/fullscreen_enforcer.log" 2>&1 &
    fi
}

while true; do
    input keyevent KEYCODE_WAKEUP 2>/dev/null || true
    if is_parent_mode; then
        sleep 6
        continue
    fi
    ensure_core_daemons
    kill_rivals
    settings put global policy_control immersive.full=org.schabi.newpipe 2>/dev/null || true

    fg_app=$(get_foreground_app)
    [ -z "$fg_app" ] && fg_app="unknown"

    if [ "$fg_app" = "org.schabi.newpipe" ]; then
        sleep $CHECK_INTERVAL
        continue
    fi

    # Don't fight Termux during parent ops / brief flashes — only restore if NewPipe dead
    if [ "$fg_app" = "com.termux" ] || [ "$fg_app" = "com.termux.boot" ] || \
       [ "$fg_app" = "com.termux.api" ] || [ "$fg_app" = "com.termux.widget" ]; then
        if ! pgrep -f org.schabi.newpipe >/dev/null 2>&1; then
            restore_playback "termux"
        fi
        sleep $CHECK_INTERVAL
        continue
    fi

    if [ "$fg_app" = "unknown" ]; then
        sleep $CHECK_INTERVAL
        continue
    fi

    log_warn "Unauthorized $fg_app"
    am force-stop "$fg_app" 2>/dev/null || true
    restore_playback "unauthorized"
    sleep $CHECK_INTERVAL
done
