#!/data/data/com.termux/files/usr/bin/bash
#
# NEWPIPE AUTO-UPDATER v1.0
# Automatically checks GitHub API for latest NewPipe releases when Wi-Fi is online
# Downloads and updates NewPipe silently in background
#

export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:$PATH

LOG_FILE="$HOME/newpipe_update.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

log "NewPipe Auto-Updater daemon started. Polling every 2 hours when online."

while true; do
    # Check internet / Wi-Fi connection
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log "Wi-Fi connected. Checking GitHub API for latest NewPipe release..."
        
        LATEST_JSON=$(curl -s --connect-timeout 10 https://api.github.com/repos/TeamNewPipe/NewPipe/releases/latest || true)
        
        if [ -n "$LATEST_JSON" ]; then
            DOWNLOAD_URL=$(echo "$LATEST_JSON" | grep -o -E 'https://github.com/TeamNewPipe/NewPipe/releases/download/[^"]+\.apk' | head -n 1 || true)
            LATEST_TAG=$(echo "$LATEST_JSON" | grep -o -E '"tag_name":\s*"[^"]+"' | head -n 1 | cut -d'"' -f4 || echo "unknown")
            
            CURRENT_VER=$(pm dump org.schabi.newpipe | grep "versionName=" | head -n 1 | cut -d'=' -f2 | tr -d '\r' || echo "")
            log "Current NewPipe: $CURRENT_VER | Latest GitHub: $LATEST_TAG"
            
            if [ -n "$DOWNLOAD_URL" ] && [ "$CURRENT_VER" != "$LATEST_TAG" ] && [ "v$CURRENT_VER" != "$LATEST_TAG" ]; then
                APK_PATH="/data/local/tmp/newpipe_latest.apk"
                log "New version found ($LATEST_TAG)! Downloading from $DOWNLOAD_URL..."
                curl -sL -o "$APK_PATH" "$DOWNLOAD_URL"
                
                if [ -f "$APK_PATH" ] && [ -s "$APK_PATH" ]; then
                    log "Download complete. Installing update..."
                    pm install -r "$APK_PATH" >> "$LOG_FILE" 2>&1 || true
                    log "NewPipe updated successfully to $LATEST_TAG."
                    rm -f "$APK_PATH"
                else
                    log "APK download failed or was empty."
                fi
            else
                log "NewPipe is up to date ($CURRENT_VER)."
            fi
        fi
    else
        log "No active Wi-Fi connection. Skipping update check."
    fi

    # Check for updates every 2 hours (7200 seconds)
    sleep 7200
done
