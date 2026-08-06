#!/data/data/com.termux/files/usr/bin/bash
# Parent toggle for Termux:Widget — PIN protected
PARENT_FILE=/sdcard/Kiosk/parent_mode.txt
PIN_FILE=/data/data/com.termux/files/home/.kiosk_pin
CORRECT_PIN=1234
HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:$PATH

[ -f "$PIN_FILE" ] && CORRECT_PIN=$(cat "$PIN_FILE" 2>/dev/null | tr -d '[:space:]')

if command -v termux-dialog >/dev/null 2>&1; then
  OUT=$(termux-dialog text -t "Parent PIN" -i "Enter PIN")
  PIN=$(echo "$OUT" | grep -o '"text":"[^"]*"' | sed 's/"text":"//;s/"//')
else
  read -s -p "PIN: " PIN; echo
fi

[ "$PIN" != "$CORRECT_PIN" ] && termux-toast -s "Wrong PIN" 2>/dev/null && exit 1

mkdir -p /sdcard/Kiosk 2>/dev/null || true

if [ -f "$PARENT_FILE" ] && [ "$(cat $PARENT_FILE 2>/dev/null | tr -d '\r')" = "true" ]; then
  # → Child / kiosk mode
  rm -f "$PARENT_FILE"
  settings put secure status_bar_hidden 1 2>/dev/null || true
  settings put secure home_key_disabled 1 2>/dev/null || true
  settings put secure back_key_disabled 1 2>/dev/null || true
  settings put global policy_control immersive.full=org.schabi.newpipe 2>/dev/null || true

  # Ensure 24/7 stack
  pgrep -f newpipe_24x7.sh >/dev/null || nohup bash "$HOME/newpipe_24x7.sh" >> "$HOME/newpipe_24x7.log" 2>&1 &
  pgrep -f fullscreen_enforcer.sh >/dev/null || nohup bash "$HOME/fullscreen_enforcer.sh" >> "$HOME/fullscreen_enforcer.log" 2>&1 &
  pgrep -f volume_guard.sh >/dev/null || nohup bash "$HOME/volume_guard.sh" >> "$HOME/volume_guard.log" 2>&1 &

  . "$HOME/playlist_lib.sh" 2>/dev/null || true
  if type play_next_coordinated >/dev/null 2>&1; then
    play_next_coordinated "child_mode" 1
  else
    am start -n org.schabi.newpipe/.RouterActivity -a android.intent.action.VIEW \
      -d "https://www.youtube.com/watch?v=2dDpryw3z5w" -e fullscreen true 2>/dev/null || true
  fi
  termux-toast -s "Child mode: NewPipe 24/7 ON" 2>/dev/null || true
else
  # → Parent mode
  echo "true" > "$PARENT_FILE"
  settings put secure status_bar_hidden 0 2>/dev/null || true
  settings put secure home_key_disabled 0 2>/dev/null || true
  settings put secure back_key_disabled 0 2>/dev/null || true
  settings put global policy_control null 2>/dev/null || true
  termux-toast -s "PARENT MODE — full access" 2>/dev/null || true
fi
