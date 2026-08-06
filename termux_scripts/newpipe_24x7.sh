#!/data/data/com.termux/files/usr/bin/bash
#
# NEWPIPE 24/7 v5.2 — RECOVERY + VOLUME LOCK
# - PID check verifies cmdline (fixes false "already running")
# - Content: imported NewPipe subscriptions only; phase controls ambience
# - Aggressive auto-play + fullscreen
#

set +e

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:/system/xbin:/vendor/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib

LOG_FILE="$HOME/newpipe_24x7.log"
PID_FILE="$HOME/newpipe_24x7.pid"
NEEDLE="newpipe_24x7.sh"
STATE_HOME="$HOME/Kiosk"
mkdir -p "$STATE_HOME" 2>/dev/null || true

LAST_LAUNCH_FILE="$STATE_HOME/last_launch_epoch.txt"
PARENT_MODE_VAR="/sdcard/Kiosk/parent_mode.txt"
HEALTH_HOME="$STATE_HOME/health_24x7.json"

CHECK_EVERY=20
IDLE_UI_SEC=180
FORCE_ROTATE_SEC=0
LAUNCH_GRACE_SEC=180
OFFLINE_RETRY_SEC=30
OFFLINE_CACHE_RETRY_SEC=300
WIFI_LOSS_GRACE_SEC=45
RECOVERY_PLAY_PRESS_ATTEMPTS=3

. "$HOME/daemon_lib.sh" 2>/dev/null || true
. "$HOME/kiosk_config.sh" 2>/dev/null || true
. "$HOME/playlist_lib.sh" 2>/dev/null || true

CHECK_EVERY="${PLAYBACK_CHECK_SEC:-$CHECK_EVERY}"
IDLE_UI_SEC="${PLAYBACK_IDLE_RECOVERY_SEC:-$IDLE_UI_SEC}"
FORCE_ROTATE_SEC="${FORCED_ROTATION_SEC:-$FORCE_ROTATE_SEC}"
LAUNCH_GRACE_SEC="${PLAYBACK_GRACE_SEC:-$LAUNCH_GRACE_SEC}"
SLEEP_AUTOPLAY="${SLEEP_AUTOPLAY:-0}"
NEWPIPE_PKG="${NEWPIPE_PKG:-${NEWPIPE_PACKAGE:-org.schabi.newpipe}}"

if ! type daemon_claim >/dev/null 2>&1; then
    daemon_claim() {
        local pf="$1" needle="$2" old cmd
        if [ -f "$pf" ]; then
            old=$(cat "$pf" 2>/dev/null | tr -d '\r\n ')
            if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
                cmd=$(tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null || true)
                echo "$cmd" | grep -q "$needle" && return 1
            fi
        fi
        echo $$ > "$pf"
        return 0
    }
    daemon_release() { rm -f "$1" 2>/dev/null || true; }
fi

if ! type play_next_coordinated >/dev/null 2>&1; then
    current_phase() { echo "NIGHT"; }
    get_playlist_url() { echo "https://www.youtube.com/watch?v=cDsbfQkl7VQ"; }
    play_next_coordinated() {
        am start -a android.intent.action.VIEW -d "$(get_playlist_url)" \
            -n org.schabi.newpipe/.RouterActivity -f 0x10000000 >/dev/null 2>&1
    }
    is_online() { ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; }
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

if ! daemon_claim "$PID_FILE" "$NEEDLE"; then
    log "Real instance already running — exit"
    exit 0
fi
trap 'daemon_release "$PID_FILE"' EXIT INT TERM

# Clear stale play locks from crashed runs
rm -rf "$STATE_HOME/.play_lock" /sdcard/Kiosk/.play_lock 2>/dev/null || true

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar \
        app_process / KioskHelper "$@" 2>/dev/null
}

is_parent_mode() {
    [ -f "$PARENT_MODE_VAR" ] || return 1
    [ "$(cat "$PARENT_MODE_VAR" 2>/dev/null | tr -d '\r')" = "true" ]
}

