#!/data/data/com.termux/files/usr/bin/bash
# On-tablet shortcut to toggle Parent Mode / Child Kiosk Mode

PARENT_FILE="/sdcard/Kiosk/parent_mode.txt"

kiosk_helper() {
    LD_LIBRARY_PATH="" LD_PRELOAD="" CLASSPATH=/data/local/tmp/kioskhelper.jar app_process / KioskHelper "$@"
}

if [ -f "$PARENT_FILE" ] && [ "$(cat $PARENT_FILE 2>/dev/null)" = "true" ]; then
    rm -f "$PARENT_FILE"
    kiosk_helper write-setting secure status_bar_hidden 1 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure home_key_disabled 1 >/dev/null 2>&1 || true
    am toast -s "text:Switched to Child Kiosk Mode (NewPipe Only)" >/dev/null 2>&1 || true
    am start -n org.schabi.newpipe/.MainActivity >/dev/null 2>&1 || true
else
    mkdir -p /sdcard/Kiosk 2>/dev/null || true
    echo "true" > "$PARENT_FILE"
    kiosk_helper write-setting secure status_bar_hidden 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure navbar_hidden 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure home_key_disabled 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting secure back_key_disabled 0 >/dev/null 2>&1 || true
    kiosk_helper write-setting global power_menu_disabled 0 >/dev/null 2>&1 || true
    am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
    am toast -s "text:PARENT MODE UNLOCKED! Full tablet controls enabled." >/dev/null 2>&1 || true
fi
