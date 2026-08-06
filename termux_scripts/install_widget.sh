#!/data/data/com.termux/files/usr/bin/bash
# Installer — run from Termux to set up ~/.shortcuts/ParentToggle.sh
SRC=/sdcard/Kiosk/ParentToggle.sh
DEST=/data/data/com.termux/files/home/.shortcuts/ParentToggle.sh
mkdir -p /data/data/com.termux/files/home/.shortcuts
chmod 700 /data/data/com.termux/files/home/.shortcuts
cp "$SRC" "$DEST" && chmod 755 "$DEST" && echo "SUCCESS: $DEST installed" || echo "FAIL: could not install"
echo "Current shortcuts:"
ls -la /data/data/com.termux/files/home/.shortcuts/
# Set default PIN if not already set
PIN_FILE=/data/data/com.termux/files/home/.kiosk_pin
[ ! -f "$PIN_FILE" ] && echo "1234" > "$PIN_FILE" && echo "Default PIN set to 1234"
echo ""
echo "DONE. Now add Termux:Widget to your home screen to use the toggle."