get_fg() {
    local fg
    # UsageStats can lag behind the actual focused window on this firmware
    # (it can report a previously used child app while NewPipe is visible).
    # Prefer the current WindowManager focus. Termux cannot read that focus
    # dump reliably on this P7, so return unknown rather than a stale package.
    fg=$(dumpsys window 2>/dev/null | grep mCurrentFocus | head -1 \
        | sed -n 's/.* \([a-zA-Z0-9_.]*\)\/.*/\1/p' | head -1)
    if [ -n "$fg" ] && [ "$fg" != "unknown" ]; then
        echo "$fg"
        return
    fi
    echo "unknown"
}

# True if NewPipe media is actively playing or buffering
# Primary signal: UID-safe music-active check, then fallback to media-session
# dumps where available.
newpipe_music_active() {
    [ "${SUBSCRIPTIONS_ONLY:-0}" = "1" ] || return 1
    [ "$(kiosk_helper is-music-active 2>/dev/null | tr -d '\r\n')" = "true" ]
}

is_playing() {
    if newpipe_music_active; then
        return 0
    fi
    local ms
    ms=$(dumpsys media_session 2>/dev/null || true)
    if echo "$ms" | grep -q 'org.schabi.newpipe' && echo "$ms" | grep -qE 'state=3|state=6'; then
        return 0
    fi
    # Audio track held by NewPipe (not always accessible from Termux UID)
    if dumpsys audio 2>/dev/null | grep -qi 'org.schabi.newpipe'; then
        return 0
    fi
    # Media session list via cmd (some builds return a compact, UID-safe listing)
    if cmd media_session list-sessions 2>/dev/null | grep -qi 'org.schabi.newpipe'; then
        return 0
    fi
    return 1
}

newpipe_media_active() {
    if newpipe_music_active; then
        return 0
    fi
    local ms
    ms=$(dumpsys media_session 2>/dev/null || true)
    if echo "$ms" | grep -q 'package=org.schabi.newpipe' && \
       echo "$ms" | grep -qE 'state=3|state=6'; then
        return 0
    fi
    cmd media_session list-sessions 2>/dev/null | grep -qi 'org.schabi.newpipe'
}

is_newpipe_fg() {
    [ "$(get_fg)" = "org.schabi.newpipe" ]
}

is_vlc_fg() {
    [ "$(get_fg)" = "org.videolan.vlc" ]
}

