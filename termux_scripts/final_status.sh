#!/data/data/com.termux/files/usr/bin/bash
export PATH=/data/data/com.termux/files/usr/bin:/system/bin:$PATH
HOME=/data/data/com.termux/files/home
# kill stubborn old PIDs if still present
for id in 2704 2709 2713; do kill -9 "$id" 2>/dev/null; done
# ensure helpers
nohup bash "$HOME/volume_guard.sh" >>"$HOME/volume_guard.log" 2>&1 &
nohup bash "$HOME/fullscreen_enforcer.sh" >>"$HOME/fullscreen_enforcer.log" 2>&1 &
sleep 2
echo "=== PROCESSES ==="
ps -A -o PID,ARGS 2>/dev/null | grep 'files/home' | grep '\.sh' | grep -v grep || true
echo "=== 24x7 LOG ==="
tail -8 "$HOME/newpipe_24x7.log" 2>/dev/null || true
echo "=== BOOT LOG ==="
tail -6 "$HOME/boot_orchestrator.log" 2>/dev/null || true
