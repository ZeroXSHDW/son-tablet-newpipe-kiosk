#!/data/data/com.termux/files/usr/bin/bash
# Phase-aware subscription helpers v5
# DAY: learning channels | BEDTIME/NIGHT: Edubuzzkids sleep with Ms Rachel fallback

. "${HOME:-/data/data/com.termux/files/home}/kiosk_config.sh" 2>/dev/null || true

# Centralized launch wrapper: helper fast-path + guaranteed shell fallback.
if ! type kiosk_start_activity >/dev/null 2>&1; then
    kiosk_start_activity() { am start "$@" >/dev/null 2>&1 || true; }
fi

KIOSK_DIR_CANDIDATES="${HOME:-/data/data/com.termux/files/home}/Kiosk /sdcard/Kiosk /storage/emulated/0/Kiosk"
FALLBACK_URL_DAY="https://www.youtube.com/watch?v=2dDpryw3z5w"
FALLBACK_URL_BED="https://www.youtube.com/watch?v=OyUoskE7Ogk"
FALLBACK_URL_NIGHT="https://www.youtube.com/watch?v=cDsbfQkl7VQ"
FALLBACK_CH_DAY="https://www.youtube.com/@msrachel/videos"
FALLBACK_CH_NIGHT="https://www.youtube.com/@msrachel/videos"
NEWPIPE_PKG="org.schabi.newpipe"

resolve_kiosk_dir() {
    for d in $KIOSK_DIR_CANDIDATES; do
        if [ -d "$d" ] || mkdir -p "$d" 2>/dev/null; then
            echo "$d"
            return 0
        fi
    done
    echo "${HOME:-/data/data/com.termux/files/home}/Kiosk"
}

# Returns MORNING|LEARNING|RELAXING|BEDTIME|NIGHT
current_phase() {
    if type kiosk_current_phase >/dev/null 2>&1; then
        kiosk_current_phase
        return
    fi
    hm=$(date +%H%M 2>/dev/null | tr -d '\r' || echo 0)
    hm=$(echo "$hm" | sed 's/^0*//')
    [ -z "$hm" ] && hm=0
    if [ "$hm" -ge 600 ] && [ "$hm" -lt 900 ]; then
        echo "MORNING"
    elif [ "$hm" -ge 900 ] && [ "$hm" -lt 1800 ]; then
        echo "LEARNING"
    elif [ "$hm" -ge 1800 ] && [ "$hm" -lt 2030 ]; then
        echo "RELAXING"
    elif [ "$hm" -ge 2030 ] && [ "$hm" -lt 2230 ]; then
        echo "BEDTIME"
    else
        # 22:30-06:00
        echo "NIGHT"
    fi
}

# Write phase for other daemons (volume/wallpaper)
write_phase_file() {
    local p
    p=$(current_phase)
    local k
    k=$(resolve_kiosk_dir)
    echo "$p" > "$k/phase.txt" 2>/dev/null || true
    echo "$p" > "${HOME}/Kiosk/phase.txt" 2>/dev/null || true
    echo "$p"
}

find_playlist_file() {
    local k
    k=$(resolve_kiosk_dir)
    [ -f "$k/online_playlist.json" ] && echo "$k/online_playlist.json" && return 0
    [ -f "${HOME}/Kiosk/online_playlist.json" ] && echo "${HOME}/Kiosk/online_playlist.json" && return 0
    echo ""
}

