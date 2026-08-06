# GitHub release checklist

This repository contains the readable kiosk source and deployment controls. A
GitHub release is ready only when the following gates are satisfied:

- `pwsh -NoProfile -File tests/validate-repository.ps1` passes.
- The support APKs and helper JARs are rebuilt from this checkout on a trusted
  Termux/Android toolchain, then installed and verified on the target tablet.
- `HEALTH-CHECK.ps1 -DeviceSerial <serial>` passes on the target device after
  a cold reboot, with the exact device serial recorded outside Git.
- The intended GitHub repository, visibility, owner, and distribution license
  are explicitly chosen. The repository includes an MIT `LICENSE` file.
- The release commit contains source and documentation only; device captures,
  ADB state, cookies, logs, APKs, JARs, and platform-tools remain excluded.

Confirm the GitHub remote points to the intended repository before pushing.
