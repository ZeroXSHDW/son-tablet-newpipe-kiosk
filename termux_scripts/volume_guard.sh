#!/system/bin/sh
#
# VOLUME GUARD v3 — phase-aligned volume & brightness
# DAY about 80% (12/15) | BEDTIME/NIGHT sleep volume 3/15
#

set +e

STATE_DIR="/data/data/com.termux/files/home"
STATE_FILE="$STATE_DIR/volume_lock_state.txt"
DEBUG_LOG="$STATE_DIR/volume_guard.log"
KIOSK="/sdcard/Kiosk"
PID_FILE="$STATE_DIR/volume_guard.pid"

mkdir -p "$STATE_DIR" 2>/dev/null || true

. "$STATE_DIR/kiosk_config.sh" 2>/dev/null || true
. "$STATE_DIR/daemon_lib.sh" 2>/dev/null || true
if type daemon_claim >/dev/null 2>&1; then
    daemon_claim "$PID_FILE" "volume_guard.sh" || exit 0
else
    echo $$ > "$PID_FILE"
fi
trap 'rm -f "$PID_FILE"' EXIT INT TERM

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper "$@"
}

set_volume_level() {
    local target="$1"
    cmd media_session volume --stream 3 --set "$target" >/dev/null 2>&1 || true
    media volume --stream 3 --set "$target" >/dev/null 2>&1 || true
}

set_screen_brightness() {
    # The P7 denies CONTROL_DISPLAY_BRIGHTNESS to Termux. Kiosk Booter's
    # accessibility overlay is the trusted child-mode display window, so pass
    # the phase target to that window and retain the settings write as a
    # compatibility baseline for firmware that permits it.
    am broadcast --user 0 -a com.android.kioskbooter.BRIGHTNESS_SET \
        -n com.android.kioskbooter/.BootReceiver --ei brightness "$1" \
        >/dev/null 2>&1 || true
    kiosk_helper write-setting system screen_brightness "$1" >/dev/null 2>&1 || true
}

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

phase_settings() {
    phase=$(current_phase)
    if type kiosk_volume_for_phase >/dev/null 2>&1 && \
       type kiosk_brightness_for_phase >/dev/null 2>&1; then
        echo "$(kiosk_volume_for_phase "$phase")|$(kiosk_brightness_for_phase "$phase")"
        return
    fi
    case "$phase" in
        MORNING) echo "12|160" ;;
        LEARNING) echo "12|180" ;;
        RELAXING) echo "12|120" ;;
        BEDTIME) echo "3|40" ;;
        NIGHT) echo "3|25" ;;
        *) echo "12|100" ;;
    esac
}

ensure_state_file() {
    [ -f "$STATE_FILE" ] || printf 'LOCKED\n0\n' > "$STATE_FILE"
}

read_state() {
    ensure_state_file
    state=$(sed -n '1p' "$STATE_FILE" 2>/dev/null || echo LOCKED)
    unlock_until=$(sed -n '2p' "$STATE_FILE" 2>/dev/null || echo 0)
    echo "$state|$unlock_until"
}

write_state() {
    printf '%s\n%s\n' "$1" "$2" > "$STATE_FILE"
}

echo "[$(date)] Volume Guard v3 phase-aligned started" >> "$DEBUG_LOG"
last_brightness=-1
brightness_refresh_ticks=0
last_volume=-1

while true; do
    state_info=$(read_state)
    state=$(echo "$state_info" | cut -d'|' -f1)
    unlock_until=$(echo "$state_info" | cut -d'|' -f2)
    now=$(date +%s)

    if [ "$state" = "UNLOCKED" ] && [ "$unlock_until" -gt "$now" ]; then
        sleep 2
        continue
    fi
    if [ "$state" = "UNLOCKED" ] && [ "$unlock_until" -le "$now" ]; then
        write_state "LOCKED" "0"
        state="LOCKED"
    fi
    if [ "$state" = "UNLOCKED" ]; then
        sleep 2
        continue
    fi

    settings_str=$(phase_settings)
    vol_target=$(echo "$settings_str" | cut -d'|' -f1)
    bright_target=$(echo "$settings_str" | cut -d'|' -f2)
    if [ "$vol_target" -ne "$last_volume" ]; then
        set_volume_level "$vol_target"
        last_volume="$vol_target"
    fi
    if [ "$bright_target" -ne "$last_brightness" ] || [ "$brightness_refresh_ticks" -ge 15 ]; then
        set_screen_brightness "$bright_target"
        brightness_refresh_ticks=0
        if [ "$bright_target" -ne "$last_brightness" ]; then
            echo "[$(date)] phase=$(current_phase) vol=$vol_target bright=$bright_target" >> "$DEBUG_LOG"
        fi
        last_brightness=$bright_target
    else
        brightness_refresh_ticks=$((brightness_refresh_ticks + 1))
    fi
    sleep 5
done