# Phase-filtered video URLs — NEVER use grep -B (it bleeds into previous JSON objects)
# Extract each playlist object and filter by type field only.
_urls_for_phase() {
    local playlist_file phase want_type urls
    playlist_file=$(find_playlist_file)
    phase=$(current_phase)
    [ -z "$playlist_file" ] || [ ! -f "$playlist_file" ] && return 0

    case "$phase" in
        BEDTIME) want_type='bedtime|asmr' ;;
        NIGHT)   want_type='asmr' ;;
        MORNING|LEARNING|RELAXING) want_type='learning' ;;
        *) want_type='learning' ;;
    esac

    # Split-ish: for each "url" line, look ahead a few lines for matching type in the SAME object
    # Objects are ordered url then later type — scan with awk
    urls=$(awk -v want="$want_type" '
        /"url":/ {
            if (match($0, /https:\/\/www\.youtube\.com\/watch\?v=[a-zA-Z0-9_-]{11}/)) {
                u = substr($0, RSTART, RLENGTH)
            }
        }
        /"type":/ {
            if (u != "" && $0 ~ want) {
                print u
                u = ""
            }
        }
        /\{/ { if ($0 ~ /^\s*\{/) { /* new object may reset */ } }
        /"url":/ { }
    ' "$playlist_file" 2>/dev/null || true)

    # Fallback pure type blocks: lines with type then previous url stored
    if [ -z "$urls" ]; then
        urls=$(awk -v want="$want_type" '
            /"url":/ {
                if (match($0, /https:\/\/www\.youtube\.com\/watch\?v=[a-zA-Z0-9_-]{11}/))
                    u = substr($0, RSTART, RLENGTH)
            }
            /"type":/ {
                t=$0
                if (u != "" && t ~ want) print u
            }
        ' "$playlist_file" 2>/dev/null || true)
    fi

    echo "$urls" | sed '/^$/d' | sort -u
}

# Channel feeds allowed for current phase
get_subscription_channel_url() {
    local phase ch last
    phase=$(current_phase)
    write_phase_file >/dev/null 2>&1 || true

    # Sleep playback has an explicit channel owner even in subscriptions-only
    # mode. This prevents bedtime from rotating into learning channels.
    if [ "$phase" = "BEDTIME" ] || [ "$phase" = "NIGHT" ]; then
        ch="${SLEEP_CHANNEL_URL:-https://www.youtube.com/@edubuzzkids/videos}"
        echo "$ch" > "$(resolve_kiosk_dir)/last_channel_url.txt" 2>/dev/null || true
        echo "$ch" > "${HOME}/Kiosk/last_channel_url.txt" 2>/dev/null || true
        echo "$ch"
        return 0
    fi

    # Daytime subscriptions-only mode rotates through the imported channels.
    if [ "${SUBSCRIPTIONS_ONLY:-0}" = "1" ]; then
        local index_file idx next
        index_file="$(resolve_kiosk_dir)/subscription_channel_index.txt"
        idx=$(cat "$index_file" 2>/dev/null | tr -d '\r\n ')
        case "$idx" in 0|1|2|3|4) ;; *) idx=0 ;; esac
        case "$idx" in
            0) ch="https://www.youtube.com/@msrachel/videos" ;;
            1) ch="https://www.youtube.com/@TractorTed/videos" ;;
            2) ch="https://www.youtube.com/@Teletubbies/videos" ;;
            3) ch="https://www.youtube.com/channel/UCrbHp6Xh0oEOhOozMk9t_wQ/videos" ;;
            *) ch="https://www.youtube.com/@edubuzzkids/videos" ;;
        esac
        next=$(( (idx + 1) % 5 ))
        echo "$next" > "$index_file" 2>/dev/null || true
        echo "$ch" > "$(resolve_kiosk_dir)/last_channel_url.txt" 2>/dev/null || true
        echo "$ch" > "${HOME}/Kiosk/last_channel_url.txt" 2>/dev/null || true
        echo "$ch"
        return 0
    fi

    case "$phase" in
        BEDTIME|NIGHT)
            # Only Ms Rachel for bedtime/night channel mode (sleep-friendly)
            ch="https://www.youtube.com/@msrachel/videos"
            ;;
        MORNING)
            # Gentle morning: Ms Rachel + edubuzz
            case $(( RANDOM % 2 )) in
                0) ch="https://www.youtube.com/@msrachel/videos" ;;
                *) ch="https://www.youtube.com/@edubuzzkids/videos" ;;
            esac
            ;;
        RELAXING)
            case $(( RANDOM % 3 )) in
                0) ch="https://www.youtube.com/@msrachel/videos" ;;
                1) ch="https://www.youtube.com/@Teletubbies/videos" ;;
                *) ch="https://www.youtube.com/@TractorTed/videos" ;;
            esac
            ;;
        LEARNING|*)
            case $(( RANDOM % 5 )) in
                0) ch="https://www.youtube.com/@msrachel/videos" ;;
                1) ch="https://www.youtube.com/@TractorTed/videos" ;;
                2) ch="https://www.youtube.com/@Teletubbies/videos" ;;
                3) ch="https://www.youtube.com/channel/UCrbHp6Xh0oEOhOozMk9t_wQ/videos" ;;
                *) ch="https://www.youtube.com/@edubuzzkids/videos" ;;
            esac
            ;;
    esac

    last=""
    [ -f "$(resolve_kiosk_dir)/last_channel_url.txt" ] && \
        last=$(cat "$(resolve_kiosk_dir)/last_channel_url.txt" 2>/dev/null | tr -d '\r')
    # Avoid same channel twice when alternatives exist (day only)
    if [ "$phase" = "LEARNING" ] && [ "$ch" = "$last" ]; then
        ch="https://www.youtube.com/@TractorTed/videos"
    fi
    echo "$ch" > "$(resolve_kiosk_dir)/last_channel_url.txt" 2>/dev/null || true
    echo "$ch" > "${HOME}/Kiosk/last_channel_url.txt" 2>/dev/null || true
    echo "$ch"
}

