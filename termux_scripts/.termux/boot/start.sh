#!/data/data/com.termux/files/usr/bin/bash
# Kiosk Booter is the sole kiosk startup owner through Termux RUN_COMMAND.
# Termux:Boot may still be installed on the tablet, but this compatibility
# entrypoint must not launch a second orchestrator or duplicate daemon stack.
exit 0
