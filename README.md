# Son's tablet kiosk

This repository contains the source, configuration, deployment scripts, and
validation checks for a supervised Android tablet kiosk using NewPipe,
Termux, Kiosk Booter, and the optional calm live-wallpaper support app.

The project is intended to keep the tablet in a controlled NewPipe playback
path, restrict daytime selection to the configured subscriptions, apply
time-based volume and brightness settings, and recover playback when the
active session stops.

## Repository contents

- `termux_scripts/` — Termux runtime scripts, channel/configuration data, and
  source for the small Android support apps.
- `DEPLOY-WIFI-ADB.ps1` and related PowerShell/ batch files — host-side
  connection, deployment, and mode-control helpers.
- `HEALTH-CHECK.ps1` — live device health checks after deployment or reboot.
- `tests/` and `.github/workflows/` — local and GitHub Actions repository
  validation.
- `README-KIOSK.md`, `ACTIVE-STACK.md`, `GOAL.md`, and
  `BUILD-AND-ARTIFACTS.md` — operating model, active control path, goals, and
  source/artifact boundary.

## Quick start

1. Install PowerShell 7, Git, Python 3, Bash (Git for Windows is sufficient),
   and Android platform tools on the host.
2. Restore or build the ignored deployment artifacts described in
   `BUILD-AND-ARTIFACTS.md`: `adb.exe`, the helper JARs, and the support APKs.
3. Pair the target tablet over USB once, enable Wi-Fi ADB, and run:

   ```powershell
   .\WAIT-AND-DEPLOY.ps1
   ```

4. Run the health check with the target serial supplied locally:

   ```powershell
   .\HEALTH-CHECK.ps1 -DeviceSerial <tablet-serial>
   ```

5. Before committing source changes, run the repository gate:

   ```powershell
   pwsh -NoProfile -File .\tests\validate-repository.ps1
   ```

Read `README-KIOSK.md` and `RELEASE-CHECKLIST.md` before using the deployment
scripts. The target device, package versions, accessibility permissions, and
live playback state must be verified on the actual tablet; a passing source
validation run is not a substitute for that device check.

## Publish boundary

This checkout intentionally contains source and documentation only. It does
not include device-local ADB state, cookies, runtime logs, UI captures,
platform tools, APKs, compiled JARs, or other generated artifacts. Those files
are ignored by `.gitignore` and should remain outside a public repository.

The exact target device serial is deliberately not stored in the repository;
provide it at runtime with `-DeviceSerial`.

No distribution license has been selected in this package. Choose and add an
appropriate license before describing the repository as open source.

## Important safety notes

- Review `termux_scripts/kiosk_config.sh` before deployment; it is the
  authoritative configuration for phases, channels, volume, brightness, and
  sleep autoplay.
- The deployment flow uses the Termux app's `run-as` boundary. Do not replace
  it with an unrestricted copy into Termux's private data directory.
- Keep the target repository visibility, owner, and remote URL as an explicit
  user decision. This folder is prepared for upload, but it is not connected
  to GitHub and no remote push has been performed.