get_playlist_url() {
    local phase urls count picked last tries
    phase=$(current_phase)
    write_phase_file >/dev/null 2>&1 || true
    urls=$(_urls_for_phase)

    if [ -z "$urls" ]; then
        case "$phase" in
            BEDTIME) echo "$FALLBACK_URL_BED"; return 0 ;;
            NIGHT) echo "$FALLBACK_URL_NIGHT"; return 0 ;;
            *) echo "$FALLBACK_URL_DAY"; return 0 ;;
        esac
    fi

    last=""
    [ -f "$(resolve_kiosk_dir)/last_played_url.txt" ] && \
        last=$(cat "$(resolve_kiosk_dir)/last_played_url.txt" 2>/dev/null | tr -d '\r')
    count=$(echo "$urls" | wc -l | tr -d ' \r')
    [ "$count" -lt 1 ] && count=1
    tries=0
    picked=""
    while [ "$tries" -lt 12 ]; do
        tries=$((tries + 1))
        picked=$(echo "$urls" | sed -n "$(( (RANDOM % count) + 1 ))p")
        [ -n "$picked" ] && [ "$picked" != "$last" ] && break
        [ -n "$picked" ] && [ "$count" -le 1 ] && break
    done
    [ -z "$picked" ] && picked="$FALLBACK_URL_DAY"
    echo "$picked" > "$(resolve_kiosk_dir)/last_played_url.txt" 2>/dev/null || true
    echo "$picked"
}

is_online() {
    # ICMP is filtered on some Wi-Fi networks even when Android reports a
    # validated route and HTTPS works. Prefer the cheap ping checks, then use
    # a bounded HTTPS probe so NewPipe is not incorrectly forced into the
    # offline VLC path while the tablet is genuinely online.
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && return 0
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && return 0
    local curl_bin="${PREFIX:-/data/data/com.termux/files/usr}/bin/curl"
    [ -x "$curl_bin" ] || curl_bin=$(command -v curl 2>/dev/null || true)
    [ -n "$curl_bin" ] || return 1
    "$curl_bin" -fsS -o /dev/null --connect-timeout 3 --max-time 6 \
        https://www.google.com/generate_204 >/dev/null 2>&1 && return 0
    "$curl_bin" -fsS -o /dev/null --connect-timeout 3 --max-time 6 \
        https://www.youtube.com >/dev/null 2>&1 && return 0
    return 1
}

acquire_play_lock() {
    local lockdir
    lockdir="$(resolve_kiosk_dir)/.play_lock"
    if mkdir "$lockdir" 2>/dev/null; then
        date +%s > "$lockdir/ts" 2>/dev/null || true
        return 0
    fi
    local ts now age=999
    ts=$(cat "$lockdir/ts" 2>/dev/null | tr -d '\r')
    now=$(date +%s)
    [ -n "$ts" ] && age=$(( now - ts ))
    if [ "$age" -gt 100 ]; then
        rm -rf "$lockdir" 2>/dev/null || true
        mkdir "$lockdir" 2>/dev/null || return 1
        date +%s > "$lockdir/ts" 2>/dev/null || true
        return 0
    fi
    return 1
}

release_play_lock() {
    rm -rf "$(resolve_kiosk_dir)/.play_lock" 2>/dev/null || true
    rm -rf "${HOME}/Kiosk/.play_lock" 2>/dev/null || true
}

enforce_fullscreen_system() {
    settings put global policy_control immersive.full=${NEWPIPE_PKG} 2>/dev/null || true
    settings put system accelerometer_rotation 0 2>/dev/null || true
    settings put system user_rotation 0 2>/dev/null || true
    input keyevent KEYCODE_WAKEUP 2>/dev/null || true
}

