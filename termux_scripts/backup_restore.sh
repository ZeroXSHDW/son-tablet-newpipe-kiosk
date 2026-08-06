#!/system/bin/sh
# Configuration Backup & Restore
# Auto-backup of critical configs, with restore capability

set -u

HOME_DIR="/data/data/com.termux/files/home"
KIOSK_DIR="/sdcard/Kiosk"
BACKUP_DIR="$KIOSK_DIR/backups"
BACKUP_RETENTION_DAYS=7

# Directories and files to backup
BACKUP_SOURCES=(
    "$KIOSK_DIR/phase.txt"
    "$KIOSK_DIR/download_schedule.json"
    "$KIOSK_DIR/schedule_config.json"
    "$KIOSK_DIR/offline_videos"
    "$HOME_DIR/boot_orchestrator.log"
)

# Initialize backup directory
init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Backup directory: $BACKUP_DIR"
}

# Create backup
create_backup() {
    init_backup_dir
    
    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Creating backup: $backup_name"
    
    for source in "${BACKUP_SOURCES[@]}"; do
        if [ -e "$source" ]; then
            if [ -d "$source" ]; then
                # Backup directory
                cp -r "$source" "$backup_path/" 2>/dev/null || true
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]   ✓ Backed up directory: $(basename "$source")"
            else
                # Backup file
                cp "$source" "$backup_path/" 2>/dev/null || true
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]   ✓ Backed up file: $(basename "$source")"
            fi
        fi
    done
    
    # Create manifest
    cat > "$backup_path/MANIFEST.txt" << EOF
Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
Device: $(getprop ro.product.model 2>/dev/null || echo "Unknown")
Android Version: $(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
System Uptime: $(uptime)
EOF
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ✓ Backup created: $backup_path"
    
    # Cleanup old backups
    cleanup_old_backups
}

# List available backups
list_backups() {
    if [ -d "$BACKUP_DIR" ]; then
        echo "Available backups:"
        ls -1dt "$BACKUP_DIR"/backup_* 2>/dev/null | head -10 | while read backup; do
            local manifest="$backup/MANIFEST.txt"
            if [ -f "$manifest" ]; then
                local date=$(grep "Backup Date" "$manifest" | cut -d: -f2-)
                echo "  $(basename "$backup") $date"
            fi
        done
    else
        echo "No backups found"
    fi
}

# Restore from backup
restore_backup() {
    local backup_date=$1
    
    if [ -z "$backup_date" ]; then
        echo "Usage: $0 restore BACKUP_NAME"
        echo "Available backups:"
        list_backups
        return 1
    fi
    
    local backup_path="$BACKUP_DIR/$backup_date"
    
    if [ ! -d "$backup_path" ]; then
        echo "Backup not found: $backup_date"
        list_backups
        return 1
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] Restoring from $backup_date..."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] Current configs will be overwritten!"
    
    # Restore files
    for item in "$backup_path"/*; do
        if [ "$(basename "$item")" != "MANIFEST.txt" ]; then
            if [ -d "$item" ]; then
                # Directory
                rm -rf "${item%/*}/../$(basename "$item")" 2>/dev/null || true
                cp -r "$item" "${item%/*}/../" 2>/dev/null
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ✓ Restored: $(basename "$item")"
            else
                # File
                cp "$item" "$(dirname "$item" | sed "s|$backup_path|$KIOSK_DIR|")" 2>/dev/null
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ✓ Restored: $(basename "$item")"
            fi
        fi
    done
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ✓ Restore complete"
}

# Cleanup old backups
cleanup_old_backups() {
    if [ -d "$BACKUP_DIR" ]; then
        local count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" | wc -l)
        
        # Keep only the 10 most recent
        if [ "$count" -gt 10 ]; then
            find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" -printf '%T@ %p\n' | \
                sort -rn | tail -n +11 | cut -d' ' -f2- | xargs rm -rf
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Cleaned up old backups (kept 10 most recent)"
        fi
        
        # Also cleanup backups older than 7 days
        find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null
    fi
}

# Show backup statistics
show_stats() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          BACKUP STATISTICS                                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ -d "$BACKUP_DIR" ]; then
        local count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" | wc -l)
        local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
        
        echo "Total backups: $count"
        echo "Total backup size: $total_size"
        echo "Retention: $BACKUP_RETENTION_DAYS days"
        echo ""
        echo "Recent backups:"
        list_backups
    else
        echo "No backups found"
    fi
    echo ""
}

# Automatic daily backup (can be called by service)
auto_backup() {
    # Check if backup already exists today
    local today=$(date +%Y%m%d)
    local existing=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_${today}_*" | wc -l)
    
    if [ "$existing" -lt 1 ]; then
        create_backup
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Backup already exists for today"
    fi
}

# Cleanup on signal
trap 'exit 0' SIGTERM SIGINT

# Handle commands
case "${1:-backup}" in
    backup)
        create_backup
        ;;
    list)
        list_backups
        ;;
    restore)
        restore_backup "$2"
        ;;
    stats)
        show_stats
        ;;
    auto)
        auto_backup
        ;;
    *)
        echo "Usage: $0 {backup|list|restore|stats|auto}"
        echo ""
        echo "Commands:"
        echo "  backup          - Create new backup now"
        echo "  list            - List available backups"
        echo "  restore NAME    - Restore from specific backup"
        echo "  stats           - Show backup statistics"
        echo "  auto            - Create backup if not exists today"
        ;;
esac
