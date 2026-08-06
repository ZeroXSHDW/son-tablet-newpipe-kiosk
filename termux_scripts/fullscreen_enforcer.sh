#!/system/bin/sh
#
# FULLSCREEN ENFORCER v5 — NewPipe ONLY, hard relaunch lock
#

set +e

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:/system/xbin:/vendor/bin:$PATH

LOG_FILE="$HOME/fullscreen_enforcer.log"
PARENT_MODE_VAR="/sdcard/Kiosk/parent_mode.txt"
PID_FILE="$HOME/fullscreen_enforcer.pid"
LOCK_URL_FILE="$HOME/Kiosk/last_played_url.txt"
DEFAULT_URL="https://www.youtube.com/watch?v=cDsbfQkl7VQ"
UI_DUMP_FILE="$HOME/Kiosk/fullscreen_enforcer.xml"

. "$HOME/daemon_lib.sh" 2>/dev/null || true
if type daemon_claim >/dev/null 2>&1; then
    daemon_claim "$PID_FILE" "fullscreen_enforcer.sh" || exit 0
else
    if [ -f "$PID_FILE" ]; then
        old=$(cat "$PID_FILE" 2>/dev/null | tr -d '\r\n ')
        if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            cmd=$(tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null || true)
            echo "$cmd" | grep -q "fullscreen_enforcer" && exit 0
        fi
    fi
    echo $$ > "$PID_FILE"
fi
trap 'rm -f "$PID_FILE"' EXIT INT TERM

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper "$@"
}

# The player-level fullscreen transition is separate from Android's immersive
# policy. Keep it owned by this always-running enforcer as well, so a NewPipe
# foreground reassert or playback grace period cannot leave the detail pane.
. "$HOME/kiosk_config.sh" 2>/dev/null || true

reassert_newpipe_player_fullscreen() {
    # Player-level fullscreen is owned by Kiosk Booter's bound accessibility
    # service. Calling Termux's `am` wrapper from this four-second watchdog can
    # leave an app_process child stuck, so this shell loop only maintains the
    # non-blocking display policy while the service repairs player bounds.
    settings put system accelerometer_rotation 0 2>/dev/null || true
    settings put system user_rotation 0 2>/dev/null || true
}

exec 1>>"$LOG_FILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] FULLSCREEN ENFORCER v4"

is_parent_mode() {
    [ -f "$PARENT_MODE_VAR" ] || return 1
    [ "$(cat "$PARENT_MODE_VAR" 2>/dev/null | tr -d '\r')" = "true" ]
}

get_foreground_app() {
    # UsageStats can lag behind the visible activity on this firmware. Use
    # WindowManager focus first so the player-level fullscreen watchdog sees
    # NewPipe while it is actually on screen. Termux cannot read that focus
    # dump reliably on this P7; do not fall back to stale UsageStats here.
    local fg
    fg=$(dumpsys window 2>/dev/null | grep mCurrentFocus | head -1 \
        | sed -n 's/.* \([a-zA-Z0-9_.]*\)\/.*/\1/p' | head -1)
    if [ -n "$fg" ] && [ "$fg" != "unknown" ]; then
        echo "$fg"
        return 0
    fi
    echo "unknown"
}

newpipe_media_active() {
    [ "${SUBSCRIPTIONS_ONLY:-0}" = "1" ] || return 1
    [ "$(kiosk_helper is-music-active 2>/dev/null | tr -d '\r\n')" = "true" ] && return 0

    local ms
    ms=$(dumpsys media_session 2>/dev/null || true)
    if echo "$ms" | grep -q 'package=org.schabi.newpipe' && \
       echo "$ms" | grep -qE 'state=3|state=6'; then
        return 0
    fi
    cmd media_session list-sessions 2>/dev/null | grep -qi 'org.schabi.newpipe'
}

resolve_lock_url() {
    if [ -f "$LOCK_URL_FILE" ]; then
        cat "$LOCK_URL_FILE" 2>/dev/null | tr -d '\r\n ' | grep -m1 -E '^https?://.+' || true
    elif [ -f /sdcard/Kiosk/active_stage_url.txt ]; then
        cat /sdcard/Kiosk/active_stage_url.txt 2>/dev/null | tr -d '\r\n ' | grep -m1 -E '^https?://.+' || true
    else
        echo "$DEFAULT_URL"
    fi
}

