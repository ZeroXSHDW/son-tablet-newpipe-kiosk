#!/data/data/com.termux/files/usr/bin/bash
# Full restart + verify (run as: run-as com.termux bash this)
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:$PATH
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr

kill_name() {
  local n="$1"
  local id
  for id in $(pgrep -f "$n" 2>/dev/null); do
    [ "$id" = "$$" ] && continue
    kill -9 "$id" 2>/dev/null && echo "killed $n $id"
  done
}

echo "=== STOP OLD ==="
kill_name "volume_guard.sh"
kill_name "kiosk_watchdog_v2.sh"
kill_name "fullscreen_enforcer.sh"
kill_name "newpipe_24x7.sh"
kill_name "service_monitor.sh"
kill_name "wifi_keepalive.sh"
kill_name "boot_orchestrator_v2_integrated.sh"
kill_name "update_newpipe.sh"
rm -f "$HOME"/*.pid 2>/dev/null
sleep 2

echo "=== START ORCHESTRATOR ==="
nohup bash "$HOME/boot_orchestrator_v2_integrated.sh" >> "$HOME/boot_orchestrator.log" 2>&1 &
echo "orch=$!"
sleep 10

echo "=== RUNNING ==="
pgrep -af "volume_guard.sh" || echo "DOWN volume_guard"
pgrep -af "fullscreen_enforcer.sh" || echo "DOWN fullscreen"
pgrep -af "newpipe_24x7.sh" || echo "DOWN newpipe_24x7"
pgrep -af "kiosk_watchdog_v2.sh" || echo "DOWN watchdog"
pgrep -af "service_monitor.sh" || echo "DOWN service_monitor"
pgrep -af "wifi_keepalive.sh" || echo "DOWN wifi_keepalive"

echo "=== LOGS ==="
tail -12 "$HOME/boot_orchestrator.log"
tail -8 "$HOME/newpipe_24x7.log" 2>/dev/null || true
