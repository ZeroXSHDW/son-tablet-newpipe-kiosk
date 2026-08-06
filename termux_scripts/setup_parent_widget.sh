#!/data/data/com.termux/files/usr/bin/bash
#
# SETUP PARENT WIDGET — Run once via ADB or Termux to install everything
# Sets up Termux:Widget shortcut on the home screen for one-tap Parent Mode toggle
#

set +e

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:/system/xbin:$PATH

SHORTCUTS_DIR="$HOME/.shortcuts"
WIDGET_SCRIPT="$SHORTCUTS_DIR/🔒 Parent Toggle.sh"

echo "════════════════════════════════════════════"
echo "  PARENT WIDGET SETUP"
echo "════════════════════════════════════════════"
echo ""

# ── 1. Create shortcuts directory (required by Termux:Widget) ────────────────
mkdir -p "$SHORTCUTS_DIR" 2>/dev/null
chmod 700 "$SHORTCUTS_DIR"
echo "[✓] Shortcuts directory ready: $SHORTCUTS_DIR"

# ── 2. Copy toggle script into shortcuts ─────────────────────────────────────
if [ -f "$HOME/parent_toggle_widget.sh" ]; then
    cp "$HOME/parent_toggle_widget.sh" "$WIDGET_SCRIPT"
    chmod 755 "$WIDGET_SCRIPT"
    echo "[✓] Widget script installed: $WIDGET_SCRIPT"
else
    echo "[!] parent_toggle_widget.sh not found in home. Trying /sdcard/Kiosk/..."
    if [ -f "/sdcard/Kiosk/parent_toggle_widget.sh" ]; then
        cp "/sdcard/Kiosk/parent_toggle_widget.sh" "$WIDGET_SCRIPT"
        chmod 755 "$WIDGET_SCRIPT"
        echo "[✓] Widget script installed from /sdcard/Kiosk/"
    else
        echo "[✗] ERROR: parent_toggle_widget.sh not found! Run deploy first."
        exit 1
    fi
fi

# ── 3. Set / prompt for PIN ───────────────────────────────────────────────────
PIN_FILE="$HOME/.kiosk_pin"
if [ -f "$PIN_FILE" ]; then
    echo "[i] PIN already set. To change it, run: echo 'NEWPIN' > ~/.kiosk_pin"
else
    echo ""
    echo -n "[?] Set your private Parent PIN (digits only): "
    read USER_PIN
    if [ -z "$USER_PIN" ]; then
        echo "[✗] PIN cannot be empty"
        exit 1
    fi
    echo "$USER_PIN" > "$PIN_FILE"
    chmod 600 "$PIN_FILE"
    echo "[✓] PIN saved"
fi

# ── 4. Install Termux:API if missing (needed for graphical PIN dialog) ────────
if ! command -v termux-dialog >/dev/null 2>&1; then
    echo ""
    echo "[i] termux-dialog not found — installing Termux:API..."
    pkg install -y termux-api >/dev/null 2>&1 && \
        echo "[✓] Termux:API installed (enables graphical PIN popup)" || \
        echo "[!] Could not install Termux:API — PIN prompt will use terminal mode"
else
    echo "[✓] Termux:API already installed"
fi

# ── 5. Check Termux:Widget APK ────────────────────────────────────────────────
WIDGET_APK_INSTALLED=$(pm list packages 2>/dev/null | grep "com.termux.widget" || echo "")
if [ -n "$WIDGET_APK_INSTALLED" ]; then
    echo "[✓] Termux:Widget app installed"
else
    echo ""
    echo "════════════════════════════════════════════"
    echo "  [!] ACTION REQUIRED: Install Termux:Widget"
    echo "════════════════════════════════════════════"
    echo "  Termux:Widget is NOT installed."
    echo "  Download from F-Droid:"
    echo "  https://f-droid.org/en/packages/com.termux.widget/"
    echo ""
    echo "  OR install via ADB from PC:"
    echo "  adb install termux-widget.apk"
    echo ""
fi

# ── 6. Print final instructions ───────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════"
echo "  SETUP COMPLETE!"
echo "════════════════════════════════════════════"
echo ""
echo "  To add the toggle button to your home screen:"
echo "  1. Long-press the home screen"
echo "  2. Tap 'Widgets'"
echo "  3. Find 'Termux:Widget' → drag it to home screen"
echo "  4. Select '🔒 Parent Toggle' from the list"
echo ""
echo "  That's it! One tap = PIN popup = mode switch."
echo ""
echo "  To change PIN: echo 'YOURPIN' > ~/.kiosk_pin"
echo ""
