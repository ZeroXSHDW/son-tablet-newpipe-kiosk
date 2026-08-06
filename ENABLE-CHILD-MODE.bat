@echo off
cd /d "%~dp0"
set ADB=platform-tools\adb.exe
echo ====================================================
echo   CHILD MODE — NEWPIPE 24/7 FULLSCREEN PLAYLIST
echo ====================================================
%ADB% shell "rm -f /sdcard/Kiosk/parent_mode.txt; settings put global policy_control immersive.full=org.schabi.newpipe; settings put secure status_bar_hidden 1; settings put secure home_key_disabled 1; settings put secure back_key_disabled 1"
%ADB% shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash /data/data/com.termux/files/home/restart_kiosk_stack.sh"
%ADB% shell "export HOME=/data/data/com.termux/files/home; . $HOME/playlist_lib.sh 2>/dev/null; URL=$(grep -oE 'https://www.youtube.com/watch\?v=[a-zA-Z0-9_-]{11}' /sdcard/Kiosk/online_playlist.json 2>/dev/null | head -1); [ -z \"$URL\" ] && URL=https://www.youtube.com/watch?v=2dDpryw3z5w; am force-stop org.schabi.newpipe; am start -a android.intent.action.VIEW -d \"$URL\" -n org.schabi.newpipe/.RouterActivity -e fullscreen true"
echo.
echo   NewPipe only — continuous playlist fullscreen.
echo   Volume: day 80%% / night 40%%
pause
