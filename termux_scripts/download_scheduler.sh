#!/data/data/com.termux/files/usr/bin/bash
# Guarded scheduled downloader. It never owns playback and never changes Wi-Fi.

set +e
TERMUX_HOME="/data/data/com.termux/files/home"
PYTHON="/data/data/com.termux/files/usr/bin/python3"
DOWNLOAD_SCRIPT="$TERMUX_HOME/download_videos.py"
STATE_DIR="/sdcard/Kiosk"
PRIVATE_STATE_DIR="$TERMUX_HOME/Kiosk"
LOG_FILE="$TERMUX_HOME/download_scheduler.log"
PID_FILE="$TERMUX_HOME/download_scheduler.pid"

. "$TERMUX_HOME/daemon_lib.sh" 2>/dev/null || true
if type daemon_claim >/dev/null 2>&1; then
    daemon_claim "$PID_FILE" "download_scheduler.sh" || exit 0
else
    echo $$ > "$PID_FILE"
fi
trap 'rm -f "$PID_FILE"' EXIT INT TERM

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }
last_day=""
manual_done=""
log "NETZ-aware download scheduler started"

while true; do
    day=$(date +%Y-%m-%d)
    hour=$(date +%H)
    minute=$(date +%M)
    if [ "$day" != "$last_day" ]; then
        last_day="$day"
        manual_done=""
    fi

    if [ -f "$STATE_DIR/download_now.txt" ] || [ -f "$PRIVATE_STATE_DIR/download_now.txt" ]; then
        rm -f "$STATE_DIR/download_now.txt" "$PRIVATE_STATE_DIR/download_now.txt"
        log "Manual download request"
        "$PYTHON" "$DOWNLOAD_SCRIPT" download --force >> "$LOG_FILE" 2>&1
        manual_done="$day"
    elif [ "$hour" = "02" ] && [ "$minute" -lt "30" ] && [ "$manual_done" != "$day" ]; then
        log "Scheduled 02:00 download window"
        "$PYTHON" "$DOWNLOAD_SCRIPT" download >> "$LOG_FILE" 2>&1
        manual_done="$day"
    fi
    sleep 60
done
