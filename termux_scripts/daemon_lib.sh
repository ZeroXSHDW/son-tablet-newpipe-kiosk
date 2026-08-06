#!/data/data/com.termux/files/usr/bin/bash
# Shared single-instance helpers — NEVER trust PID alone (Android reuses PIDs)

# Return 0 if pidfile points at a live process whose cmdline contains needle
daemon_is_running() {
    local pidfile="$1"
    local needle="$2"
    local old cmd
    [ -f "$pidfile" ] || return 1
    old=$(cat "$pidfile" 2>/dev/null | tr -d '\r\n ')
    [ -n "$old" ] || return 1
    [ "$old" -eq "$old" ] 2>/dev/null || return 1
    kill -0 "$old" 2>/dev/null || return 1
    cmd=$(tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null || true)
    # If cmdline is unavailable due SELinux / procfs privacy, still keep the
    # instance healthy as long as PID and liveness checks pass.
    [ -z "$cmd" ] && return 0
    case "$cmd" in
        *"$needle"*) ;;
        *) return 1 ;;
    esac
    return 0
}

# Kill stale/duplicate script processes so a restart always normalizes to one
# active instance. This is safe because it is only used for the known kiosk
# daemons that self-restart through this control path.
daemon_kill_duplicates() {
    local needle="$1"
    local pids
    local target="/data/data/com.termux/files/home/$needle"
    pids=$(ps -ef 2>/dev/null | grep -F "bash $target" | grep -v "grep" | awk '{print $2}' || true)
    [ -z "$pids" ] && return 0

    for pid in $pids; do
        [ -z "$pid" ] && continue
        # Never kill the caller if it somehow appears in this lookup.
        [ "$pid" = "$$" ] && continue
        kill -9 "$pid" >/dev/null 2>&1 || true
    done
}

# Claim single instance: exit 0 if another real instance owns the lock
# Usage: daemon_claim "$PID_FILE" "newpipe_24x7.sh" || exit 0
daemon_claim() {
    local pidfile="$1"
    local needle="$2"
    if daemon_is_running "$pidfile" "$needle"; then
        return 1  # already running (caller should exit)
    fi
    # If a stale copy is still alive, clean it before this instance claims.
    daemon_kill_duplicates "$needle"
    echo $$ > "$pidfile"
    return 0
}

daemon_release() {
    local pidfile="$1"
    rm -f "$pidfile" 2>/dev/null || true
}

# The accessibility overlay blocks real child-mode touch/button input. Any
# scripted NewPipe UI recovery must use this short, explicit handshake so the
# overlay never stays open after a failed command.
kiosk_touch_unlock() {
    mkdir -p "${HOME}/Kiosk" 2>/dev/null || true
    printf 'unlocked\n' > "${HOME}/Kiosk/touch_mode.txt" 2>/dev/null || true
    mkdir -p /sdcard/Kiosk 2>/dev/null || true
    if [ -d /sdcard ] && [ -w /sdcard/Kiosk ] 2>/dev/null; then
        printf 'unlocked\n' > /sdcard/Kiosk/touch_mode.txt 2>/dev/null || true
    fi
    # Android's `am` can hang indefinitely when a short-lived app_process
    # receiver is being torn down on this firmware. Never let that stall a
    # watchdog or prevent the overlay handshake from being re-entered.
    /system/bin/timeout 5 am broadcast --user 0 -a com.android.kioskbooter.TOUCH_UNLOCK -n com.android.kioskbooter/.BootReceiver >/dev/null 2>&1 || true
    sleep 1
}

kiosk_touch_lock() {
    mkdir -p "${HOME}/Kiosk" 2>/dev/null || true
    printf 'locked\n' > "${HOME}/Kiosk/touch_mode.txt" 2>/dev/null || true
    mkdir -p /sdcard/Kiosk 2>/dev/null || true
    if [ -d /sdcard ] && [ -w /sdcard/Kiosk ] 2>/dev/null; then
        printf 'locked\n' > /sdcard/Kiosk/touch_mode.txt 2>/dev/null || true
    fi
    /system/bin/timeout 5 am broadcast --user 0 -a com.android.kioskbooter.TOUCH_LOCK -n com.android.kioskbooter/.BootReceiver >/dev/null 2>&1 || true
}

kiosk_tap() {
    /system/bin/timeout 5 am broadcast --user 0 -a com.android.kioskbooter.TAP \
        -n com.android.kioskbooter/.BootReceiver \
        --ei x "$1" --ei y "$2" >/dev/null 2>&1 || true
    sleep 0.25
}

kiosk_start_activity() {
    # Start foreground activity with Kiosk helper first (fast path), then always
    # force a direct shell start as fallback so helper no-op cannot block launch.
    if [ "$1" != "am" ] || [ "$2" != "start" ]; then
        echo "kiosk_start_activity expects am start ..." >&2
        return 1
    fi
    shift 2

    local rc=1
    # MainActivity must be handed off by Kiosk Booter on this tablet. A direct
    # `am start` from Termux can report success while leaving Termux focused.
    # Use the receiver's foreground-capable context for this specific fallback.
    local skip_helper=0 use_booter_main=0 argstr
    argstr="$*"
    case "$argstr" in
        *"org.schabi.newpipe/.MainActivity"*)
            skip_helper=1
            use_booter_main=1
            ;;
        *"org.schabi.newpipe/"*)
            # The KioskHelper app_process path can remain stuck on this
            # firmware. NewPipe RouterActivity starts correctly through the
            # bounded shell `am start` fallback, so never put the playback
            # controller behind that unbounded helper.
            skip_helper=1
            ;;
    esac
    if [ "$use_booter_main" -eq 1 ]; then
        /system/bin/timeout 5 am broadcast --user 0 -a com.android.kioskbooter.START_ACTIVITY \
            -n com.android.kioskbooter/.BootReceiver \
            --es component org.schabi.newpipe/.MainActivity \
            --es action android.intent.action.MAIN >/dev/null 2>&1 || true
        return 0
    fi
    if [ "$skip_helper" -eq 0 ] && type kiosk_helper >/dev/null 2>&1; then
        kiosk_helper am-start "$@" >/dev/null 2>&1 || true
    fi
    /system/bin/timeout 8 am start "$@" >/dev/null 2>&1
    rc=$?
    return $rc
}

kiosk_media_play() {
    /system/bin/timeout 5 am broadcast --user 0 -a com.android.kioskbooter.MEDIA_PLAY \
        -n com.android.kioskbooter/.BootReceiver >/dev/null 2>&1 || true
}
