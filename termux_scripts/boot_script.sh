#!/system/bin/sh

# Set up Termux environment variables
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib

# MacroDroid adds its own 15s delay before calling this script, so only wait 5s here
sleep 5

# Acquire Termux wake lock - only works when running as Termux app user
termux-wake-lock > /dev/null 2>&1 || true

# Determine execution context:
# If HOME is writable, we are running within the Termux app context or as root.
IS_TERMUX_CONTEXT=false
if [ -w "$HOME" ]; then
    IS_TERMUX_CONTEXT=true
fi

# Start background services ONLY when running in Termux context
if [ "$IS_TERMUX_CONTEXT" = "true" ]; then
    # Start background web server if not already running
    if ! pgrep -f "server.sh" >/dev/null 2>&1; then
        nohup bash $HOME/server.sh > $HOME/server.log 2>&1 &
    fi

    # Start background sync loop if not already running
    if ! pgrep -f "sync_wifi.py" >/dev/null 2>&1; then
        nohup sh -c '
        while true; do
          echo "=== Starting sync_wifi.py run at $(date) ==="
          python3 -u $HOME/sync_wifi.py
          echo "=== Sync run finished at $(date). Sleeping for 4 hours... ==="
          sleep 14400
        done
        ' > $HOME/sync_wifi.log 2>&1 &
    fi
fi

STAGE_FALLBACK_URL="https://www.youtube.com/watch?v=2dDpryw3z5w"
LAST_PHASE=""
COUNTER=0

get_online_url() {
    PLAYLIST_FILE="/sdcard/Kiosk/online_playlist.json"
    if [ -f "$PLAYLIST_FILE" ]; then
        URLS=$(grep -o -E 'https://www.youtube.com/watch\?v=[a-zA-Z0-9_-]{11}' "$PLAYLIST_FILE" || true)
        if [ -n "$URLS" ]; then
            COUNT=$(echo "$URLS" | wc -l)
            RANDOM_IDX=$(( (RANDOM % COUNT) + 1 ))
            SELECTED_URL=$(echo "$URLS" | sed -n "${RANDOM_IDX}p")
            echo "$SELECTED_URL"
            return 0
        fi
    fi
    
    # Fallback URL from active_stage_url.txt if present
    if [ -f "/sdcard/Kiosk/active_stage_url.txt" ]; then
        file_url=$(cat /sdcard/Kiosk/active_stage_url.txt | tr -d '\r' || true)
        if [ -n "$file_url" ]; then
            echo "$file_url"
            return 0
        fi
    fi
    echo "$STAGE_FALLBACK_URL"
}

# Helper to play a random offline video file
play_offline_video() {
    FILES=$(find /sdcard/Movies/ /sdcard/Kiosk/offline_videos/ /sdcard/Download/ -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) 2>/dev/null || true)
    if [ -n "$FILES" ]; then
        COUNT=$(echo "$FILES" | wc -l)
        RANDOM_IDX=$(( (RANDOM % COUNT) + 1 ))
        FILE_PATH=$(echo "$FILES" | sed -n "${RANDOM_IDX}p")
        echo "Playing offline video: $FILE_PATH"
        am start -n com.brouken.player/.PlayerActivity -a android.intent.action.VIEW -d "file://$FILE_PATH" -t "video/*"
    else
        echo "No local videos. Launching educational game..."
        GAMES=("net.gcompris.full/net.gcompris.GComprisActivity" "org.khankids.android/org.khankids.android.MainActivity" "org.pbskids.games/org.pbskids.games.MainActivity" "com.rvappstudios.math.kids.counting/com.rvappstudios.math.kids.counting.MainActivity")
        RANDOM_GAME=${GAMES[$RANDOM % ${#GAMES[@]}]}
        am start -n $RANDOM_GAME || am start -n net.gcompris.full/net.gcompris.GComprisActivity
    fi
}

# Helper to play morning lesson video
play_morning_video() {
    FILES=$(find /sdcard/Movies/ /sdcard/Kiosk/offline_videos/ /sdcard/Download/ -type f \( -iname "*preschool*" -o -iname "*learning*" -o -iname "*phonics*" -o -iname "*words*" -o -iname "*circle*" -o -iname "*sentences*" \) \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) 2>/dev/null || true)
    if [ -n "$FILES" ]; then
        COUNT=$(echo "$FILES" | wc -l)
        RANDOM_IDX=$(( (RANDOM % COUNT) + 1 ))
        FILE_PATH=$(echo "$FILES" | sed -n "${RANDOM_IDX}p")
        echo "Playing morning lesson video: $FILE_PATH"
        am start -n com.brouken.player/.PlayerActivity -a android.intent.action.VIEW -d "file://$FILE_PATH" -t "video/*"
    else
        play_offline_video
    fi
}

# Helper to play a relaxing/bedtime offline video
play_relaxing_video() {
    FILES=$(find /sdcard/Movies/ /sdcard/Kiosk/offline_videos/ /sdcard/Download/ -type f \( -iname "*bedtime*" -o -iname "*sleep*" -o -iname "*lullaby*" \) \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) 2>/dev/null || true)
    if [ -n "$FILES" ]; then
        COUNT=$(echo "$FILES" | wc -l)
        RANDOM_IDX=$(( (RANDOM % COUNT) + 1 ))
        FILE_PATH=$(echo "$FILES" | sed -n "${RANDOM_IDX}p")
        echo "Playing relaxing video: $FILE_PATH"
        am start -n com.brouken.player/.PlayerActivity -a android.intent.action.VIEW -d "file://$FILE_PATH" -t "video/*"
    else
        play_offline_video
    fi
}