play_offline_download() {
    local file
    # Termux's Android sandbox cannot enumerate the media FUSE mount on this
    # tablet, while Android/VLC can open a known URI. Keep this list aligned
    # with the verified native NewPipe Downloads and try them in order.
    local candidates=(
        "/sdcard/Movies/Bedtime Routine - Bedtime Stories for Toddlers - Preschool Videos - Toddler Learning Video Songs.mp4"
        "/sdcard/Movies/Animal Learning for Toddlers with Ms Rachel - 3 Full Episodes - Learn Animal Sounds - Best Videos.mp4"
        "/sdcard/Movies/Phonics Song + More Kids Songs & Nursery Rhymes - Learn Letter Sounds - Videos for Kids - Ms Rachel.mp4"
        "/sdcard/Movies/Learn with Ms Rachel - Friendship & Social Skills - Videos for Kids - Colors, Letters & Counting.mp4"
        "/sdcard/Movies/Teletubbies_-_WildBrain_FWcZtVtUKUY_Teletubbies_Laa_Laa_and_Tinky_Winky_Discover_Seahorses_Underwater_Full_Classic_Episode.mp4"
        "/sdcard/Movies/Teletubbies_-_WildBrain_ytpXXKkstrI_Teletubbies_Laa_Laa_Dipsy_Love_Playing_Together_Early_Social_Skills_Full_Episode.mp4"
        "/sdcard/Movies/Teletubbies_Compilations_-_Wildbrain_Vv3AsP_3GHg_Digging_for_Sand_Worms_Scooter_Fun_Teletubbies_Compilations_-_WildBrain.mp4"
        "/sdcard/Movies/Teletubbies_Compilations_-_Wildbrain_Ysi1juQWNW8_Dizzy_Fun_in_the_Tubby_Car_Teletubbies_Compilations_-_WildBrain_2_Hour_Compilation.mp4"
        "/sdcard/Movies/edubuzzkids_-xQ5NSVsfj4_Fox_and_Rabbit_fun_with_the_Ice_Cream_Truck.mp4"
        "/sdcard/Movies/edubuzzkids_MPK57xU-DZQ_Elephant_Help_Pluck_Some_Apples_for_Fox_and_Rabbit.mp4"
        "/sdcard/Movies/Tractor_Ted_di5Luvguy7I_Tractor_Ted_Moovie_Time_Full_Episode_Tractor_Ted_Official_Channel.mp4"
        "/sdcard/Movies/Tractor_Ted_y5n3FeVKh2c_Hello_Ewe_Tractor_Ted_Full_Episode_Big_Machines_Tractors_For_Kids.mp4"
        "/sdcard/Movies/Tractor_Ted_t9P5K9251Cc_Full_Episode_Compilation_Massive_Farm_Adventures_With_Tractor_Ted_For_Kids_Who_LOVE_Farms.mp4"
        "/sdcard/Movies/Teletubbies_-_WildBrain_zXfzzxH1q8o_Teletubbies_-_2_HOUR_Compilation_Season_16_Episodes_16-30_Videos_For_Kids.mp4"
        "/sdcard/Movies/Teletubbies_-_WildBrain_GzlvNZSzU4I_Classic_Episodes_-_3_HOURS_Full_Episode_Compilation_-_Teletubbies.mp4"
        "/sdcard/Movies/Teletubbies_-_WildBrain_ufCV6c_uJ4c_Teletubbies_-_2_HOURS_Full_Episode_Compilation_Go_Outside_Videos_For_Kids.mp4"
        "/sdcard/Movies/Teletubbies_-_WildBrain_DoT3K-jTtr4_Teletubbies_Staying_Cool_in_Summer_2_HOUR_Compilation_for_Kids.mp4"
    )
    am force-stop org.schabi.newpipe 2>/dev/null || true
    for file in "${candidates[@]}"; do
        # Use the normal video intent. VLC is the tablet's default video
        # handler after first-run setup; Android/VLC performs the file access.
        if type kiosk_helper >/dev/null 2>&1 && \
           kiosk_helper am-start -a android.intent.action.VIEW \
               -d "file://$file" -t video/mp4 >/dev/null 2>&1; then
            settings put global policy_control immersive.full=org.videolan.vlc 2>/dev/null || true
            kiosk_touch_lock 2>/dev/null || true
            return 0
        fi
        am start -a android.intent.action.VIEW -d "file://$file" -t video/mp4 \
            >/dev/null 2>&1 && {
                settings put global policy_control immersive.full=org.videolan.vlc 2>/dev/null || true
                kiosk_touch_lock 2>/dev/null || true
                return 0
            }
    done
    return 1
}

bring_newpipe_foreground() {
    local url=""
    url=$(cat "$STATE_HOME/last_played_url.txt" 2>/dev/null | tr -d '\r\n')
    if [ -n "$url" ] && echo "$url" | grep -qE 'youtube\.com/watch|youtu\.be/'; then
        kiosk_start_activity am start -a android.intent.action.VIEW -d "$url" \
            -n "${NEWPIPE_PKG}/.RouterActivity" \
            -f 0x10000000 -e autoplay true -e fullscreen true >/dev/null 2>&1 || true
    else
        kiosk_start_activity am start -n "${NEWPIPE_PKG}/.MainActivity" -f 0x10000000 >/dev/null 2>&1 || true
    fi
    enforce_screen
    ensure_fullscreen_player_ui 2>/dev/null || true
}

kill_rivals() {
    for pkg in com.google.android.youtube com.google.android.apps.youtube.kids \
        com.brouken.player net.gcompris.full com.android.chrome \
        com.google.android.go.documentsui; do
        am force-stop "$pkg" >/dev/null 2>&1 || true
    done
    # newpipe_24x7 is the sole playback/handoff owner. Never kill VLC during an
    # offline grace window; doing so used to make the separate Wi-Fi monitor
    # and this controller fight over the child-facing player every 20 seconds.
    if is_online; then
        am force-stop org.videolan.vlc >/dev/null 2>&1 || true
    fi
}

enforce_screen() {
    settings put system screen_off_timeout 2147483647 2>/dev/null || true
    settings put global stay_on_while_plugged_in 7 2>/dev/null || true
    if [ "$(get_fg)" = "org.videolan.vlc" ]; then
        settings put global policy_control immersive.full=org.videolan.vlc 2>/dev/null || true
    else
        settings put global policy_control immersive.full=org.schabi.newpipe 2>/dev/null || true
    fi
    input keyevent KEYCODE_WAKEUP 2>/dev/null || true
}