force_fullscreen_newpipe() {
    local url
    url=$(resolve_lock_url)
    [ -z "$url" ] && url="$DEFAULT_URL"
    am force-stop org.schabi.newpipe >/dev/null 2>&1 || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOCK] relaunching NewPipe fullscreen" >> "$LOG_FILE"
    if ! kiosk_start_activity am start -a android.intent.action.VIEW -d "$url" \
        -n org.schabi.newpipe/.RouterActivity -f 0x10000000 \
        -e fullscreen true -e autoplay true >/dev/null 2>&1; then
        kiosk_start_activity am start -a android.intent.action.VIEW -d "$url" \
            -n org.schabi.newpipe/.MainActivity \
            -f 0x10000000 >/dev/null 2>&1 || true
    fi
    # RouterActivity's fullscreen extra does not expand the tablet mini-player
    # by itself. Once the activity is present, use the native accessibility
    # transition and let its bounded gesture sequence finish before the next
    # foreground check can intervene.
    sleep 3
    reassert_newpipe_player_fullscreen
}

offline_vlc_allowed() {
    [ "$(get_foreground_app | tr -d '\r')" = "org.videolan.vlc" ] || return 1
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && return 1
    return 0
}

enforce_fullscreen() {
    local now target_fg target
    now=$(date +%s 2>/dev/null || echo 0)
    target_fg=$(get_foreground_app | tr -d '\r' || true)
    target=org.schabi.newpipe
    [ "$target_fg" = "org.videolan.vlc" ] && target=org.videolan.vlc

    # The overlay service is the fast safety path. Reassert the heavier shell
    # policy only every 30 seconds or when the foreground player changes; the
    # former four-second cadence spawned repeated app_process helpers and
    # materially increased low-memory pressure on this P7.
    if [ "$target" = "$last_policy_target" ] && \
       [ $((now - last_policy_epoch)) -lt 30 ] 2>/dev/null; then
        return 0
    fi
    settings put global policy_control "immersive.full=$target" 2>/dev/null || true
    # Keep landscape video orientation (P7 1024x600)
    settings put system accelerometer_rotation 0 2>/dev/null || true
    settings put system user_rotation 0 2>/dev/null || true

    # The boot orchestrator applies the privileged navigation settings once.
    # Do not call the app_process helper from this four-second watchdog: on
    # this firmware that helper can remain in an uninterruptible wait and
    # freeze the enforcer before it reaches the player fullscreen check.
    # The accessibility service remains locked unless a bounded fullscreen
    # transition explicitly unlocks it; avoid a blocking receiver call here.
    last_policy_epoch="$now"
    last_policy_target="$target"

    # Do not broadcast CLOSE_SYSTEM_DIALOGS on every watchdog pass. On this
    # firmware Termux implements `am` as a short-lived app_process that can be
    # orphaned; repeating it created hundreds of resident processes and drove
    # the low-memory killer against Kiosk Booter.
}

last_policy_epoch=0
last_policy_target=""
last_relaunch_epoch=0

while true; do
    if is_parent_mode; then
        settings put global policy_control null 2>/dev/null || true
        kiosk_helper write-setting secure home_key_disabled 0 >/dev/null 2>&1 || true
        kiosk_helper write-setting secure back_key_disabled 0 >/dev/null 2>&1 || true
        last_policy_epoch=0
        last_policy_target=""
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MODE] parent mode active" >> "$LOG_FILE"
        sleep 5
        continue
    fi

    enforce_fullscreen
    # Keep NewPipe fullscreen continuously: do not rely only on media-session
    # state. On this firmware media-session signals can be stale while NewPipe
    # is visible; foreground checks are more reliable for enforcing kiosk UI.
    fg=$(get_foreground_app | tr -d '\r' || true)
    if [ "$fg" = "org.schabi.newpipe" ] || [ "$fg" = "unknown" ]; then
        reassert_newpipe_player_fullscreen
        sleep 4
        continue
    fi
    fg=$(get_foreground_app | tr -d '\r' || true)
    if [ -n "$fg" ] && [ "$fg" != "org.schabi.newpipe" ] && [ "$fg" != "com.termux" ] && \
       [ "$fg" != "com.termux.boot" ] && [ "$fg" != "com.termux.api" ] && \
       [ "$fg" != "com.termux.widget" ] && [ "$fg" != "unknown" ] && \
       ! offline_vlc_allowed; then
        relaunch_now=$(date +%s 2>/dev/null || echo 0)
        if [ $((relaunch_now - last_relaunch_epoch)) -lt 60 ] 2>/dev/null; then
            sleep 4
            continue
        fi
        last_relaunch_epoch="$relaunch_now"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOCK] removing $fg and restoring fullscreen" >> "$LOG_FILE"
        am force-stop "$fg" >/dev/null 2>&1 || true
        force_fullscreen_newpipe
    fi
    sleep 4
done
