#!/data/data/com.termux/files/usr/bin/bash
# activate.sh - Start NewPipe 24/7 kiosk services (idempotent)

set +u

PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
PATH=$PREFIX/bin:$PATH
LOG=$HOME/activate.log

mkdir -p /sdcard/Kiosk "$HOME"
exec >> "$LOG" 2>&1
echo ""
echo "============================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] activate.sh — NewPipe 24/7"
echo "============================================="

# Phase label (for logs / brightness)
HM=$(date +%H%M | sed 's/^0*//')
[ -z "$HM" ] && HM=0
if   [ "$HM" -ge 600  ] && [ "$HM" -lt 2030 ]; then PHASE=DAY
else PHASE=NIGHT
fi
echo "$PHASE" > /sdcard/Kiosk/phase.txt
echo "[INFO] Phase: $PHASE"

# 24/7 display
settings put system screen_off_timeout 2147483647 2>/dev/null || true
settings put global stay_on_while_plugged_in 7 2>/dev/null || true
if [ "$PHASE" = "DAY" ]; then
    settings put system screen_brightness 180 2>/dev/null || true
else
    settings put system screen_brightness 30 2>/dev/null || true
fi
settings put system screen_brightness_mode 0 2>/dev/null || true
settings put secure adaptive_sleep 0 2>/dev/null || true
settings put global policy_control immersive.full=org.schabi.newpipe 2>/dev/null || true
echo "[INFO] Display / immersive applied"

termux-wake-lock 2>/dev/null || true
rm -f /sdcard/Kiosk/parent_mode.txt 2>/dev/null || true

# Kill rival players — NewPipe only
for p in com.brouken.player com.google.android.youtube com.google.android.apps.youtube.kids net.gcompris.full; do
    am force-stop "$p" 2>/dev/null || true
done

svc_start() {
    local tag=$1 script=$2
    if pgrep -f "$tag" >/dev/null 2>&1; then
        echo "[INFO] Already running: $tag"
        return
    fi
    if [ ! -f "$script" ]; then
        echo "[WARN] Missing: $script"
        return
    fi
    echo "[INFO] Starting: $tag"
    nohup $PREFIX/bin/bash "$script" >> "$HOME/${tag}.log" 2>&1 &
    sleep 1
}

svc_start "volume_guard"        "$HOME/volume_guard.sh"
svc_start "fullscreen_enforcer" "$HOME/fullscreen_enforcer.sh"
svc_start "newpipe_24x7"        "$HOME/newpipe_24x7.sh"
svc_start "service_monitor"     "$HOME/service_monitor.sh"
[ -f "$HOME/wifi_keepalive.sh" ] && svc_start "wifi_keepalive" "$HOME/wifi_keepalive.sh"
[ -f "$HOME/update_newpipe.sh" ] && svc_start "update_newpipe" "$HOME/update_newpipe.sh"
[ -f "$HOME/log_rotation.sh" ] && svc_start "log_rotation" "$HOME/log_rotation.sh"

# Immediate playlist kickstart
. "$HOME/playlist_lib.sh" 2>/dev/null || true
if type get_playlist_url >/dev/null 2>&1; then
    URL=$(get_playlist_url)
else
    URL=$(grep -oE 'https://www\.youtube\.com/watch\?v=[a-zA-Z0-9_-]{11}' /sdcard/Kiosk/online_playlist.json 2>/dev/null | head -1)
    [ -z "$URL" ] && URL="https://www.youtube.com/watch?v=2dDpryw3z5w"
fi
echo "[INFO] Kickstart: $URL"
am start -a android.intent.action.VIEW -d "$URL" \
    -n org.schabi.newpipe/.RouterActivity -e fullscreen "true" -e autoplay "true" -f 0x10000000 2>/dev/null \
    || am start -a android.intent.action.VIEW -d "$URL" -n org.schabi.newpipe/.MainActivity 2>/dev/null \
    || true

echo "[INFO] activate.sh complete — NewPipe 24/7 only"
