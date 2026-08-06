#!/data/data/com.termux/files/usr/bin/bash
#
# ADHD LIVE WALLPAPER v1
# Soft cycling wallpapers by time phase (not overstimulating).
# Day = calm focus blues/greens | Dusk = lavender | Night = dark indigo
#

set +e
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:$PATH

LOG="$HOME/wallpaper_live.log"
PID_FILE="$HOME/wallpaper_live.pid"
# Prefer Termux-private walls (sdcard often unreadable under SELinux for Termux)
WALL_DIR="$HOME/Kiosk/wallpapers"
[ -d "$WALL_DIR" ] || WALL_DIR="/sdcard/Kiosk/wallpapers"
KIOSK_HOME="$HOME/Kiosk"
KIOSK="/sdcard/Kiosk"
LIVE_MARKER="$KIOSK_HOME/live_wallpaper_enabled"
CYCLE_SEC=90
mkdir -p "$KIOSK_HOME" "$WALL_DIR" 2>/dev/null || true

. "$HOME/daemon_lib.sh" 2>/dev/null || true
. "$HOME/kiosk_config.sh" 2>/dev/null || true
if type daemon_claim >/dev/null 2>&1; then
    daemon_claim "$PID_FILE" "wallpaper_live.sh" || exit 0
else
    if [ -f "$PID_FILE" ]; then
        old=$(cat "$PID_FILE" 2>/dev/null | tr -d '\r\n ')
        if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            cmd=$(tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null || true)
            echo "$cmd" | grep -q "wallpaper_live.sh" && exit 0
        fi
    fi
    echo $$ > "$PID_FILE"
fi
trap 'rm -f "$PID_FILE"' EXIT INT TERM

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

mkdir -p "$WALL_DIR" 2>/dev/null || true

# Phase helper (same windows as playlist_lib)
current_phase() {
    if type kiosk_current_phase >/dev/null 2>&1; then
        kiosk_current_phase
        return
    fi
    hm=$(date +%H%M 2>/dev/null | tr -d '\r' | sed 's/^0*//')
    [ -z "$hm" ] && hm=0
    if [ "$hm" -ge 600 ] && [ "$hm" -lt 900 ]; then echo "MORNING"
    elif [ "$hm" -ge 900 ] && [ "$hm" -lt 1800 ]; then echo "LEARNING"
    elif [ "$hm" -ge 1800 ] && [ "$hm" -lt 2030 ]; then echo "RELAXING"
    elif [ "$hm" -ge 2030 ] && [ "$hm" -lt 2230 ]; then echo "BEDTIME"
    else echo "NIGHT"
    fi
}

wallpaper_for_phase() {
    local p="$1"
    case "$p" in
        RELAXING) echo "$WALL_DIR/adhd_dusk.jpg" ;;
        BEDTIME|NIGHT) echo "$WALL_DIR/adhd_night.jpg" ;;
        *) echo "$WALL_DIR/adhd_day.jpg" ;;
    esac
}

set_wallpaper() {
    local img="$1"
    local phase_now
    phase_now=$(current_phase)
    [ -f "$img" ] || return 1

    # Always stage where other tools expect it
    cp -f "$img" /sdcard/Download/wallpaper.jpg 2>/dev/null || true
    cp -f "$img" /sdcard/Download/wallpaper.png 2>/dev/null || true

    # Prefer WallpaperSetter.jar if present
    if [ -f /data/local/tmp/WallpaperSetter.jar ]; then
        CLASSPATH=/data/local/tmp/WallpaperSetter.jar \
            app_process / WallpaperSetter "$img" >/dev/null 2>&1 && {
            log "set via WallpaperSetter: $img"
        }
    fi

    # termux-wallpaper if available
    if command -v termux-wallpaper >/dev/null 2>&1; then
        termux-wallpaper -f "$img" >/dev/null 2>&1 && log "set via termux-wallpaper: $img"
    fi

    # Phase brightness is owned by volume_guard through the Kiosk Booter child
    # overlay. Termux cannot reliably control WallpaperManager dimming on this
    # firmware, so do not leave a stale wallpaper-only dim override behind.
    log "wallpaper staged phase=$phase_now img=$img"
    return 0
}

apply_phase_dim() {
    # Kept as a compatibility hook. The child overlay owns effective display
    # brightness, including the live-wallpaper view, on this P7 firmware.
    return 0
}

log "ADHD live wallpaper daemon started"
last_phase=""
frame=0

while true; do
    # Skip if parent mode
    if [ -f "$KIOSK/parent_mode.txt" ] && \
       [ "$(cat "$KIOSK/parent_mode.txt" 2>/dev/null | tr -d '\r')" = "true" ]; then
        sleep 30
        continue
    fi

    phase=$(current_phase)
    echo "$phase" > "$KIOSK_HOME/phase.txt" 2>/dev/null || true
    if [ -d /sdcard ] && [ -w "$KIOSK" ] 2>/dev/null; then
        echo "$phase" > "$KIOSK/phase.txt" 2>/dev/null || true
    fi

    # When the real WallpaperService is active, never replace it with a static
    # image. This daemon then acts only as the shared phase/dimming companion.
    if [ -f "$LIVE_MARKER" ]; then
        apply_phase_dim "$phase"
        if [ "$phase" != "$last_phase" ]; then
            log "live wallpaper active phase=$phase"
            last_phase="$phase"
        fi
        sleep "$CYCLE_SEC"
        continue
    fi

    img=$(wallpaper_for_phase "$phase")
    # Fallback to Download staging
    if [ ! -f "$img" ]; then
        bn=$(basename "$img")
        [ -f "/sdcard/Download/$bn" ] && img="/sdcard/Download/$bn"
        [ -f "$HOME/Kiosk/wallpapers/$bn" ] && img="$HOME/Kiosk/wallpapers/$bn"
    fi

    # Soft "live" effect: alternate primary + copy of same set if variants exist
    # Prefer _a/_b frames if present
    base=$(echo "$img" | sed 's/\.jpg$//')
    if [ -f "${base}_a.jpg" ] && [ -f "${base}_b.jpg" ]; then
        if [ $((frame % 2)) -eq 0 ]; then
            img="${base}_a.jpg"
        else
            img="${base}_b.jpg"
        fi
    fi

    if [ "$phase" != "$last_phase" ] || [ $((frame % 1)) -eq 0 ]; then
        if [ -f "$img" ]; then
            set_wallpaper "$img"
            last_phase="$phase"
            log "phase=$phase wallpaper=$img"
        else
            log "missing wallpaper file: $img"
            # Fallbacks
            [ -f /sdcard/Download/wallpaper.png ] && set_wallpaper /sdcard/Download/wallpaper.png
        fi
    fi

    frame=$((frame + 1))
    sleep "$CYCLE_SEC"
done
