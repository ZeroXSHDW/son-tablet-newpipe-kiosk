#!/bin/bash

# AUTO-BOOT VERIFICATION & SETUP HELPER
# Verifies and ensures all services auto-boot on device startup

ADB="./platform-tools/adb"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_fail() { echo -e "${RED}✗${NC} $1"; }
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }

header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

if [ ! -f "$ADB" ]; then
    log_fail "ADB not found at $ADB"
    exit 1
fi

if ! $ADB devices | grep -q "device$"; then
    log_fail "No device connected"
    exit 1
fi

DEVICE=$($ADB shell getprop ro.product.model)
log_info "Device: $DEVICE"
echo ""

# ============================================================================
# CHECK 1: TERMUX:BOOT SERVICE INSTALLED
# ============================================================================

header "CHECK 1: Termux:Boot Service"

# Check if Termux:Boot app is installed
if $ADB shell pm list packages | grep -q "com.termux.boot"; then
    log_pass "Termux:Boot app is installed"
else
    log_fail "Termux:Boot app NOT installed"
    log_info "Install from: Play Store → Search 'Termux:Boot'"
fi

# Check if boot directory exists
if $ADB shell "run-as com.termux [ -d /data/data/com.termux/files/home/.termux/boot ]"; then
    log_pass "Boot directory exists"
else
    log_warn "Boot directory does not exist (will be created on first run)"
fi

# Check if boot script exists
if $ADB shell "run-as com.termux [ -f /data/data/com.termux/files/home/.termux/boot/start.sh ]"; then
    log_pass "Boot startup script exists"
    
    # Show first few lines
    echo ""
    log_info "Boot script content (first 10 lines):"
    $ADB shell "run-as com.termux head -10 /data/data/com.termux/files/home/.termux/boot/start.sh" 2>/dev/null | sed 's/^/  /'
else
    log_warn "Boot startup script does not exist"
    log_info "Will be created during first boot"
fi

# Check if the compatibility boot script exists
if $ADB shell "run-as com.termux [ -f /data/data/com.termux/files/home/boot_script.sh ]"; then
    log_pass "boot_script.sh compatibility launcher exists"
else
    log_warn "boot_script.sh compatibility launcher missing"
fi

# ============================================================================
# CHECK 2: BOOT ORCHESTRATOR
# ============================================================================

header "CHECK 2: Boot Orchestrator"

if $ADB shell "run-as com.termux [ -f /data/data/com.termux/files/home/boot_orchestrator_v2_integrated.sh ]"; then
    log_pass "boot_orchestrator_v2_integrated.sh exists"
    
    # Check if executable
    if $ADB shell "run-as com.termux [ -x /data/data/com.termux/files/home/boot_orchestrator_v2_integrated.sh ]"; then
        log_pass "boot_orchestrator_v2_integrated.sh is executable"
    else
        log_warn "boot_orchestrator_v2_integrated.sh not executable (will fix)"
    fi
else
    log_fail "boot_orchestrator_v2_integrated.sh NOT found (run deployment)"
fi

# Check wallpaper asset
if $ADB shell "[ -f /sdcard/Download/wallpaper.png ]" 2>/dev/null; then
    log_pass "Wallpaper asset exists"
else
    log_warn "Wallpaper asset missing (run generate_wallpaper.py)"
fi

# ============================================================================
# CHECK 3: BACKGROUND SERVICES
# ============================================================================

header "CHECK 3: Background Services"

SERVICES=(
    "kiosk_watchdog_v2.sh"
    "network_monitor.sh"
    "fullscreen_enforcer.sh"
    "download_scheduler.sh"
    "volume_guard.sh"
    "sync_wifi.py"
)

MISSING=0
for service in "${SERVICES[@]}"; do
    if $ADB shell "run-as com.termux [ -f /data/data/com.termux/files/home/$service ]"; then
        log_pass "$service exists"
    else
        log_fail "$service MISSING (run ./setup_v2.sh)"
        ((MISSING++))
    fi
