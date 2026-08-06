# Security policy

## Scope

This repository contains deployment scripts for a supervised Android tablet.
It is not a security boundary by itself: anyone with physical access, Android
debugging access, or the configured parent PIN may be able to change the
device.

## Reporting a concern

Please do not publish credentials, cookies, device serials, private ADB state,
runtime logs, or other sensitive device data in an issue. Report suspected
security problems privately through the repository owner's GitHub contact
options, including a minimal reproduction and the affected file or component.

The repository intentionally excludes device-local state and generated
artifacts. Review `.gitignore` before adding deployment output or diagnostics.
