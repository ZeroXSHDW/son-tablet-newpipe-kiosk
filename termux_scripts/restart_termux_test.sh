#!/data/data/com.termux/files/usr/bin/bash
# Clean restart of kiosk stack (called after Termux process restart)
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:$PATH

LOG=$HOME/restart_test.log
exec >>"$LOG" 2>&1
echo "=== RESTART TEST $(date) ==="

# Kill prior stack
for n in volume_guard kiosk_watchdog_v2 fullscreen_enforcer newpipe_24x7 service_monitor wifi_keepalive wallpaper_live boot_orchestrator_v2_integrated update_newpipe; do
  for id in $(pgrep -f "${n}.sh" 2>/dev/null); do
    [ "$id" = "$$" ] && continue
    kill -9 "$id" 2>/dev/null && echo "killed $n $id"
  done
done
rm -f "$HOME"/*.pid 2>/dev/null
sleep 2

# Ensure configs
mkdir -p "$HOME/Kiosk" /sdcard/Kiosk /sdcard/Download 2>/dev/null || true
for f in channels.json newpipe_subscriptions.json online_playlist.json; do
  [ -f "/sdcard/Kiosk/$f" ] && cp -f "/sdcard/Kiosk/$f" "$HOME/Kiosk/" 2>/dev/null || true
  [ -f "$HOME/Kiosk/$f" ] && cp -f "$HOME/Kiosk/$f" /sdcard/Download/ 2>/dev/null || true
done
[ -f /sdcard/Kiosk/newpipe_subscriptions.json ] && \
  cp -f /sdcard/Kiosk/newpipe_subscriptions.json /sdcard/Download/newpipe_subscriptions.json 2>/dev/null || true

# Boot stack
nohup bash "$HOME/boot_orchestrator_v2_integrated.sh" >> "$HOME/boot_orchestrator.log" 2>&1 &
echo "orch=$!"
sleep 12

echo "=== PROCESSES ==="
for n in volume_guard fullscreen_enforcer newpipe_24x7 kiosk_watchdog_v2 service_monitor wifi_keepalive wallpaper_live; do
  if pgrep -f "${n}.sh" >/dev/null; then echo "UP $n"; else echo "DOWN $n"; fi
done
echo "phase=$(cat /sdcard/Kiosk/phase.txt 2>/dev/null || cat $HOME/Kiosk/phase.txt 2>/dev/null)"
echo "=== BOOT LOG ==="
tail -20 "$HOME/boot_orchestrator.log"
echo "=== 24x7 LOG ==="
tail -15 "$HOME/newpipe_24x7.log" 2>/dev/null || true
echo "DONE"
