#!/system/bin/sh
set -eu

STATE_DIR="/data/data/com.termux/files/home"
STATE_FILE="$STATE_DIR/volume_lock_state.txt"
LOCK_DURATION=300

mkdir -p "$STATE_DIR"

now=$(date +%s)
if [ -f "$STATE_FILE" ]; then
    state=$(sed -n '1p' "$STATE_FILE" 2>/dev/null || echo LOCKED)
    unlock_until=$(sed -n '2p' "$STATE_FILE" 2>/dev/null || echo 0)
else
    state="LOCKED"
    unlock_until="0"
fi

if [ "$state" = "LOCKED" ] || [ -z "$unlock_until" ] || [ "$unlock_until" -le "$now" ]; then
    new_unlock_until=$((now + LOCK_DURATION))
    printf 'UNLOCKED\n%s\n' "$new_unlock_until" > "$STATE_FILE"
    am toast -s "text:Volume unlocked for 5 minutes" >/dev/null 2>&1 || true
else
    printf 'LOCKED\n0\n' > "$STATE_FILE"
    am toast -s "text:Volume locked again" >/dev/null 2>&1 || true
fi