now_epoch() { date +%s 2>/dev/null | tr -d '\r'; }

reconnect_saved_wifi() {
    # Android chooses among its saved networks when Wi-Fi is enabled.
    svc wifi enable 2>/dev/null || true
    settings put global wifi_on 1 2>/dev/null || true
    settings put global wifi_scan_always_enabled 1 2>/dev/null || true
    cmd wifi set-wifi-enabled enabled 2>/dev/null || true
    cmd wifi start-scan 2>/dev/null || true
}

offline_loss_elapsed() {
    local now="$1" since=0
    [ -f "$STATE_HOME/wifi_loss_since_epoch.txt" ] && \
        since=$(cat "$STATE_HOME/wifi_loss_since_epoch.txt" 2>/dev/null | tr -d '\r')
    [ -z "$since" ] && since=0
    [ "$since" -gt 0 ] 2>/dev/null || { echo 0; return; }
    echo $((now - since))
}

read_last_launch() {
    [ -f "$LAST_LAUNCH_FILE" ] && cat "$LAST_LAUNCH_FILE" 2>/dev/null | tr -d '\r' || echo 0
}

ensure_volume_level() {
    local phase target
    phase=$(current_phase 2>/dev/null || echo NIGHT)
    if type kiosk_volume_for_phase >/dev/null 2>&1; then
        target=$(kiosk_volume_for_phase "$phase" 2>/dev/null || echo "")
    fi
    if [ -z "$target" ]; then
        case "$phase" in
            BEDTIME|NIGHT) target=3 ;;
            *) target=12 ;;
        esac
    fi
    cmd media_session volume --stream 3 --set "$target" >/dev/null 2>&1 || true
    media volume --stream 3 --set "$target" >/dev/null 2>&1 || true
    echo "$target"
}

restore_if_not_playing() {
    local i
    for i in $(seq 1 "$RECOVERY_PLAY_PRESS_ATTEMPTS"); do
        ensure_fullscreen_player_ui 2>/dev/null || true
        kiosk_media_play 2>/dev/null || true
        sleep 2
        if is_playing; then
            return 0
        fi
    done
    return 1
}

write_health() {
    local status="$1" detail="$2" phase url fallback
    phase=$(current_phase 2>/dev/null || echo '?')
    if [ "$status" = "playing" ] && { [ "$phase" = "BEDTIME" ] || [ "$phase" = "NIGHT" ]; }; then
        url=$(cat "$STATE_HOME/last_played_url.txt" 2>/dev/null | tr -d '\r\n')
        fallback="${SLEEP_FALLBACK_URL:-${FALLBACK_URL_BED:-}}"
        if [ -n "$fallback" ] && [ "$url" = "$fallback" ]; then
            detail="$phase/$detail sleep_fallback_ms_rachel"
        else
            detail="$phase/$detail sleep_channel_selected_edubuzzkids"
        fi
    fi
    printf '{"status":"%s","detail":"%s","phase":"%s","pid":%s,"updated":"%s"}\n' \
        "$status" "$detail" "$phase" "$$" \
        "$(date -Iseconds 2>/dev/null || date)" > "$HEALTH_HOME" 2>/dev/null || true
}

is_allowed_foreground() {
    case "$1" in
        org.schabi.newpipe|com.termux|com.termux.boot|com.termux.api|com.termux.widget|unknown|"")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

reclaim_foreground() {
    local fg="$1"
    if is_allowed_foreground "$fg"; then
        return 1
    fi
    if [ -n "$fg" ] && [ "$fg" != "unknown" ]; then
        am force-stop "$fg" >/dev/null 2>&1 || true
    fi
    bring_newpipe_foreground
    ensure_fullscreen_player_ui 2>/dev/null || true
    return 0
}

