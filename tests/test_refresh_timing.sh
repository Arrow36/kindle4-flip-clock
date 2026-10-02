#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DEFINITIONS=$(sed -e '/^main() {/,$d' \
  -e '/^\. "\$SRC_DIR\/time_sync\.sh"$/d' "$ROOT/kfc/src/start.sh")
eval "$DEFINITIONS"

monotonic_centiseconds >/dev/null

save_settings() { :; }
SETTINGS_VERSION=3
RTC_WAKE_LEAD_SECONDS=2
load_settings
[ "$SETTINGS_VERSION" = 5 ]
[ "$RTC_WAKE_LEAD_SECONDS" = 3 ]

NEXT_FRAME_EPOCH=120
NEXT_DISPLAY_CLOCK=120
NEXT_FRAME_KIND=partial
NEXT_FRAME_CHANGED_DIGITS=1
FAKE_CS=5000
monotonic_centiseconds() { echo "$FAKE_CS"; }
sleep_until_monotonic_centiseconds() {
  TEST_SLEEP_TARGET="$1"
  return 0
}

prepare_refresh_release 119
[ "$REFRESH_PROFILE_KIND" = digit1 ]
[ "$REFRESH_DURATION_MS" = 800 ]
[ "$REFRESH_BOUNDARY_UPTIME_CS" = 5100 ]
[ "$REFRESH_PLANNED_START_UPTIME_CS" = 5060 ]
[ "$TEST_SLEEP_TARGET" = 5060 ]
[ "$(format_monotonic_centiseconds 5060)" = 50.60 ]

NEXT_FRAME_CHANGED_DIGITS=2
select_refresh_profile 120
[ "$REFRESH_PROFILE_KIND" = digit2 ]
[ "$REFRESH_DURATION_MS" = 800 ]

NEXT_FRAME_KIND=png
select_refresh_profile 120
[ "$REFRESH_PROFILE_KIND" = full ]
[ "$REFRESH_DURATION_MS" = 1400 ]

parse_partial_detail "170 612 260 178 DIGITS 1 START_CS 5058 END_CS 5133"
[ "$PARTIAL_CHANGED_COUNT" = 1 ]
[ "$PARTIAL_START_CS" = 5058 ]
[ "$PARTIAL_END_CS" = 5133 ]

[ "$(calc_effective_ppm 4120 5400)" = "5400" ]
[ "$(calc_effective_ppm 4050 5400)" = "5400" ]
[ "$(calc_effective_ppm 4000 5400)" = "2700" ]
[ "$(calc_effective_ppm 3975 5400)" = "1350" ]
[ "$(calc_effective_ppm 3950 5400)" = "0" ]
[ "$(calc_effective_ppm 3800 5400)" = "0" ]
[ "$(calc_effective_ppm 4120 0)" = "0" ]

printf 'refresh timing tests passed\n'
