#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DEFINITIONS=$(sed -e '/^main() {/,$d' \
  -e '/^\. "\$SRC_DIR\/time_sync\.sh"$/d' "$ROOT/kfc/src/start.sh")
eval "$DEFINITIONS"

monotonic_centiseconds >/dev/null

log_message() { :; }
save_settings() { :; }
SETTINGS_VERSION=3
RTC_WAKE_LEAD_SECONDS=2
load_settings
[ "$SETTINGS_VERSION" = 6 ]
[ "$RTC_WAKE_LEAD_SECONDS" = 3 ]
[ "$AUTO_DRIFT_CALIBRATION" = 1 ]

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

# Effective PPM no longer depends on voltage; trim may drive it negative.
[ "$(calc_effective_ppm 4120 5400)" = "5400" ]
[ "$(calc_effective_ppm 3800 5400)" = "5400" ]
[ "$(calc_effective_ppm "" 5400)" = "5400" ]
[ "$(calc_effective_ppm 4120 0)" = "0" ]
[ "$(calc_effective_ppm 4120 0 3000)" = "0" ]
[ "$(calc_effective_ppm 3800 5400 300)" = "5700" ]
[ "$(calc_effective_ppm 3800 5400 -9000)" = "-3600" ]
[ "$(calc_effective_ppm 4120 5400 9000)" = "12000" ]
[ "$(calc_effective_ppm 4120 5400 -20000)" = "-8000" ]

# Signed drift adjustment with millisecond carry.
DRIFT_REMAINDER_MS=0
for _ in 1 2 3; do calc_drift_adjustment 57 5400; [ "$DRIFT_ADJUST_SECONDS" = 0 ]; done
[ "$DRIFT_REMAINDER_MS" = 918 ]
calc_drift_adjustment 57 5400
[ "$DRIFT_ADJUST_SECONDS" = -1 ]
[ "$DRIFT_REMAINDER_MS" = 224 ]
DRIFT_REMAINDER_MS=0
for _ in 1 2 3 4; do calc_drift_adjustment 57 -3600; [ "$DRIFT_ADJUST_SECONDS" = 0 ]; done
calc_drift_adjustment 57 -3600
[ "$DRIFT_ADJUST_SECONDS" = 1 ]
[ "$DRIFT_REMAINDER_MS" = -25 ]
if calc_drift_adjustment 57 0; then exit 1; fi

# Test update_adaptive_drift_trim
RUNTIME_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'kfc')
AUTO_DRIFT_CALIBRATION=1
RTC_DRIFT_COMPENSATION_PPM=5400
ADAPTIVE_PPM_TRIM=0
SYNC_STAT_FILE="$RUNTIME_DIR/last_sntp_sync"
printf "OFFSET_MS=-1800\nELAPSED_SEC=3600\nDRIFT_PPM=500\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "250" ]
[ "$(cat "$RUNTIME_DIR/adaptive_ppm.trim")" = "250" ]
[ ! -f "$SYNC_STAT_FILE" ]

printf "OFFSET_MS=-1800\nELAPSED_SEC=3600\nDRIFT_PPM=400\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "450" ]

# Large slow residual: step capped at 6000, trim may push PPM negative.
printf "OFFSET_MS=72000\nELAPSED_SEC=3600\nDRIFT_PPM=-20000\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-5550" ]
[ "$(calc_effective_ppm "" 5400 "$ADAPTIVE_PPM_TRIM")" = "-150" ]

# Anti-windup: trim stops where the effective PPM reaches -8000.
for _ in 1 2 3; do
  printf "OFFSET_MS=72000\nELAPSED_SEC=3600\nDRIFT_PPM=-20000\n" > "$SYNC_STAT_FILE"
  update_adaptive_drift_trim
done
[ "$ADAPTIVE_PPM_TRIM" = "-13400" ]

# Implausible samples are ignored.
printf "OFFSET_MS=-90000\nELAPSED_SEC=3600\nDRIFT_PPM=25000\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-13400" ]
printf "OFFSET_MS=-9000\nELAPSED_SEC=20000\nDRIFT_PPM=450\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-13400" ]

rm -rf "$RUNTIME_DIR"

printf 'refresh timing tests passed\n'
