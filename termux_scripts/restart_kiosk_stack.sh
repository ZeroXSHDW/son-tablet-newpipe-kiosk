#!/data/data/com.termux/files/usr/bin/bash
# Restart NewPipe 24/7 stack (run via: run-as com.termux bash thisfile)
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:$PATH
HOME=/data/data/com.termux/files/home
PREFIX=/data/data/com.termux/files/usr

kill_matching() {
  local needle="$1"
  # Exact prefix match avoids killing the controller while it is still scanning.
  # This script may run while many historical variants exist; match by fully
  # qualified path and command name.
  local pids
  pids=$(
    ps -ef 2>/dev/null | /data/data/com.termux/files/usr/bin/grep -F "/data/data/com.termux/files/home/$needle" | \
      /data/data/com.termux/files/usr/bin/grep -v 'grep' | \
      /system/bin/awk '{print $2}'
  ) || true
  if [ -n "$pids" ]; then
    # Android toybox xargs does not consistently support GNU's -r flag on
    # this tablet; use a bounded shell loop so cleanup actually happens.
    for pid in $pids; do
      [ -n "$pid" ] || continue
      [ "$pid" = "$$" ] && continue
      kill -9 "$pid" 2>/dev/null || true
    done
  fi
}

# Stop supervisors first so they cannot recreate children during cleanup.
kill_matching "service_monitor.sh"
kill_matching "boot_orchestrator_v2_integrated.sh"
sleep 1

kill_matching "kiosk_watchdog_v2.sh"
kill_matching "newpipe_24x7.sh"
kill_matching "fullscreen_enforcer.sh"
kill_matching "wallpaper_live.sh"
kill_matching "volume_guard.sh"
kill_matching "wifi_keepalive.sh"
kill_matching "download_scheduler.sh"
kill_matching "update_newpipe.sh"

# A second pass closes the narrow race where an old supervisor recreated a
# child just before the supervisor itself was terminated.
sleep 1
kill_matching "service_monitor.sh"
kill_matching "boot_orchestrator_v2_integrated.sh"
kill_matching "kiosk_watchdog_v2.sh"
kill_matching "newpipe_24x7.sh"
kill_matching "fullscreen_enforcer.sh"
kill_matching "wallpaper_live.sh"
kill_matching "volume_guard.sh"
kill_matching "wifi_keepalive.sh"
kill_matching "download_scheduler.sh"
kill_matching "update_newpipe.sh"

rm -f "$HOME"/*.pid 2>/dev/null
sleep 1

echo "remaining:"
ps -ef 2>/dev/null | grep -E "/data/data/com.termux/files/home/(volume_guard|fullscreen_enforcer|wallpaper_live|newpipe_24x7|service_monitor|wifi_keepalive|download_scheduler)\.sh" | grep -v grep || echo none

# Re-enter through the single authorized boot owner. Do not launch the
# orchestrator directly here or this utility can create a second RUN_COMMAND
# session beside Kiosk Booter.
am broadcast --user 0 -a com.android.kioskbooter.RESTART_STACK \
  -n com.android.kioskbooter/.BootReceiver >/dev/null 2>&1 || true
echo "RESTART_STACK requested through Kiosk Booter"
sleep 14

echo "running:"
ps -ef 2>/dev/null | grep -E "/data/data/com.termux/files/home/(volume_guard|fullscreen_enforcer|wallpaper_live|newpipe_24x7|service_monitor|wifi_keepalive|download_scheduler)\.sh" | grep -v grep || echo none
echo "--- boot log ---"
tail -15 "$HOME/boot_orchestrator.log"
echo "--- 24x7 log ---"
tail -10 "$HOME/newpipe_24x7.log" 2>/dev/null || true
