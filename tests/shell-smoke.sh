#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

export HOME="$TEMP_ROOT/home"
mkdir -p "$HOME/Kiosk"
cp "$ROOT/termux_scripts/kiosk_config.sh" "$HOME/kiosk_config.sh"
cp "$ROOT/termux_scripts/Kiosk/online_playlist.json" "$HOME/Kiosk/online_playlist.json"

fail() {
    echo "SMOKE FAIL: $*" >&2
    exit 1
}

assert_eq() {
    [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

. "$HOME/kiosk_config.sh"
. "$ROOT/termux_scripts/daemon_lib.sh"
. "$ROOT/termux_scripts/playlist_lib.sh"

kiosk_validate_config || fail "authoritative configuration rejected"
assert_eq "$(kiosk_volume_for_phase MORNING)" "12"
assert_eq "$(kiosk_volume_for_phase BEDTIME)" "3"
assert_eq "$(kiosk_volume_for_phase NIGHT)" "3"
assert_eq "$(kiosk_brightness_for_phase NIGHT)" "25"

if kiosk_validate_hhmm TEST_TIME 2360; then
    fail "invalid 2360 time was accepted"
fi
if kiosk_validate_range TEST_LEVEL 16 15; then
    fail "out-of-range level was accepted"
fi

kiosk_current_phase() { echo BEDTIME; }
assert_eq "$(get_subscription_channel_url)" "$SLEEP_CHANNEL_URL"

kiosk_current_phase() { echo LEARNING; }
rm -f "$HOME/Kiosk/subscription_channel_index.txt"
first="$(get_subscription_channel_url)"
second="$(get_subscription_channel_url)"
case "$first" in
    https://www.youtube.com/@msrachel/videos|https://www.youtube.com/@TractorTed/videos|https://www.youtube.com/@Teletubbies/videos|https://www.youtube.com/channel/UCrbHp6Xh0oEOhOozMk9t_wQ/videos|https://www.youtube.com/@edubuzzkids/videos) ;;
    *) fail "unexpected daytime channel: $first" ;;
esac
[ "$first" != "$second" ] || fail "daytime channel rotation did not advance"

playlist_url="$(get_playlist_url)"
grep -Fq "$playlist_url" "$HOME/Kiosk/online_playlist.json" \
    || fail "playlist selector returned a URL outside the checked-in playlist"

echo "SHELL_SMOKE_PASS"