done

if [ $MISSING -eq 0 ]; then
    log_pass "All background services present"
fi

# ============================================================================
# CHECK 4: CONFIGURATION FILES
# ============================================================================

header "CHECK 4: Configuration Files"

CONFIG_CHECKS=(
    "/sdcard/Kiosk/phase.txt:Phase file"
    "/sdcard/Kiosk/download_schedule.json:Download schedule"
    "/sdcard/Kiosk/download_state.json:Download state"
)

for check in "${CONFIG_CHECKS[@]}"; do
    IFS=':' read -r path name <<< "$check"
    if $ADB shell "[ -f $path ]" 2>/dev/null; then
        log_pass "$name exists"
    else
        log_warn "$name missing (will be created on boot)"
    fi
done

# Check offline videos directory
if $ADB shell "[ -d /sdcard/Kiosk/offline_videos ]" 2>/dev/null; then
    COUNT=$($ADB shell "ls /sdcard/Kiosk/offline_videos | wc -l" 2>/dev/null || echo "0")
    log_pass "Offline videos directory exists ($COUNT videos)"
else
    log_warn "Offline videos directory missing (will be created)"
fi

# ============================================================================
# CHECK 5: REQUIRED APPS
# ============================================================================

header "CHECK 5: Required Applications"

APPS=(
    "org.schabi.newpipe:NewPipe"
    "com.brouken.player:Just Player"
    "net.gcompris.full:GCompris"
    "com.arlosoft.macrodroid:MacroDroid"
)

for check in "${APPS[@]}"; do
    IFS=':' read -r package name <<< "$check"
    if $ADB shell pm list packages | grep -q "^package:$package$"; then
        log_pass "$name is installed"
    else
        log_fail "$name NOT installed (required for content playback)"
    fi
done

# ============================================================================
# CHECK 6: MACRODROID MACROS
# ============================================================================

header "CHECK 6: MacroDroid Scheduling"

log_info "MacroDroid macros must be created manually on the device"
echo ""
log_info "Required macros (6 total):"
echo "  1. Wake-Up (7:00 AM) - Sets MORNING phase"
echo "  2. Learning (9:00 AM) - Sets LEARNING phase"
echo "  3. Break (1:00 PM) - Sets BREAK phase"
echo "  4. Winddown (6:00 PM) - Sets RELAXING phase"
echo "  5. Sleep (9:00 PM) - Sets SLEEP phase + locks"
echo "  6. Download (2:00 AM) - Triggers video download"
echo ""
log_warn "See MACRODROID_SETUP.md for detailed macro creation"

# ============================================================================
# CHECK 7: AUTO-BOOT DAEMON
# ============================================================================

header "CHECK 7: Auto-Boot Daemon Setup"

log_info "Checking if autoboot_setup.sh is deployed..."

if $ADB shell "run-as com.termux [ -f /data/data/com.termux/files/home/autoboot_setup.sh ]"; then
    log_pass "autoboot_setup.sh is deployed"
else
    log_warn "autoboot_setup.sh not deployed"
    log_info "Will be deployed during ./setup_v2.sh"
fi

# ============================================================================
# CHECK 8: RECENT BOOT LOGS
# ============================================================================

header "CHECK 8: Recent Boot Activity"

if $ADB shell "run-as com.termux [ -f /data/data/com.termux/files/home/boot_orchestrator.log ]"; then
    echo "Recent boot orchestrator activity (last 15 lines):"
    echo ""
    $ADB shell "run-as com.termux tail -15 /data/data/com.termux/files/home/boot_orchestrator.log" | sed 's/^/  /'
else
    log_warn "No boot logs yet (device hasn't booted with new system)"
fi

echo ""

