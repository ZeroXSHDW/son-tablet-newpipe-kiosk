# Android NewPipe tablet kiosk

This repository contains the source, configuration, deployment scripts, and
validation checks for a supervised Android tablet kiosk using NewPipe,
Termux, Kiosk Booter, and the optional calm live-wallpaper support app.

The project keeps the tablet in a controlled NewPipe playback path, restricts
daytime selection to configured subscriptions, applies time-based volume and
brightness settings, and recovers playback when the active session stops.

## Features

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
- `GET-DEVICE-SERIAL.ps1` — shows the tablet's ADB serial and prints ready-to-
  paste deployment commands.
- `GET-DEVICE-SERIAL.bat` — double-clickable Windows shortcut for the same
  serial lookup.
- `HEALTH-CHECK.ps1` — live device health checks after deployment or reboot.
- `tests/` and `.github/workflows/` — local and GitHub Actions repository
  validation.
- `GETTING-STARTED.md` — beginner-friendly explanation, first deployment, and
  troubleshooting.
- `README-KIOSK.md`, `ACTIVE-STACK.md`, `GOAL.md`, and
  `BUILD-AND-ARTIFACTS.md` — operating model, active control path, goals, and
  source/artifact boundary.


## Prerequisites

The host workstation needs PowerShell 5.1+ (PowerShell 7 is recommended),
Git, Python 3.11, Bash (Git for Windows is sufficient), and Android platform
tools. The target must be an authorized Android tablet with the required
NewPipe, Termux, Kiosk Booter, and optional support-app setup. ADB pairing,
accessibility permissions, storage, and the actual playback state are device
checks; the source validator cannot prove them.

## Quick start for an existing setup

1. Install PowerShell 5.1+, Git, Python 3.11, Bash (Git for Windows is
   sufficient), and Android platform tools on the host. The repository's CI
   runtime is pinned in [`.python-version`](.python-version).
2. Restore or build the ignored deployment artifacts described in
   `BUILD-AND-ARTIFACTS.md`, then run the read-only preflight:

   ```powershell
   .\CHECK-PREREQUISITES.ps1 -RequireArtifacts
   ```

3. Pair the target tablet over USB once, enable Wi-Fi ADB, and run:

   ```powershell
   .\WAIT-AND-DEPLOY.ps1
   ```

4. If a command asks for `<tablet-serial>`, find it with:

   ```powershell
   .\GET-DEVICE-SERIAL.ps1 -Wait -Copy
   ```

   On Windows, you can also double-click `GET-DEVICE-SERIAL.bat`.

   With exactly one authorized device connected, this displays the serial,
   copies it to the clipboard, and prints the exact deployment and health-check
   commands.

5. Run the health check with the target serial supplied locally:

   ```powershell
   .\HEALTH-CHECK.ps1 -DeviceSerial <tablet-serial>
   ```

6. Before committing source changes, run the repository gate:

   ```powershell
   git diff --check
   pwsh -NoProfile -File .\tests\validate-repository.ps1
   ```

Read [`README-KIOSK.md`](README-KIOSK.md) and
[`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md) before using the deployment
scripts. The target device, package versions, accessibility permissions, and
live playback state must be verified on the actual tablet; a passing source
validation run is not a substitute for that device check.


## Troubleshooting

Use the read-only checks first and keep the tablet's recovery path available.

- If prerequisites or ignored deployment artifacts are missing, run
  `CHECK-PREREQUISITES.ps1` with the same artifact requirement used by the
  deployment plan; rebuild or restore artifacts deliberately instead of
  committing them.
- If ADB cannot find the tablet, pair it over USB or Wi-Fi again and run
  `GET-DEVICE-SERIAL.ps1 -Wait -Copy`. Pass the printed serial explicitly;
  never guess a device target.
- If deployment completes but playback or kiosk behavior is wrong, run
  `HEALTH-CHECK.ps1 -DeviceSerial <tablet-serial>`, review the active stack and
  phase configuration, and verify the actual tablet manually before redeploying.
- If the source gate fails, run
  `pwsh -NoProfile -File .\tests\validate-repository.ps1`,
  `git diff --check`, and the relevant shell/Python checks from the repository
  root. A passing source check does not replace live-device validation.
- If a device is left in an unsafe or unexpected state, stop automation,
  restore the approved kiosk path manually, and use the documented recovery
  procedure in [GETTING-STARTED.md](GETTING-STARTED.md#common-issues). Do not
  upload device logs, cookies, serials, or screenshots to the public repository.

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

## Contributing

Keep device identifiers, cookies, logs, APKs, and platform tools outside the repository. Run the documented validators before review and see [CONTRIBUTING.md](CONTRIBUTING.md).

## Architecture

The repository separates host-side deployment scripts, Termux-side kiosk
configuration, and documentation. Device state, credentials, cookies, logs,
and compiled artifacts remain runtime-only inputs.

## Security

See [SECURITY.md](SECURITY.md) for private vulnerability reporting. Review the
target device, repository owner, and Termux `run-as` boundary before any push
or deployment.

## License

MIT — see [LICENSE](LICENSE).
