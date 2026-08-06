#!/data/data/com.termux/files/usr/bin/bash
# One-shot helper: place import file + open NewPipe for subscription import
# Import path in NewPipe: Subscriptions tab → (menu) Import from previous export
# File: /sdcard/Download/newpipe_subscriptions.json

export PATH=/data/data/com.termux/files/usr/bin:/system/bin:$PATH
SRC_SD=/sdcard/Kiosk/newpipe_subscriptions.json
DST=/sdcard/Download/newpipe_subscriptions.json

mkdir -p /sdcard/Download /sdcard/Kiosk 2>/dev/null || true
[ -f "$SRC_SD" ] && cp -f "$SRC_SD" "$DST" 2>/dev/null || true
[ -f "$HOME/Kiosk/newpipe_subscriptions.json" ] && cp -f "$HOME/Kiosk/newpipe_subscriptions.json" "$DST" 2>/dev/null || true

echo "Import file: $DST"
ls -la "$DST" 2>/dev/null || echo "MISSING import file"

# Open NewPipe main so parent/user can: Subscriptions → ⋮ → Import from previous export
am start -n org.schabi.newpipe/.MainActivity >/dev/null 2>&1 || true
echo "Open NewPipe → Subscriptions → Import → Previous export → pick newpipe_subscriptions.json"
echo "Also enable: Settings → Player → Autoplay next stream = ON, Preferred player = Main"