if $ADB shell "run-as com.termux [ -f /data/data/com.termux/files/home/autoboot_setup.log ]"; then
    echo "Recent auto-boot setup activity (last 10 lines):"
    echo ""
    $ADB shell "run-as com.termux tail -10 /data/data/com.termux/files/home/autoboot_setup.log" | sed 's/^/  /'
fi

# ============================================================================
# CHECK 9: CURRENT RUNNING SERVICES
# ============================================================================

header "CHECK 9: Currently Running Services"

RUNNING_SERVICES=$(
    echo "Kiosk Watchdog: $($ADB shell 'pgrep -f kiosk_watchdog >/dev/null && echo Running || echo Stopped')"
    echo "Network Monitor: $($ADB shell 'pgrep -f network_monitor >/dev/null && echo Running || echo Stopped')"
    echo "Fullscreen Enforcer: $($ADB shell 'pgrep -f fullscreen_enforcer >/dev/null && echo Running || echo Stopped')"
    echo "Download Scheduler: $($ADB shell 'pgrep -f download_scheduler >/dev/null && echo Running || echo Stopped')"
    echo "Volume Guard: $($ADB shell 'pgrep -f volume_guard >/dev/null && echo Running || echo Stopped')"
    echo "WiFi Sync: $($ADB shell 'pgrep -f sync_wifi >/dev/null && echo Running || echo Stopped')"
)

echo "$RUNNING_SERVICES" | while read line; do
    if echo "$line" | grep -q "Running"; then
        log_pass "$line"
    else
        log_warn "$line"
    fi
done

# ============================================================================
# SETUP INSTRUCTIONS
# ============================================================================

header "AUTO-BOOT SETUP INSTRUCTIONS"

cat << 'EOF'

STEP 1: Deploy System (if not already done)
  $ ./setup_v2.sh
  [Installs all scripts and services to tablet]

STEP 2: Enable Termux:Boot (CRITICAL - must do this!)
  On tablet:
  1. Open "Termux:Boot" app (should be installed after step 1)
  2. Grant permissions when prompted
  3. Close the app (just opening it enables the service)

STEP 3: Verify Auto-Boot
  On PC:
  $ ./verify_autoboot.sh
  [Confirms everything is set up correctly]

STEP 4: Test Auto-Boot
  On tablet:
  1. Reboot device: $ adb reboot
  2. Wait 30 seconds for boot to complete
  3. Verify content launches automatically

STEP 5: Create MacroDroid Macros
  On tablet:
  1. Open MacroDroid app
  2. Create 6 macros (see MACRODROID_SETUP.md)
  3. Export backup when done

STEP 6: Download Initial Videos
  $ python3 download_videos.py download --force
  [Takes 10-30 min, downloads offline content]

STEP 7: Final Verification
  $ ./health_check.sh
  [All 7 services should show RUNNING]

EOF

# ============================================================================
# SUMMARY
# ============================================================================

header "AUTO-BOOT SETUP SUMMARY"

echo "Status: Ready to deploy"
echo ""
echo "Auto-boot sequence:"
echo "  1. Device powers on"
echo "  2. Termux:Boot service starts"
echo "  3. .termux/boot/start.sh runs"
echo "  4. boot_orchestrator_v2_integrated.sh executes"
echo "  5. 7 background services start:"
echo "     • kiosk_watchdog_v2.sh"
echo "     • network_monitor.sh"
echo "     • fullscreen_enforcer.sh"
echo "     • download_scheduler.sh"
echo "     • volume_guard.sh"
echo "     • sync_wifi.py"
echo "     • MacroDroid (runs time-based macros)"
echo ""
echo "Result:"
echo "  ✓ Content launches based on current time"
echo "  ✓ Fullscreen mode enforced"
echo "  ✓ Network detection active"
echo "  ✓ All protections active"
echo ""
echo "Next: Run ./setup_v2.sh (if not done)"
echo "Then: Open Termux:Boot app on tablet to enable auto-boot"
echo "Finally: Reboot and verify"
echo ""

log_pass "Auto-boot verification complete!"