# Termux cannot read detailed media-session state on this tablet. Kiosk
# Helper's music-active signal is the reliable UID-safe playback signal; in
# subscriptions-only mode rival media packages are stopped before launch.
newpipe_playback_detected() {
    if dumpsys media_session 2>/dev/null | grep -q 'org.schabi.newpipe' && \
       dumpsys media_session 2>/dev/null | grep -qE 'state=3|state=6'; then
        return 0
    fi
    if [ "${SUBSCRIPTIONS_ONLY:-0}" = "1" ] && type kiosk_helper >/dev/null 2>&1 && \
       [ "$(kiosk_helper is-music-active 2>/dev/null)" = "true" ]; then
        return 0
    fi
    return 1
}

newpipe_player_ui_fullscreen_once() {
    # Player-level fullscreen is now owned by the bound Kiosk Booter
    # accessibility watchdog. Termux's `am` wrapper can block in an
    # app_process child, so the playback controller must not wait on a shell
    # broadcast for this UI-only repair.
    enforce_fullscreen_system
    return 0
}

enter_fullscreen_player_ui() {
    sleep 5
    newpipe_player_ui_fullscreen_once
    sleep 2
    release_play_lock
}

# Reassert fullscreen without reopening the stream. NewPipe can restore the
# video in its detail surface after a boot, a foreground reassert, or a
# transient network change even while the media session remains playing.
ensure_fullscreen_player_ui() {
    (
        sleep 1
        newpipe_player_ui_fullscreen_once
    ) >/dev/null 2>&1 &
}

# Subscription-only mode launches a subscribed channel and presses Play All.
# If the live channel endpoint is unavailable, fall back to NewPipe's locally
# cached "What's New / All" subscription feed, which keeps the imported
# subscription set and its auto-enqueue behavior in the app itself.
launch_newpipe_cached_subscription_feed() {
    local main="${NEWPIPE_PKG}/.MainActivity"
    enforce_fullscreen_system
    am force-stop "$NEWPIPE_PKG" 2>/dev/null || true
    sleep 1
    kiosk_start_activity am start -n "$main" --ez fullscreen true -f 0x10000000 >/dev/null 2>&1 || true
    sleep 4
    kiosk_touch_unlock 2>/dev/null || true
    # MainActivity can restore the last channel fragment after a force-stop.
    # Return to the imported Subscriptions screen before selecting the All
    # group; otherwise the fixed feed-item coordinate lands on a channel page.
    uiautomator dump "${HOME}/Kiosk/feed_state.xml" >/dev/null 2>&1 || true
    if grep -q 'channel_metadata' "${HOME}/Kiosk/feed_state.xml" 2>/dev/null; then
    kiosk_tap 32 56
        sleep 3
    fi
    # MainActivity opens the imported Subscriptions screen. The All group is
    # the second group card on this 1024x600 tablet; the first feed item is
    # selected only after the cached feed is visible.
    kiosk_tap 175 175
    sleep 5
    kiosk_tap 128 230
    sleep 8
    if newpipe_playback_detected; then
        echo "cached:all" > "$(resolve_kiosk_dir)/last_subscription_channel.txt" 2>/dev/null || true
        kiosk_touch_lock 2>/dev/null || true
        enter_fullscreen_player_ui
        date +%s > "$(resolve_kiosk_dir)/last_launch_epoch.txt" 2>/dev/null || true
        release_play_lock
        echo "cached subscription feed reached playback" >> "${HOME}/newpipe_24x7.log" 2>/dev/null || true
        return 0
    fi
    kiosk_touch_lock 2>/dev/null || true
    echo "cached subscription feed did not reach playback" >> "${HOME}/newpipe_24x7.log" 2>/dev/null || true
    return 1
}

