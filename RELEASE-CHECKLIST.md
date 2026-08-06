# GitHub release checklist

This repository contains the readable kiosk source and deployment controls. A
GitHub release is ready only when the following gates are satisfied:

- `pwsh -NoProfile -File tests/validate-repository.ps1` passes.
- The support APKs and helper JARs are rebuilt from this checkout on a trusted
  Termux/Android toolchain, then installed and verified on the target tablet.
- `HEALTH-CHECK.ps1 -DeviceSerial <serial>` passes on the target device after
  a cold reboot, with the exact device serial recorded outside Git.
- The intended GitHub repository, visibility, owner, and distribution license
  are explicitly chosen. This project currently has no `LICENSE` file, so it
  must not be published as an open-source project until that choice is made.
- The release commit contains source and documentation only; device captures,
  ADB state, cookies, logs, APKs, JARs, and platform-tools remain excluded.

The local repository currently has no configured Git remote. Adding or pushing
to a remote is intentionally a separate, user-authenticated release action.
