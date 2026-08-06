#!/data/data/com.termux/files/usr/bin/bash
#
# WIFI KEEPALIVE v1.1
# Ensures Wi‑Fi stays up for NewPipe streaming (+ wireless ADB).
# Playback handoff is owned exclusively by newpipe_24x7.sh.
#

set +e
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:$PATH
LOG="$HOME/wifi_keepalive.log"
PID_FILE="$HOME/wifi_keepalive.pid"
STATUS_FILE="$HOME/Kiosk/wifi_status.txt"
LOSS_FILE="$HOME/Kiosk/wifi_loss_since_epoch.txt"
mkdir -p "$HOME/Kiosk" 2>/dev/null || true

if [ -f "$PID_FILE" ]; then
    old=$(cat "$PID_FILE" 2>/dev/null | tr -d '\r')
    [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null && exit 0
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT INT TERM

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

log "WiFi keepalive started"

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar \
        app_process / KioskHelper "$@" 2>/dev/null
}

reconnect_saved_wifi() {
    # Enabling Wi-Fi lets Android select one of the networks already saved
    # on the tablet; no SSID or password is hard-coded here.
    svc wifi enable 2>/dev/null || true
    settings put global wifi_on 1 2>/dev/null || true
    settings put global wifi_scan_always_enabled 1 2>/dev/null || true
    cmd wifi set-wifi-enabled enabled 2>/dev/null || true
    cmd wifi start-scan 2>/dev/null || true
}

while true; do
    reconnect_saved_wifi

    if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        rm -f "$LOSS_FILE" 2>/dev/null || true
        echo "ok $(date +%s)" > "$STATUS_FILE" 2>/dev/null || true
    else
        log "No internet — ask Android to reconnect to a saved network"
        reconnect_saved_wifi
        echo "reconnecting $(date +%s)" > "$STATUS_FILE" 2>/dev/null || true
        now=$(date +%s)
        if [ ! -s "$LOSS_FILE" ]; then
            echo "$now" > "$LOSS_FILE" 2>/dev/null || true
        fi
        since=$(cat "$LOSS_FILE" 2>/dev/null | tr -d '\r')
        [ -n "$since" ] || since="$now"
        elapsed=$((now - since))
        log "Offline for ${elapsed}s — playback handoff remains owned by newpipe_24x7"
    fi

    # Soft-lock: never sleep wifi aggressively
    settings put global wifi_sleep_policy 2 2>/dev/null || true

    sleep 10
done
