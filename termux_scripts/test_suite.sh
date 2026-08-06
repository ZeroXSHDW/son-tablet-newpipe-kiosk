#!/system/bin/sh
# Device-side smoke and runtime gate for the active kiosk stack.
#
# This is intentionally a health gate, not a synthetic claim that a network
# stream or Android accessibility service was tested. It reports warnings for
# environmental conditions and fails only on required runtime invariants.

set -u

HOME_DIR="${HOME_DIR:-/data/data/com.termux/files/home}"
KIOSK_DIR="${KIOSK_DIR:-/sdcard/Kiosk}"
PRIVATE_KIOSK_DIR="$HOME_DIR/Kiosk"
TEST_LOG="${TEST_LOG:-$HOME_DIR/test_results.log}"
TEST_REPORT="${TEST_REPORT:-$HOME_DIR/test_report.txt}"

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_WARNED=0
TESTS_FAILED=0

log_test() {
    test_name="$1"
    result="$2"
    message="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    case "$result" in
        PASS)
            TESTS_PASSED=$((TESTS_PASSED + 1))
            ;;
        WARN)
            TESTS_WARNED=$((TESTS_WARNED + 1))
            ;;
        *)
            TESTS_FAILED=$((TESTS_FAILED + 1))
            result=FAIL
            ;;
    esac
    line="[$result] $test_name: $message"
    echo "$line" | tee -a "$TEST_LOG"
}

service_count() {
    name="$1"
    ps -ef 2>/dev/null \
        | grep -F "bash $HOME_DIR/$name" \
        | grep -v grep \
        | wc -l \
        | tr -d ' '
}

test_required_file() {
    path="$1"
    name="$2"
    if [ -f "$path" ]; then
        log_test "$name" PASS "$path"
    else
        log_test "$name" FAIL "missing: $path"
    fi
}

test_service() {
    name="$1"
    label="$2"
    if [ ! -f "$HOME_DIR/$name" ]; then
        log_test "$label script" FAIL "missing: $HOME_DIR/$name"
        return
    fi
    count=$(service_count "$name")
    if [ "$count" = "1" ]; then
        log_test "$label process" PASS "one active instance"
    elif [ "$count" -gt 1 ] 2>/dev/null; then
        # A supervised daemon can briefly overlap while service_monitor is
        # completing a restart. Only fail when the duplicate survives a
        # second sample; the host health gate still reports instantaneous
        # duplicates for release evidence.
        sleep 1
        stable_count=$(service_count "$name")
        if [ "$stable_count" -gt 1 ] 2>/dev/null; then
            log_test "$label process" FAIL "$stable_count active instances (duplicate daemon)"
        else
            log_test "$label process" PASS "one active instance after transient restart"
        fi
    else
        log_test "$label process" FAIL "no active instance"
    fi
}

