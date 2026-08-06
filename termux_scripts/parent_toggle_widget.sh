#!/data/data/com.termux/files/usr/bin/bash
#
# PARENT MODE TOGGLE WIDGET v2.0
# Place in ~/.shortcuts/ for Termux:Widget home screen button
# PIN-protected so child can't accidentally trigger it
#
# USAGE: Tap the home screen widget icon — enter PIN when prompted
#

set +e

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:/system/xbin:$PATH

PARENT_FILE="/sdcard/Kiosk/parent_mode.txt"
PIN_FILE="/data/data/com.termux/files/home/.kiosk_pin"
LOG_FILE="/data/data/com.termux/files/home/parent_toggle.log"

# ── Default PIN (change this!) ──────────────────────────────────────────────
DEFAULT_PIN="1234"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper "$@"
}

# ── Load saved PIN or use default ────────────────────────────────────────────
if [ -f "$PIN_FILE" ]; then
    CORRECT_PIN=$(cat "$PIN_FILE" 2>/dev/null | tr -d '[:space:]')
else
    CORRECT_PIN="$DEFAULT_PIN"
    echo "$DEFAULT_PIN" > "$PIN_FILE"
fi

# ── Determine current mode label ─────────────────────────────────────────────
if [ -f "$PARENT_FILE" ] && [ "$(cat $PARENT_FILE 2>/dev/null)" = "true" ]; then
    CURRENT_MODE="PARENT MODE"
    NEXT_ACTION="Lock tablet → Child Kiosk"
    EMOJI="🔓"
else
    CURRENT_MODE="CHILD KIOSK"
    NEXT_ACTION="Unlock tablet → Parent Mode"
    EMOJI="🔒"
fi

# ── PIN Prompt via termux-dialog (requires Termux:API) ───────────────────────
PIN_RESULT=""
if command -v termux-dialog >/dev/null 2>&1; then
    # Use termux-dialog for a graphical PIN entry
    DIALOG_OUTPUT=$(termux-dialog -l -m "Parent PIN required.\nCurrent: $EMOJI $CURRENT_MODE\nAction: $NEXT_ACTION" 2>/dev/null)
    PIN_RESULT=$(echo "$DIALOG_OUTPUT" | grep -o '"text":"[^"]*"' | sed 's/"text":"//;s/"//')
else
    # Fallback: read from stdin (works if terminal is open)
    echo ""
    echo "═══════════════════════════════════"
    echo "  $EMOJI  Current: $CURRENT_MODE"
    echo "  Action: $NEXT_ACTION"
    echo "═══════════════════════════════════"
    echo -n "  Enter Parent PIN: "
    read -s PIN_RESULT
    echo ""
fi

# ── Validate PIN ─────────────────────────────────────────────────────────────
if [ "$PIN_RESULT" != "$CORRECT_PIN" ]; then
    log "WARN: Wrong PIN attempt - access denied"
    if command -v termux-toast >/dev/null 2>&1; then
        termux-toast -s "❌ Wrong PIN! Access denied."
    fi
    exit 1
fi

log "INFO: PIN verified. Toggling parent mode..."

# ── TOGGLE LOGIC ─────────────────────────────────────────────────────────────
if [ -f "$PARENT_FILE" ] && [ "$(cat $PARENT_FILE 2>/dev/null)" = "true" ]; then
    # ── DISABLE Parent Mode → Activate Child Kiosk ───────────────────────────
    rm -f "$PARENT_FILE"
    
    # Re-enable kiosk restrictions
    kiosk_helper write-setting secure status_bar_hidden 1 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure home_key_disabled 1 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure navbar_hidden 1 >/dev/null 2>&1 || true
    kiosk_helper write-setting global policy_control "immersive.full=*" >/dev/null 2>&1 || true
    
    # Return to NewPipe
    am force-stop com.android.settings >/dev/null 2>&1 || true
    am start -n org.schabi.newpipe/.MainActivity >/dev/null 2>&1 || true
    
    log "SUCCESS: Child Kiosk Mode ACTIVATED"
    
    if command -v termux-toast >/dev/null 2>&1; then
        termux-toast -s "🔒 Child Kiosk Mode ON — NewPipe Only"
    fi

else
    # ── ENABLE Parent Mode → Full Tablet Access ───────────────────────────────
    mkdir -p /sdcard/Kiosk 2>/dev/null || true
    echo "true" > "$PARENT_FILE"
    
    # Restore all navigation & status bar
    kiosk_helper write-setting secure status_bar_hidden 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure navbar_hidden 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure home_key_disabled 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure back_key_disabled 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting global power_menu_disabled 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting global policy_control none >/dev/null 2>&1 || true
    
    # Broadcast to close any kiosk overlays
    am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
    
    log "SUCCESS: Parent Mode ACTIVATED — full tablet unlocked"
    
    if command -v termux-toast >/dev/null 2>&1; then
        termux-toast -s "🔓 PARENT MODE ON — Full Access Unlocked!"
    fi
fi
