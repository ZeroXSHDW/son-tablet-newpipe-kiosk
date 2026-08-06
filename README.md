# Android NewPipe tablet kiosk

This repository contains the source, configuration, deployment scripts, and
validation checks for a supervised Android tablet kiosk using NewPipe,
Termux, Kiosk Booter, and the optional calm live-wallpaper support app.

The project keeps the tablet in a controlled NewPipe playback path, restricts
daytime selection to configured subscriptions, applies time-based volume and
brightness settings, and recovers playback when the active session stops.

## See it at a glance

| Capability | Behavior |
| --- | --- |
| Supervised playback | NewPipe fullscreen with recovery after sustained inactivity |
| Content policy | Five configured subscription channels only during the day |
| Time phases | Morning, learning, relaxing, bedtime, and night settings |
| Offline fallback | Permitted cached media can be handed to VLC |
| Parent controls | Private-PIN parent mode and child kiosk mode |
| Operations | Boot, Wi-Fi, download, service, and health monitoring |

This is a deployment toolkit for an Android tablet, not a standalone app. It
uses ADB and Termux to configure and supervise NewPipe and the small support
apps included in the repository.

For the beginner-friendly setup path, see
[`GETTING-STARTED.md`](GETTING-STARTED.md).

## Repository contents

- `termux_scripts/` — Termux runtime scripts, channel/configuration data, and
  source for the small Android support apps.
- `DEPLOY-WIFI-ADB.ps1` and related PowerShell/ batch files — host-side
  connection, deployment, and mode-control helpers.
- `CHECK-PREREQUISITES.ps1` — read-only preflight that explains what is
  missing before deployment.
- `HEALTH-CHECK.ps1` — live device health checks after deployment or reboot.
- `tests/` and `.github/workflows/` — local and GitHub Actions repository
  validation.
- `GETTING-STARTED.md` — beginner-friendly explanation, first deployment, and
  troubleshooting.
- `README-KIOSK.md`, `ACTIVE-STACK.md`, `GOAL.md`, and
  `BUILD-AND-ARTIFACTS.md` — operating model, active control path, goals, and
  source/artifact boundary.

## Quick start for an existing setup

1. Install PowerShell 5.1+, Git, Python 3, Bash (Git for Windows is
   sufficient), and Android platform tools on the host.
2. Restore or build the ignored deployment artifacts described in
   `BUILD-AND-ARTIFACTS.md`, then run the read-only preflight:

   ```powershell
   .\CHECK-PREREQUISITES.ps1 -RequireArtifacts
   ```

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

Read [`README-KIOSK.md`](README-KIOSK.md) and
[`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md) before using the deployment
scripts. The target device, package versions, accessibility permissions, and
live playback state must be verified on the actual tablet; a passing source
validation run is not a substitute for that device check.

## Public-repository boundary

This checkout intentionally contains source and documentation only. It does
not include device-local ADB state, cookies, runtime logs, UI captures,
platform tools, APKs, compiled JARs, or other generated artifacts. Those files
are ignored by `.gitignore` and should remain outside a public repository.

The exact target device serial is deliberately not stored in the repository;
provide it at runtime with `-DeviceSerial`.

This project is distributed under the MIT License. See [LICENSE](LICENSE).

## Important safety notes

- Review `termux_scripts/kiosk_config.sh` before deployment; it is the
  authoritative configuration for phases, channels, volume, brightness, and
  sleep autoplay.
- The deployment flow uses the Termux app's `run-as` boundary. Do not replace
  it with an unrestricted copy into Termux's private data directory.
- Review the target repository visibility and owner before the first push.