# Reliable play: open URL, wait, tap play — avoid thrashing on bad is_playing
force_play_video() {
    local url="$1"
    local i
    log "force_play $url"
    # Only force-stop if something other than us is stuck
    kiosk_start_activity am start -a android.intent.action.VIEW -d "$url" \
        -n org.schabi.newpipe/.RouterActivity \
        -f 0x10000000 -e autoplay true -e fullscreen true >/dev/null 2>&1 || true
    sleep 6
    kiosk_touch_unlock 2>/dev/null || true
    for i in 1 2 3 4 5; do
        kiosk_tap 320 162
        sleep 1
        kiosk_media_play 2>/dev/null || true
        sleep 2
        kiosk_tap 512 200
        sleep 2
        if is_playing; then
            log "playing after attempt $i url=$url"
            settings put global policy_control immersive.full=org.schabi.newpipe 2>/dev/null || true
            kiosk_tap 900 500
            kiosk_touch_lock 2>/dev/null || true
            date +%s > "$LAST_LAUNCH_FILE" 2>/dev/null || true
            echo "$url" > "$STATE_HOME/last_played_url.txt" 2>/dev/null || true
            return 0
        fi
    done
    # CRITICAL: record launch even if detection failed (dumpsys often lies under Termux UID)
    # Prevents endless force-stop thrash; next check uses grace period
    date +%s > "$LAST_LAUNCH_FILE" 2>/dev/null || true
    echo "$url" > "$STATE_HOME/last_played_url.txt" 2>/dev/null || true
    settings put global policy_control immersive.full=org.schabi.newpipe 2>/dev/null || true
    kiosk_touch_lock 2>/dev/null || true
    log "play launched (detection inconclusive) url=$url"
    return 0
}

play_next() {
    local reason="$1"
    local phase url
    phase=$(current_phase 2>/dev/null || echo NIGHT)
    log "PLAY next phase=$phase reason=$reason"

    if { [ "$phase" = "BEDTIME" ] || [ "$phase" = "NIGHT" ]; } && \
       [ "${SLEEP_AUTOPLAY:-0}" != "1" ]; then
        input keyevent KEYCODE_MEDIA_PAUSE 2>/dev/null || true
        write_health "sleep_disabled" "$phase/$reason config_off"
        log "sleep autoplay disabled by SLEEP_AUTOPLAY=${SLEEP_AUTOPLAY:-0}"
        return 0
    fi

    if ! is_online; then
        log "offline — wait"
        write_health "offline" "$reason"
        return 1
    fi

    kill_rivals
    enforce_screen
    rm -rf "$STATE_HOME/.play_lock" /sdcard/Kiosk/.play_lock 2>/dev/null || true

    if [ "${SUBSCRIPTIONS_ONLY:-0}" = "1" ]; then
        # Always return to the imported local subscription set. The playlist
        # helper rotates the five subscribed channels and presses Play All.
        if play_next_coordinated "$reason" 1 "channel"; then
            write_health "playing" "$phase/$reason subscriptions"
        else
            write_health "recovery_wait" "$phase/$reason subscriptions"
        fi
        return 0
    fi

    force_play_video "$(get_playlist_url)"
    write_health "playing" "$phase/$reason"
    return 0
}

log "==============================================="
log "NEWPIPE 24x7 v5.2 START pid=$$"
log "==============================================="
write_health "starting" "boot"

if ! is_parent_mode; then
    play_next "boot"
fi

