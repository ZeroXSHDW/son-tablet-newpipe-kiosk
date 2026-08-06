#!/data/data/com.termux/files/usr/bin/bash
# Clean restart using pgrep (Termux-visible processes only)
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:$PATH

LOG=$HOME/hard_fix.log
exec >>"$LOG" 2>&1
echo "======== HARD FIX $(date) ========"

kill_by_name() {
  local n="$1" id
  for id in $(pgrep -f "$n" 2>/dev/null); do
    [ "$id" = "$$" ] && continue
    kill -9 "$id" 2>/dev/null && echo "killed $n $id"
  done
}

kill_by_name "volume_guard.sh"
kill_by_name "kiosk_watchdog_v2.sh"
kill_by_name "fullscreen_enforcer.sh"
kill_by_name "newpipe_24x7.sh"
kill_by_name "service_monitor.sh"
kill_by_name "wallpaper_live.sh"
kill_by_name "wifi_keepalive.sh"
kill_by_name "boot_orchestrator_v2_integrated.sh"
kill_by_name "update_newpipe.sh"
sleep 2

rm -f "$HOME"/*.pid
rm -rf "$HOME/Kiosk/.play_lock" /sdcard/Kiosk/.play_lock 2>/dev/null || true
mkdir -p "$HOME/Kiosk/wallpapers"

if [ -d /data/local/tmp/kiosk_walls ]; then
  cp -f /data/local/tmp/kiosk_walls/* "$HOME/Kiosk/wallpapers/" 2>/dev/null || true
fi
cp -f /sdcard/Kiosk/*.json "$HOME/Kiosk/" 2>/dev/null || true

# Phase stamp
hm=$(date +%H%M | sed 's/^0*//'); [ -z "$hm" ] && hm=0
if [ "$hm" -ge 600 ] && [ "$hm" -lt 900 ]; then p=MORNING
elif [ "$hm" -ge 900 ] && [ "$hm" -lt 1800 ]; then p=LEARNING
elif [ "$hm" -ge 1800 ] && [ "$hm" -lt 2030 ]; then p=RELAXING
elif [ "$hm" -ge 2030 ] && [ "$hm" -lt 2230 ]; then p=BEDTIME
else p=NIGHT
fi
echo "$p" > "$HOME/Kiosk/phase.txt"
echo "phase=$p"

nohup bash "$HOME/boot_orchestrator_v2_integrated.sh" >> "$HOME/boot_orchestrator.log" 2>&1 &
echo orch=$!
sleep 16

echo "=== PROCESSES ==="
for n in volume_guard fullscreen_enforcer newpipe_24x7 kiosk_watchdog_v2 service_monitor wallpaper_live wifi_keepalive; do
  if pgrep -f "${n}.sh" >/dev/null 2>&1; then
    echo "UP $n pids=$(pgrep -f ${n}.sh | tr '\n' ' ')"
  else
    echo "DOWN $n"
  fi
done

echo "=== 24x7 ==="
tail -25 "$HOME/newpipe_24x7.log"
echo "DONE $(date)"
