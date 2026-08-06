#!/data/data/com.termux/files/usr/bin/bash
# Authoritative kiosk configuration. Runtime scripts source this file so the
# schedule and recovery policy cannot drift between independent copies.

KIOSK_CONFIG_VERSION="2026-08-06.1"

# Playback stays on the locally imported NewPipe subscriptions. Bedtime/night
# intentionally use the sleep channel and fallback below.
SUBSCRIPTIONS_ONLY=1
SLEEP_AUTOPLAY=1
SLEEP_CHANNEL_URL="https://www.youtube.com/@edubuzzkids/videos"
SLEEP_FALLBACK_URL="https://www.youtube.com/watch?v=OyUoskE7Ogk"

# Device-local schedule (HHMM).
MORNING_START=600
LEARNING_START=900
RELAXING_START=1800
BEDTIME_START=2030
NIGHT_START=2230

# Android media stream range on this tablet is 0..15. Day is 12/15 (about 80%)
# and bedtime/night sleep playback is 3/15.
DAY_VOLUME=12
BEDTIME_VOLUME=3
NIGHT_VOLUME=3

MORNING_BRIGHTNESS=160
LEARNING_BRIGHTNESS=180
RELAXING_BRIGHTNESS=120
BEDTIME_BRIGHTNESS=40
NIGHT_BRIGHTNESS=25

# Recovery is conservative: NewPipe owns playback/auto-next. The controller
# only relaunches after sustained inactivity and never rotates healthy playback.
PLAYBACK_CHECK_SEC=20
PLAYBACK_GRACE_SEC=180
PLAYBACK_IDLE_RECOVERY_SEC=60
FORCED_ROTATION_SEC=0

NEWPIPE_PACKAGE="org.schabi.newpipe"
CALM_WALLPAPER_COMPONENT="com.android.calmwallpaper/.CalmWallpaperService"

kiosk_current_phase() {
    local hm
    hm=$(date +%H%M 2>/dev/null | tr -d '\r' | sed 's/^0*//')
    [ -n "$hm" ] || hm=0
    if [ "$hm" -ge "$MORNING_START" ] && [ "$hm" -lt "$LEARNING_START" ]; then
        echo "MORNING"
    elif [ "$hm" -ge "$LEARNING_START" ] && [ "$hm" -lt "$RELAXING_START" ]; then
        echo "LEARNING"
    elif [ "$hm" -ge "$RELAXING_START" ] && [ "$hm" -lt "$BEDTIME_START" ]; then
        echo "RELAXING"
    elif [ "$hm" -ge "$BEDTIME_START" ] && [ "$hm" -lt "$NIGHT_START" ]; then
        echo "BEDTIME"
    else
        echo "NIGHT"
    fi
}

kiosk_volume_for_phase() {
    case "$1" in
        NIGHT) echo "$NIGHT_VOLUME" ;;
        BEDTIME) echo "$BEDTIME_VOLUME" ;;
        MORNING|LEARNING|RELAXING|*) echo "$DAY_VOLUME" ;;
    esac
}

kiosk_brightness_for_phase() {
    case "$1" in
        MORNING) echo "$MORNING_BRIGHTNESS" ;;
        LEARNING) echo "$LEARNING_BRIGHTNESS" ;;
        RELAXING) echo "$RELAXING_BRIGHTNESS" ;;
        BEDTIME) echo "$BEDTIME_BRIGHTNESS" ;;
        NIGHT) echo "$NIGHT_BRIGHTNESS" ;;
        *) echo "$LEARNING_BRIGHTNESS" ;;
    esac
}

# Validate the authoritative configuration before any daemon starts. This is
# intentionally shell-only so the same gate can run on the tablet and from
# deployment/repair paths. A bad value must fail closed instead of silently
# changing the child's schedule, volume, or brightness.
kiosk_validate_hhmm() {
    local name="$1" value="$2" numeric
    case "$value" in
        ''|*[!0-9]*) echo "invalid $name=$value (expected HHMM)" >&2; return 1 ;;
    esac
    numeric=$(echo "$value" | sed 's/^0*//')
    [ -n "$numeric" ] || numeric=0
    if [ "$numeric" -gt 2359 ] || [ $((numeric % 100)) -ge 60 ]; then
        echo "invalid $name=$value (expected 0000..2359)" >&2
        return 1
    fi
    return 0
}

