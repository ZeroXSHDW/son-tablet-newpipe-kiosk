# Build and publish boundary

The repository publishes the readable source, deployment scripts, configuration,
playlist/channel definitions, and the Android source for the support apps. It
does not publish device-local state, cookies, runtime logs, captured UI files,
platform-tools, APKs, or compiled JARs. Those outputs are intentionally ignored
by `.gitignore` because they are machine-specific, potentially sensitive, or
reproducible build artifacts.

## Fresh checkout requirements

`DEPLOY-WIFI-ADB.ps1` expects these local deployment inputs:

- `platform-tools\adb.exe`
- `termux_scripts\kioskhelper.jar`
- `termux_scripts\LiveWallpaperSetter.jar`
- the built support APKs under `termux_scripts\kioskbooter\` and
  `termux_scripts\calmwallpaper\`

The support-app source and build scripts are retained in the repository,
including the Kiosk Booter accessibility resources under
`termux_scripts\kioskbooter\res\`. A fresh checkout must either restore the
ignored APK/JAR artifacts from a trusted local build cache or rebuild them
before deployment. Never add cookies, private ADB state, or tablet runtime
logs to the repository.

## Repository validation

Run the host-side release gate before committing source changes:

```powershell
pwsh -NoProfile -File .\tests\validate-repository.ps1
```

The same gate runs in GitHub Actions. It checks PowerShell, shell, Python, and
JSON syntax, configuration-to-schedule consistency, subscriptions-only policy,
download network restrictions, and release-sensitive tracked artifacts. It
does not replace the target-tablet build and cold-boot health gates.

## Configuration change path

Edit only `termux_scripts\kiosk_config.sh`, then run
`DEPLOY-WIFI-ADB.ps1` and verify with `HEALTH-CHECK.ps1`. The deployed device
copy is replaced from this source on every deployment.