# Subscription-only mode always launches a subscribed channel and presses
# Play All. The phase schedule is still used by volume/brightness services.
launch_newpipe_channel_autoplay() {
    local phase ch
    phase=$(current_phase)
    enforce_fullscreen_system

    if [ "${SUBSCRIPTIONS_ONLY:-0}" != "1" ]; then
        case "$phase" in
            BEDTIME|NIGHT)
                launch_newpipe_video "$(get_playlist_url)"
                return 0
                ;;
        esac
    fi

    ch=$(get_subscription_channel_url)
    echo "$ch" > "$(resolve_kiosk_dir)/last_subscription_channel.txt" 2>/dev/null || true
    echo "$ch" > "$(resolve_kiosk_dir)/last_played_url.txt" 2>/dev/null || true
    am force-stop "$NEWPIPE_PKG" 2>/dev/null || true
    sleep 1
    if ! kiosk_start_activity am start -a android.intent.action.VIEW -d "$ch" \
        -n "${NEWPIPE_PKG}/.RouterActivity" -f 0x10000000 \
        -e autoplay true -e fullscreen true >/dev/null 2>&1; then
        kiosk_start_activity am start -a android.intent.action.VIEW -d "$ch" \
            -n "${NEWPIPE_PKG}/.RouterActivity" -f 0x10000000 >/dev/null 2>&1 || true
    fi
    sleep 6
    kiosk_touch_unlock 2>/dev/null || true
    # Play All on channel page (P7 ~300,288)
    kiosk_tap 300 288
    sleep 1
    kiosk_tap 280 270
    sleep 2
    kiosk_tap 400 380
    sleep 4
    if newpipe_playback_detected; then
        kiosk_touch_lock 2>/dev/null || true
        enter_fullscreen_player_ui
        date +%s > "$(resolve_kiosk_dir)/last_launch_epoch.txt" 2>/dev/null || true
        release_play_lock
        return 0
    fi
    kiosk_touch_lock 2>/dev/null || true
    rm -f "$(resolve_kiosk_dir)/last_launch_epoch.txt" 2>/dev/null || true
    echo "subscription channel did not reach playback: $ch" >> "${HOME}/newpipe_24x7.log" 2>/dev/null || true
    if [ "$phase" = "BEDTIME" ] || [ "$phase" = "NIGHT" ]; then
        echo "sleep channel fallback: ${SLEEP_FALLBACK_URL:-$FALLBACK_URL_BED}" >> "${HOME}/newpipe_24x7.log" 2>/dev/null || true
        launch_newpipe_video "${SLEEP_FALLBACK_URL:-$FALLBACK_URL_BED}"
        return 0
    fi
    # NewPipe can retain a locally cached All-subscriptions feed even when
    # the live channel page currently returns Network error.
    if launch_newpipe_cached_subscription_feed; then
        return 0
    fi
    # A feed can load successfully without creating a player on this NewPipe
    # tablet build. Always finish with a concrete video URL so the playback
    # controller has a player surface for the Kiosk Booter fullscreen watchdog
    # to promote.
    launch_newpipe_video "$(get_playlist_url)"
}

launch_newpipe_video() {
    local url="${1:-}"
    [ -z "$url" ] && url=$(get_playlist_url)
    enforce_fullscreen_system
    am force-stop "$NEWPIPE_PKG" 2>/dev/null || true
    sleep 1
    kiosk_start_activity am start -a android.intent.action.VIEW -d "$url" \
        -n ${NEWPIPE_PKG}/.RouterActivity \
        -e fullscreen "true" --ez autoplay true -f 0x10000000 >/dev/null 2>&1 || true
    echo "$url" > "$(resolve_kiosk_dir)/last_played_url.txt" 2>/dev/null || true
    date +%s > "$(resolve_kiosk_dir)/last_launch_epoch.txt" 2>/dev/null || true
    enter_fullscreen_player_ui
}

launch_newpipe_subscriptions_feed() {
    launch_newpipe_channel_autoplay
}

# mode: channel|video|auto — auto picks by phase
play_next_coordinated() {
    local reason="${1:-manual}"
    local force_stop="${2:-0}"
    local mode="${3:-auto}"
    local phase

    if ! acquire_play_lock; then
        return 1
    fi

    phase=$(write_phase_file)
    if [ "$force_stop" = "1" ]; then
        am force-stop "$NEWPIPE_PKG" 2>/dev/null || true
        sleep 1
    fi

    if [ "$mode" = "auto" ]; then
        if [ "${SUBSCRIPTIONS_ONLY:-0}" = "1" ]; then
            mode="channel"
        else
            case "$phase" in
                BEDTIME|NIGHT) mode="video" ;;
                *) mode="channel" ;;
            esac
        fi
    fi

    local rc=0
    case "$mode" in
        video) launch_newpipe_video "$(get_playlist_url)" || rc=$? ;;
        channel|*) launch_newpipe_channel_autoplay || rc=$? ;;
    esac

    if [ "$rc" -ne 0 ]; then
        release_play_lock
        return "$rc"
    fi

    echo "$(date -Iseconds 2>/dev/null || date) reason=$reason phase=$phase mode=$mode" \
        >> "$(resolve_kiosk_dir)/play_events.log" 2>/dev/null || true
    return 0
}