kiosk_hhmm_number() {
    local numeric
    numeric=$(echo "$1" | sed 's/^0*//')
    [ -n "$numeric" ] || numeric=0
    echo "$numeric"
}

kiosk_validate_range() {
    local name="$1" value="$2" maximum="$3"
    case "$value" in
        ''|*[!0-9]*) echo "invalid $name=$value (expected 0..$maximum)" >&2; return 1 ;;
    esac
    if [ "$value" -gt "$maximum" ]; then
        echo "invalid $name=$value (expected 0..$maximum)" >&2
        return 1
    fi
    return 0
}

kiosk_validate_config() {
    local errors=0 schedule_valid=1
    local morning learning relaxing bedtime night

    kiosk_validate_hhmm MORNING_START "$MORNING_START" || { errors=$((errors + 1)); schedule_valid=0; }
    kiosk_validate_hhmm LEARNING_START "$LEARNING_START" || { errors=$((errors + 1)); schedule_valid=0; }
    kiosk_validate_hhmm RELAXING_START "$RELAXING_START" || { errors=$((errors + 1)); schedule_valid=0; }
    kiosk_validate_hhmm BEDTIME_START "$BEDTIME_START" || { errors=$((errors + 1)); schedule_valid=0; }
    kiosk_validate_hhmm NIGHT_START "$NIGHT_START" || { errors=$((errors + 1)); schedule_valid=0; }

    if [ "$schedule_valid" -eq 1 ]; then
        morning=$(kiosk_hhmm_number "$MORNING_START")
        learning=$(kiosk_hhmm_number "$LEARNING_START")
        relaxing=$(kiosk_hhmm_number "$RELAXING_START")
        bedtime=$(kiosk_hhmm_number "$BEDTIME_START")
        night=$(kiosk_hhmm_number "$NIGHT_START")
        if [ "$morning" -ge "$learning" ] || [ "$learning" -ge "$relaxing" ] ||
           [ "$relaxing" -ge "$bedtime" ] || [ "$bedtime" -ge "$night" ] ||
           [ "$night" -ge 2400 ]; then
            echo "phase schedule is not strictly ordered" >&2
            errors=$((errors + 1))
        fi
    fi

    kiosk_validate_range DAY_VOLUME "$DAY_VOLUME" 15 || errors=$((errors + 1))
    kiosk_validate_range BEDTIME_VOLUME "$BEDTIME_VOLUME" 15 || errors=$((errors + 1))
    kiosk_validate_range NIGHT_VOLUME "$NIGHT_VOLUME" 15 || errors=$((errors + 1))
    kiosk_validate_range MORNING_BRIGHTNESS "$MORNING_BRIGHTNESS" 255 || errors=$((errors + 1))
    kiosk_validate_range LEARNING_BRIGHTNESS "$LEARNING_BRIGHTNESS" 255 || errors=$((errors + 1))
    kiosk_validate_range RELAXING_BRIGHTNESS "$RELAXING_BRIGHTNESS" 255 || errors=$((errors + 1))
    kiosk_validate_range BEDTIME_BRIGHTNESS "$BEDTIME_BRIGHTNESS" 255 || errors=$((errors + 1))
    kiosk_validate_range NIGHT_BRIGHTNESS "$NIGHT_BRIGHTNESS" 255 || errors=$((errors + 1))

    case "$SUBSCRIPTIONS_ONLY" in 0|1) ;; *) echo "invalid SUBSCRIPTIONS_ONLY=$SUBSCRIPTIONS_ONLY" >&2; errors=$((errors + 1));; esac
    case "$SLEEP_AUTOPLAY" in 0|1) ;; *) echo "invalid SLEEP_AUTOPLAY=$SLEEP_AUTOPLAY" >&2; errors=$((errors + 1));; esac
    case "$SLEEP_CHANNEL_URL" in http://*|https://*) ;; *) echo "invalid SLEEP_CHANNEL_URL" >&2; errors=$((errors + 1));; esac
    case "$SLEEP_FALLBACK_URL" in http://*|https://*) ;; *) echo "invalid SLEEP_FALLBACK_URL" >&2; errors=$((errors + 1));; esac

    if [ "$errors" -gt 0 ]; then
        echo "KIOSK_CONFIG_INVALID errors=$errors version=$KIOSK_CONFIG_VERSION" >&2
        return 1
    fi
    return 0
}