# Helper to play quiet sleep lullaby video
play_sleep_video() {
    FILES=$(find /sdcard/Movies/ /sdcard/Kiosk/offline_videos/ /sdcard/Download/ -type f \( -iname "*sleep*" -o -iname "*lullaby*" -o -iname "*whitenoise*" \) \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) 2>/dev/null || true)
    if [ -n "$FILES" ]; then
        COUNT=$(echo "$FILES" | wc -l)
        RANDOM_IDX=$(( (RANDOM % COUNT) + 1 ))
        FILE_PATH=$(echo "$FILES" | sed -n "${RANDOM_IDX}p")
        echo "Playing sleep video: $FILE_PATH"
        am start -n com.brouken.player/.PlayerActivity -a android.intent.action.VIEW -d "file://$FILE_PATH" -t "video/*"
    else
        play_relaxing_video
    fi
}

# Master relauncher logic by phase
relaunch_for_phase() {
    PHASE="$1"
    if [ "$PHASE" = "MORNING" ]; then
        play_morning_video
    elif [ "$PHASE" = "LEARNING" ]; then
        echo "Learning phase: Launching educational game (MacroDroid will trigger NewPipe popup)..."
        GAMES=("net.gcompris.full/net.gcompris.GComprisActivity" "org.khankids.android/org.khankids.android.MainActivity" "org.pbskids.games/org.pbskids.games.MainActivity" "com.rvappstudios.math.kids.counting/com.rvappstudios.math.kids.counting.MainActivity")
        RANDOM_GAME=${GAMES[$RANDOM % ${#GAMES[@]}]}
        am start -n $RANDOM_GAME || am start -n net.gcompris.full/net.gcompris.GComprisActivity
    elif [ "$PHASE" = "RELAXING" ]; then
        play_relaxing_video
    elif [ "$PHASE" = "SLEEP" ]; then
        play_sleep_video
    fi
}

## 1. Determine active phase
HM=$(date +%H%M)
HM=$(echo "$HM" | sed 's/^0*//')
[ -z "$HM" ] && HM=0

if [ "$HM" -ge 600 ] && [ "$HM" -lt 700 ]; then
    PHASE="MORNING"
elif [ "$HM" -ge 700 ] && [ "$HM" -lt 1900 ]; then
    PHASE="LEARNING"
elif [ "$HM" -ge 1900 ] && [ "$HM" -lt 2030 ]; then
    PHASE="RELAXING"
else
    PHASE="SLEEP"
fi

# 2. Launch content for the active phase and exit
# Only launch activities when called from shell/MacroDroid context.
# Termux app-context calls only manage background services (which is handled by the main orchestrator).
if [ "$IS_TERMUX_CONTEXT" = "true" ]; then
    echo "Running in Termux app context. Skipping content relaunch."
    exit 0
fi

echo "Running in external context (MacroDroid/Shell). Launching content for phase: $PHASE"
relaunch_for_phase "$PHASE"
exit 0