run_all_tests() {
    : > "$TEST_LOG"
    echo "KIOSK RUNTIME GATE $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Active stack: Kiosk Booter -> RUN_COMMAND -> seven supervised daemons"
    echo ""

    test_required_file "$HOME_DIR/kiosk_config.sh" "Authoritative configuration"
    test_required_file "$HOME_DIR/boot_orchestrator_v2_integrated.sh" "Integrated boot orchestrator"
    test_required_file "$HOME_DIR/daemon_lib.sh" "Daemon safety library"
    test_required_file "$HOME_DIR/.termux/boot/start.sh" "Compatibility Termux:Boot entrypoint"
    if grep -q "exit 0" "$HOME_DIR/.termux/boot/start.sh" 2>/dev/null \
        && ! grep -q "boot_orchestrator" "$HOME_DIR/.termux/boot/start.sh" 2>/dev/null; then
        log_test "Single startup owner" PASS "Termux:Boot is a no-op; Kiosk Booter owns RUN_COMMAND"
    else
        log_test "Single startup owner" FAIL "compatibility entrypoint could launch a second stack"
    fi

    if [ -f "$HOME_DIR/kiosk_config.sh" ] \
        && /data/data/com.termux/files/usr/bin/bash -c \
        '. "$1" && kiosk_validate_config' _ "$HOME_DIR/kiosk_config.sh" >/dev/null 2>&1; then
        phase=$(/data/data/com.termux/files/usr/bin/bash -c \
            '. "$1" && kiosk_current_phase' _ "$HOME_DIR/kiosk_config.sh" 2>/dev/null | tr -d '\r\n')
        case "$phase" in
            MORNING|LEARNING|RELAXING|BEDTIME|NIGHT)
                log_test "Configuration validation" PASS "valid schedule; current phase=$phase"
                ;;
            *)
                log_test "Configuration validation" FAIL "invalid current phase: $phase"
                ;;
        esac
    else
        log_test "Configuration validation" FAIL "kiosk_config.sh rejected its own values"
    fi

    test_service "newpipe_24x7.sh" "NewPipe playback owner"
    test_service "fullscreen_enforcer.sh" "Fullscreen enforcer"
    test_service "volume_guard.sh" "Volume guard"
    test_service "wallpaper_live.sh" "Live wallpaper"
    test_service "wifi_keepalive.sh" "Wi-Fi keepalive"
    test_service "download_scheduler.sh" "Offline downloader"
    test_service "service_monitor.sh" "Service monitor"

    for package in com.termux org.schabi.newpipe org.videolan.vlc com.android.kioskbooter; do
        if pm path "$package" >/dev/null 2>&1; then
            log_test "Installed package: $package" PASS "package available"
        else
            log_test "Installed package: $package" FAIL "package missing"
        fi
    done

    parent=$(cat "$KIOSK_DIR/parent_mode.txt" 2>/dev/null \
        || cat "$PRIVATE_KIOSK_DIR/parent_mode.txt" 2>/dev/null \
        || echo child)
    if [ "$parent" = "child" ]; then
        log_test "Child mode" PASS "parent_mode.txt is child or absent"
    else
        log_test "Child mode" FAIL "parent mode is $parent"
    fi

    focus=$(dumpsys window 2>/dev/null | grep -E 'mCurrentFocus' | head -1 || true)
    if [ -z "$focus" ]; then
        if grep -q '"status":"playing"' "$PRIVATE_KIOSK_DIR/health_24x7.json" 2>/dev/null; then
            log_test "Foreground playback app" WARN "Termux cannot read WindowManager; host HEALTH-CHECK must verify focus"
        else
            log_test "Foreground playback app" FAIL "no host focus and no playing health marker"
        fi
    else
        case "$focus" in
            *org.schabi.newpipe/*|*org.videolan.vlc/*)
                log_test "Foreground playback app" PASS "$focus"
                ;;
            *)
                log_test "Foreground playback app" FAIL "NewPipe/VLC is not foreground: $focus"
                ;;
        esac
    fi

    accessibility=$(dumpsys accessibility 2>/dev/null || true)
    if [ -z "$accessibility" ] || echo "$accessibility" | grep -qiE 'permission denial|missing android\.permission\.dump|not allowed'; then
        log_test "Accessibility input barrier" WARN "Termux cannot read accessibility state; host HEALTH-CHECK must verify it"
    elif echo "$accessibility" \
        | grep -q 'com.android.kioskbooter/com.android.kioskbooter.InputBlockerService'; then
        log_test "Accessibility input barrier" PASS "Kiosk Booter service enabled"
    else
        log_test "Accessibility input barrier" FAIL "Kiosk Booter service is not enabled"
    fi

    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        log_test "Network connectivity" PASS "internet probe succeeded"
    else
        log_test "Network connectivity" WARN "offline or captive network; online playback not proven"
    fi

    assets_ok=1
    for asset in newpipe_subscriptions.json phase_schedule.json download_schedule.json; do
        if [ ! -f "$KIOSK_DIR/$asset" ] && [ ! -f "$PRIVATE_KIOSK_DIR/$asset" ]; then
            assets_ok=0
        fi
    done
    if [ "$assets_ok" = "1" ]; then
        log_test "Kiosk configuration assets" PASS "subscriptions, phases, and download policy present"
    else
        log_test "Kiosk configuration assets" FAIL "one or more Kiosk JSON assets are missing"
    fi

    echo ""
    echo "Total: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Warnings: $TESTS_WARNED"
    echo "Failed: $TESTS_FAILED"
    {
        echo "KIOSK RUNTIME GATE $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Passed: $TESTS_PASSED / $TESTS_TOTAL"
        echo "Warnings: $TESTS_WARNED"
        echo "Failed: $TESTS_FAILED"
        echo ""
        cat "$TEST_LOG"
    } > "$TEST_REPORT"
}

trap 'exit 130' INT TERM
run_all_tests

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
