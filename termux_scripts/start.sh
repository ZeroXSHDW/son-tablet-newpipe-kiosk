#!/data/data/com.termux/files/usr/bin/bash
# Termux entry → NewPipe 24/7 fullscreen playlist kiosk

set +e

export PATH="/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin:/vendor/bin:$PATH"
export HOME="/data/data/com.termux/files/home"

LOG_FILE="$HOME/startup.log"
BOOT_ORCHESTRATOR="$HOME/boot_orchestrator_v2_integrated.sh"
FALLBACK_24X7="$HOME/newpipe_24x7.sh"

mkdir -p "$HOME" "/sdcard/Kiosk" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [START] $1" | tee -a "$LOG_FILE"
}

log "Boot entrypoint started (NewPipe 24/7)"
sleep 10

if [ -x "$BOOT_ORCHESTRATOR" ] || [ -f "$BOOT_ORCHESTRATOR" ]; then
    chmod 755 "$BOOT_ORCHESTRATOR" 2>/dev/null || true
    log "Launching boot orchestrator"
    exec /data/data/com.termux/files/usr/bin/bash "$BOOT_ORCHESTRATOR"
fi

if [ -f "$FALLBACK_24X7" ]; then
    log "Orchestrator missing; starting newpipe_24x7 directly"
    exec /data/data/com.termux/files/usr/bin/bash "$FALLBACK_24X7"
fi

log "No kiosk scripts found"
exit 1