while true; do
    if is_parent_mode; then
        write_health "parent" "paused"
        sleep 10
        continue
    fi

    phase_now=$(current_phase 2>/dev/null || echo NIGHT)
    if [ "${SLEEP_AUTOPLAY:-0}" != "1" ]; then
        case "$phase_now" in
            BEDTIME|NIGHT)
                if is_playing; then
                    input keyevent KEYCODE_MEDIA_PAUSE 2>/dev/null || true
                fi
                write_health "sleep_disabled" "$phase_now/config_off"
                sleep "$CHECK_EVERY"
                continue
                ;;
        esac
    fi
    enforce_screen
    kill_rivals

    # Reassert configured stream volume on each cycle (prevents drift if any
    # launcher or media app rewrites music volume).
    vol_target=$(ensure_volume_level)

    # Fullscreen is a local UI invariant. Reassert when NewPipe is foreground and
    # media looks active, so we avoid poking list/navigation views.
    fg_pre=$(get_fg)
    if [ "$fg_pre" = "org.schabi.newpipe" ] && (is_playing || newpipe_media_active); then
        ensure_fullscreen_player_ui 2>/dev/null || true
    fi

    if ! is_online; then
        # Keep Wi-Fi enabled and let Android reconnect to any saved network.
        # Do not interrupt a playing session for a transient drop: only after
        # 45 continuous seconds without connectivity may VLC take over.
        reconnect_saved_wifi
        offline_now=$(now_epoch)
        if [ ! -s "$STATE_HOME/wifi_loss_since_epoch.txt" ]; then
            echo "$offline_now" > "$STATE_HOME/wifi_loss_since_epoch.txt" 2>/dev/null || true
        fi
        offline_elapsed=$(offline_loss_elapsed "$offline_now")
        if [ "$offline_elapsed" -lt "$WIFI_LOSS_GRACE_SEC" ]; then
            write_health "offline" "wifi_reconnecting_grace_${offline_elapsed}s"
            sleep "$OFFLINE_RETRY_SEC"
            continue
        fi
        # NewPipe hands completed downloads to the external player on this
        # build. Keep VLC playing the local file until connectivity returns.
        if is_vlc_fg; then
            write_health "offline" "vlc_download_playing"
            sleep "$OFFLINE_RETRY_SEC"
            is_online && play_next "offline_recovered"
            continue
        fi
        # Offline-first behavior: preserve a healthy NewPipe session, then
        # periodically ask NewPipe to open its locally cached subscription
        # feed. NewPipe does not accept arbitrary /sdcard/Movies files as
        # RouterActivity URLs, so never pretend that external files are an
        # in-app NewPipe download.
        if [ "$fg_pre" = "org.schabi.newpipe" ] && is_playing; then
            write_health "offline" "cached_newpipe_session_playing"
        else
            offline_now=$(now_epoch)
            offline_last=0
            [ -f "$STATE_HOME/offline_cache_attempt_epoch.txt" ] && \
                offline_last=$(cat "$STATE_HOME/offline_cache_attempt_epoch.txt" 2>/dev/null | tr -d '\r')
            [ -z "$offline_last" ] && offline_last=0
            if [ $((offline_now - offline_last)) -ge "$OFFLINE_CACHE_RETRY_SEC" ]; then
                echo "$offline_now" > "$STATE_HOME/offline_cache_attempt_epoch.txt" 2>/dev/null || true
                # Prefer a completed local download whenever one exists. On
                # this NewPipe build downloaded MP4s are handed to VLC, so
                # reopening the online/cache UI first would skip the content
                # the offline-first policy is meant to use.
                if play_offline_download; then
                    write_health "offline" "vlc_download_playing"
                elif launch_newpipe_cached_subscription_feed; then
                    write_health "playing" "offline_cached_subscription_feed"
                else
                    write_health "offline" "no_cached_newpipe_download_available"
                fi
            else
                write_health "offline" "waiting_cached_newpipe_retry"
            fi
        fi
        sleep "$OFFLINE_RETRY_SEC"
        is_online && play_next "offline_recovered"
        continue
    fi

    # Connectivity has returned; the next online iteration may restore NewPipe.
    rm -f "$STATE_HOME/wifi_loss_since_epoch.txt" 2>/dev/null || true

    now=$(now_epoch)
    last=$(read_last_launch)
    [ -z "$last" ] && last=0
    # Guard against clock skew / future timestamps
    if [ "$last" -gt "$now" ]; then
        last=$now
        echo "$now" > "$LAST_LAUNCH_FILE"
    fi
    age=$(( now - last ))

    media_active=0
    if is_playing; then
        media_active=1
    elif newpipe_media_active; then
        media_active=1
    fi

    if [ "$media_active" -eq 1 ] && [ "$fg_pre" != "org.schabi.newpipe" ]; then
        reclaim_foreground "$fg_pre"
        if [ $? -eq 0 ]; then
            write_health "playing" "foreground_reassert media_active"
            sleep "$CHECK_EVERY"
            continue
        fi
    fi

    if [ "$media_active" -eq 1 ] && [ "$age" -lt "$LAUNCH_GRACE_SEC" ]; then
        if [ "$fg_pre" = "org.schabi.newpipe" ]; then
            ensure_fullscreen_player_ui 2>/dev/null || true
        fi
        write_health "playing" "grace age=$age"
        sleep "$CHECK_EVERY"
        continue
    fi

    if [ "$FORCE_ROTATE_SEC" -gt 0 ] && [ "$age" -ge "$FORCE_ROTATE_SEC" ]; then
        play_next "rotate"
        sleep "$CHECK_EVERY"
        continue
    fi

    fg=$(get_fg)
    [ -z "$fg" ] && fg="unknown"

    # KioskHelper's UsageStats fallback can be stale even while WindowManager
    # has NewPipe focused. If media remains active, restore focus then continue.
    if [ "$media_active" -eq 1 ] && [ "$fg_pre" = "org.schabi.newpipe" ]; then
        ensure_fullscreen_player_ui 2>/dev/null || true
        write_health "playing" "media_session_active"
        sleep "$CHECK_EVERY"
        continue
    fi

    # Wrong app (not NewPipe/Termux)
    if [ "$fg" != "org.schabi.newpipe" ] && [ "$fg" != "org.videolan.vlc" ] && [ "$fg" != "com.termux" ] && \
       [ "$fg" != "com.termux.boot" ] && [ "$fg" != "com.termux.api" ] && \
       [ "$fg" != "com.termux.widget" ] && [ "$fg" != "unknown" ]; then
        if [ "$fg" = "org.videolan.vlc" ] && ! is_online; then
            write_health "offline" "vlc_download_playing"
            sleep "$CHECK_EVERY"
            continue
        fi
        if [ "$media_active" -eq 1 ]; then
            reclaim_foreground "$fg"
            write_health "playing" "foreground_reassert media_active"
            sleep "$CHECK_EVERY"
            continue
        fi
        if is_playing; then
            write_health "playing" "foreground_reassert"
            bring_newpipe_foreground
            sleep "$CHECK_EVERY"
            continue
        fi
        log "block $fg"
        am force-stop "$fg" 2>/dev/null || true
        play_next "wrong_app"
        sleep "$CHECK_EVERY"
        continue
    fi

    # Termux briefly OK — only restore if not playing
    if [ "$fg" = "com.termux" ] || [ "$fg" = "com.termux.boot" ]; then
        if [ "$media_active" -eq 1 ]; then
            reclaim_foreground "$fg"
            write_health "playing" "foreground_reassert"
            sleep "$CHECK_EVERY"
            continue
        fi
        if is_playing; then
            bring_newpipe_foreground
            write_health "playing" "foreground_reassert"
        else
            play_next "left_termux"
        fi
        sleep "$CHECK_EVERY"
        continue
    fi

    if is_newpipe_fg; then
        if is_playing; then
            ensure_fullscreen_player_ui 2>/dev/null || true
            write_health "playing" "ok"
        else
            # NewPipe open but idle / error panel
            # A connectivity probe can flap between iterations while the
            # player is already stuck in a non-playing detail pane. Once the
            # offline grace has elapsed, hand off to the known cached VLC
            # path instead of leaving the child on an unusable NewPipe UI.
            if ! is_online; then
                offline_now=$(now_epoch)
                if [ ! -s "$STATE_HOME/wifi_loss_since_epoch.txt" ]; then
                    echo "$offline_now" > "$STATE_HOME/wifi_loss_since_epoch.txt" 2>/dev/null || true
                fi
                offline_elapsed=$(offline_loss_elapsed "$offline_now")
                if [ "$offline_elapsed" -ge "$WIFI_LOSS_GRACE_SEC" ] && play_offline_download; then
                    write_health "offline" "vlc_download_playing_idle_newpipe"
                    sleep "$CHECK_EVERY"
                    continue
                fi
            fi
            if restore_if_not_playing; then
                write_health "playing" "nudge_recovered age=$age"
            elif [ "$age" -ge "$IDLE_UI_SEC" ]; then
                log "NewPipe idle not playing age=$age"
                play_next "idle_ui"
            else
                # Nudge play button
                write_health "nudge" "age=$age"
            fi
        fi
    else
        if is_playing; then
            bring_newpipe_foreground
            write_health "playing" "foreground_reassert"
        elif [ "$age" -ge "$IDLE_UI_SEC" ]; then
            play_next "not_fg"
        fi
    fi

    sleep "$CHECK_EVERY"
done
