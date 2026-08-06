# Active tablet stack

This file is the control-plane map for the P7 tablet. It describes what the
deployment currently installs and starts; files that are present in the folder
but not in this path are not automatically active.

## Startup path

```text
Android boot / manual WAKEUP
  -> com.android.kioskbooter/.BootReceiver
  -> Termux RUN_COMMAND
  -> boot_orchestrator_v2_integrated.sh
  -> volume_guard.sh
  -> fullscreen_enforcer.sh
  -> wallpaper_live.sh
  -> newpipe_24x7.sh
  -> wifi_keepalive.sh (network/status only)
  -> download_scheduler.sh (NETZ-gated, playback-independent)
  -> service_monitor.sh
```

Kiosk Booter is the intended single startup owner. The deployed
`.termux/boot/start.sh` is a compatibility no-op so Termux:Boot does not create
a second stack. `start.sh` is a fallback entrypoint only; the Kiosk Booter
`RUN_COMMAND` path is the path exercised by the deployment script.

## What each active component does

- `kiosk_config.sh` is authoritative for phase times, volume, brightness,
  subscription-only playback, recovery intervals, and sleep autoplay.
- `volume_guard.sh` applies music volume and attempts phase brightness every two
  seconds while child mode is locked. On this P7, the music volume readback is
  verified; unattended brightness writeback remains device/runtime dependent.
- `fullscreen_enforcer.sh` maintains NewPipe immersive mode and the child-mode
  navigation boundary. It also requests the Kiosk Booter accessibility service's
  native NewPipe player transition, which expands mini-player/detail-pane video
  to the tablet's full width and keeps the P7 in verified landscape rotation 0.
- `wallpaper_live.sh` selects the day/dusk/night artwork and the installed
  `com.android.calmwallpaper` service is the live wallpaper when its marker is
  present.
- `newpipe_24x7.sh` is the sole playback recovery owner. It rotates the five
  allowed subscription channels during the day. During BEDTIME/NIGHT it
  autoplays `SLEEP_CHANNEL_URL` and falls back to `SLEEP_FALLBACK_URL`.
- `service_monitor.sh` checks and restarts the six managed daemons above; it does
  not start the legacy watchdog or old monitors. The complete active runtime is
  seven long-running processes: those six daemons plus this service monitor.
- `download_scheduler.sh` is a separate non-playback service: it only runs the
  storage-guarded downloader during the 02:00 window or on an explicit
  `download_now.txt` request.
- `wifi_keepalive.sh` is network/status-only: it keeps saved Wi-Fi enabled and
  records the shared connectivity-loss window. `newpipe_24x7.sh` is the sole
  playback and offline handoff owner; it may keep a healthy NewPipe session or
  hand off to VLC after the configured grace period when permitted media exists.

## Present but not active in the normal path

The older `boot_orchestrator.sh`, `boot_orchestrator_v2.sh`, `activate.sh`,
`autoboot_setup.sh`, `kiosk_watchdog_v2.sh`, and the
historical dashboard/analytics scripts are kept for reference or recovery.
They are not launched by
`boot_orchestrator_v2_integrated.sh`.

## Configuration changes

Edit only `termux_scripts/kiosk_config.sh`, then run
`DEPLOY-WIFI-ADB.ps1` and verify with `HEALTH-CHECK.ps1`. The key values are:

| Setting | Current value | Effect |
|---|---:|---|
| `SUBSCRIPTIONS_ONLY` | `1` | Restricts daytime selection to the five imported channels |
| `BEDTIME_START` | `2030` | Starts sleep playback at 20:30 |
| `NIGHT_START` | `2230` | Switches to night volume/brightness at 22:30 |
| `DAY_VOLUME` | `12` | Music stream 12/15, about 80% |
| `BEDTIME_VOLUME` | `3` | Sleep music stream 3/15 |
| `NIGHT_VOLUME` | `3` | Sleep music stream 3/15 |
| `MORNING_BRIGHTNESS` | `160` | Child overlay display target 160/255 |
| `LEARNING_BRIGHTNESS` | `180` | Child overlay display target 180/255 |
| `RELAXING_BRIGHTNESS` | `120` | Child overlay display target 120/255 |
| `BEDTIME_BRIGHTNESS` | `40` | Child overlay display target 40/255 |
| `NIGHT_BRIGHTNESS` | `25` | Child overlay display target 25/255 |
| `SLEEP_AUTOPLAY` | `1` | Autoplay sleep channel during bedtime/night |
| `SLEEP_CHANNEL_URL` | Edubuzzkids videos | Primary sleep channel |
| `SLEEP_FALLBACK_URL` | Ms Rachel bedtime video | Fallback if the channel feed fails |

Do not edit the generated device copy directly; deployment replaces it from
the repository copy.

## Verification boundary

The verification target is the P7 model/Android version, all seven active
processes, NewPipe/VLC package behavior, music volume, live wallpaper
component, immersive policy, accessibility lock, offline VLC handoff, and
online NewPipe return. A cold reboot must converge through Kiosk Booter only;
`.termux/boot/start.sh` is intentionally a no-op compatibility file.
`screen_brightness` alone is not a reliable proof on this firmware. In
child mode, `volume_guard.sh` sends the phase target to the Kiosk Booter
accessibility overlay; verify the effective value with `dumpsys display` and
the phase target reported by `HEALTH-CHECK.ps1`.
