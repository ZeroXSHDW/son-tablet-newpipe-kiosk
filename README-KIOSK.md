# Son’s tablet — NewPipe 24/7 kiosk

## Goal

| Item | Behavior |
|------|----------|
| **Online app** | **NewPipe**, immersive fullscreen |
| **Offline app** | **VLC fallback** for permitted cached media only |
| **Content** | **Time-phased** subscription channels only |
| **Day** | Ms Rachel, Tractor Ted, Teletubbies, Teletubbies–WildBrain, edubuzzkids (Play All) |
| **Bedtime 20:30–22:30** | Edubuzzkids sleep channel autoplay |
| **Night 22:30–06:00** | Edubuzzkids sleep channel autoplay; Ms Rachel fallback |
| **Wallpaper** | Calm ASMR Live Wallpaper app with slow day/dusk/night animation |
| **Volume** | Day 12/15 (06:00–20:30) · Sleep 3/15 (20:30–06:00) |
| **ADB** | USB once → Wi‑Fi **5555** |
| **Boot** | Kiosk Booter → Termux `RUN_COMMAND` → one integrated stack |

See **`GOAL.md`** and **`SUBSCRIPTIONS-SETUP.md`**.
For the active control path and publish-safe artifact boundary, see
**`ACTIVE-STACK.md`** and **`BUILD-AND-ARTIFACTS.md`**.
Before a release, run `pwsh -NoProfile -File tests/validate-repository.ps1` and
review **`RELEASE-CHECKLIST.md`**.

## Deploy (when tablet is on ADB)

```powershell
# Best: waits for device then deploys + health check
.\WAIT-AND-DEPLOY.ps1

# Immediate deploy if already connected
.\DEPLOY-WIFI-ADB.ps1

# Later status
.\HEALTH-CHECK.ps1

# If USB and Wi-Fi ADB both appear, select the tablet explicitly
.\HEALTH-CHECK.ps1 -DeviceSerial <tablet-serial>
```

Or double-click **`CONNECT-WIFI-ADB.bat`**.

### First-time tablet steps

1. Developer options → **USB debugging** ON  
2. Plug **data** USB cable → **Allow** (always)  
3. Run `.\WAIT-AND-DEPLOY.ps1`  
4. Allow the Kiosk Booter accessibility service if Android asks for confirmation
5. NewPipe: import `newpipe_subscriptions.json`; set Main player and autoplay-next ON

## Architecture (current)

| Script | Role |
|--------|------|
| `newpipe_24x7.sh` | Daytime autoplay and sustained-idle playback recovery owner |
| `playlist_lib.sh` | Phase-aware pick, no-repeat history, play lock |
| `kiosk_watchdog_v2.sh` | Retired compatibility shim; exits on stable installs |
| `fullscreen_enforcer.sh` | Immersive + native NewPipe player fullscreen + block home/back |
| `volume_guard.sh` | Time-based volume/brightness |
| `service_monitor.sh` | Restart the six managed daemons every 45s |
| `wifi_keepalive.sh` | Active; keeps Wi-Fi enabled and records connectivity status; never owns playback |
| `download_scheduler.sh` | Active; strict NETZ-only, storage-guarded cached-media downloads |
| `update_newpipe.sh` | Disabled; updates are parent-reviewed to prevent UI drift |
| `boot_orchestrator_v2_integrated.sh` | Starts the six managed daemons and service monitor on boot |

Bedtime/night autoplay uses `SLEEP_CHANNEL_URL` (Edubuzzkids) and falls back to
`SLEEP_FALLBACK_URL` (Ms Rachel) in `termux_scripts/kiosk_config.sh`. Set
`SLEEP_AUTOPLAY=0` only when sleep audio is intentionally disabled. See
`ACTIVE-STACK.md` for the exact control path and retired scripts.

Playlist file: `termux_scripts/Kiosk/online_playlist.json` → `/sdcard/Kiosk/`.

## Parent / child

- PIN widget: Termux `ParentToggle.sh` (default PIN `1234`, change in `~/.kiosk_pin`)  
- PC: `ENABLE-CHILD-MODE.bat` / `ENABLE-PARENT-MODE.bat`  

## Notes

- Offline: `newpipe_24x7.sh` hands permitted cached media to VLC and returns to
  NewPipe when NETZ returns. `wifi_keepalive.sh` only maintains connectivity
  and status; it never starts or stops a player. This is the only intentional
  exception to the online NewPipe-only rule.
- One playback owner prevents competing relaunch loops.
- Healthy playback is not force-rotated; recovery happens only after the configured idle/grace windows.
