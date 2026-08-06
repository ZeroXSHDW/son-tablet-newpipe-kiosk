#!/data/data/com.termux/files/usr/bin/bash
# Installer — run from Termux to set up ~/.shortcuts/ParentToggle.sh
SRC=/sdcard/Kiosk/ParentToggle.sh
DEST=/data/data/com.termux/files/home/.shortcuts/ParentToggle.sh
mkdir -p /data/data/com.termux/files/home/.shortcuts
chmod 700 /data/data/com.termux/files/home/.shortcuts
cp "$SRC" "$DEST" && chmod 755 "$DEST" && echo "SUCCESS: $DEST installed" || echo "FAIL: could not install"
echo "Current shortcuts:"
ls -la /data/data/com.termux/files/home/.shortcuts/
# Require a private PIN; never install a public default credential.
PIN_FILE=/data/data/com.termux/files/home/.kiosk_pin
if [ ! -s "$PIN_FILE" ]; then
  echo "Set a private PIN before using the ParentToggle shortcut:"
  printf "PIN: "
  read -r PIN
  if [ -z "$PIN" ]; then
    echo "FAIL: PIN cannot be empty"
    exit 1
  fi
  umask 077
  printf '%s\n' "$PIN" > "$PIN_FILE"
  chmod 600 "$PIN_FILE"
  echo "Private PIN saved to $PIN_FILE"
fi
echo ""
echo "DONE. Now add Termux:Widget to your home screen to use the toggle."
