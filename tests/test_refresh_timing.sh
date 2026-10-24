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
[ "$SETTINGS_VERSION" = 8 ]
[ "$RTC_WAKE_LEAD_SECONDS" = 2 ]
[ "$AUTO_DRIFT_CALIBRATION" = 1 ]
[ "$AUTO_TIME_SYNC_INTERVAL_HOURS" = 0 ]
[ "$BATTERY_REFRESH_SETTLE_SECONDS" = 0 ]

SETTINGS_VERSION=7
RTC_WAKE_LEAD_SECONDS=1
AUTO_TIME_SYNC_INTERVAL_HOURS=4
load_settings
[ "$SETTINGS_VERSION" = 8 ]
[ "$RTC_WAKE_LEAD_SECONDS" = 2 ]
[ "$AUTO_TIME_SYNC_INTERVAL_HOURS" = 6 ]

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
mkdir -p "$RUNTIME_DIR" /tmp/kfc
BASE_DIR="$RUNTIME_DIR"
LOG_DIR="$RUNTIME_DIR"
LOG_FILE="$RUNTIME_DIR/kfc.log"
SYNC_PID_FILE="$RUNTIME_DIR/time_sync.pid"
SYNC_RESULT_FILE="$RUNTIME_DIR/time_sync.result"
SYNC_RESULT_TMP="$RUNTIME_DIR/time_sync.result.tmp"
TRIM_PERSIST_FILE="$BASE_DIR/learned_ppm.trim"
AUTO_DRIFT_CALIBRATION=1
RTC_DRIFT_COMPENSATION_PPM=5400
ADAPTIVE_PPM_TRIM=0
SYNC_STAT_FILE="$RUNTIME_DIR/last_sntp_sync"
printf "OFFSET_MS=-1800\nELAPSED_SEC=3600\nDRIFT_PPM=500\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "250" ]
[ "$(cat "$RUNTIME_DIR/adaptive_ppm.trim")" = "250" ]
[ "$(cat "$TRIM_PERSIST_FILE")" = "250" ]
[ ! -f "$SYNC_STAT_FILE" ]

# Steady-state zone (< 1500 PPM): 50% critical damping
printf "OFFSET_MS=-1800\nELAPSED_SEC=3600\nDRIFT_PPM=400\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "450" ]

# Transition zone (1500 <= |PPM| < 3000): 60% step (2000 * 3 / 5 = 1200)
printf "OFFSET_MS=-7200\nELAPSED_SEC=3600\nDRIFT_PPM=2000\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "1650" ]

# Aggressive zone (|PPM| >= 3000): 80% step (-5000 * 4 / 5 = -4000)
printf "OFFSET_MS=18000\nELAPSED_SEC=3600\nDRIFT_PPM=-5000\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-2350" ]

# Large residual: step capped at 10000 PPM
printf "OFFSET_MS=72000\nELAPSED_SEC=3600\nDRIFT_PPM=-20000\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-12350" ]

# Anti-windup: trim stops where effective PPM reaches -8000 (trim = -13400)
printf "OFFSET_MS=72000\nELAPSED_SEC=3600\nDRIFT_PPM=-20000\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-13400" ]
[ "$(calc_effective_ppm "" 5400 "$ADAPTIVE_PPM_TRIM")" = "-8000" ]

# Short elapsed interval accepted (>= 600s)
printf "OFFSET_MS=1000\nELAPSED_SEC=900\nDRIFT_PPM=0\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ ! -f "$SYNC_STAT_FILE" ]

# Too-short interval ignored (< 600s): trim is unchanged
printf "OFFSET_MS=1000\nELAPSED_SEC=300\nDRIFT_PPM=500\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-13400" ]

# Test restore_persistent_adaptive_trim
rm -f "$RUNTIME_DIR/adaptive_ppm.trim"
ADAPTIVE_PPM_TRIM=0
restore_persistent_adaptive_trim
[ "$ADAPTIVE_PPM_TRIM" = "-13400" ]
[ "$(cat "$RUNTIME_DIR/adaptive_ppm.trim")" = "-13400" ]

# Implausible samples are ignored
printf "OFFSET_MS=-90000\nELAPSED_SEC=3600\nDRIFT_PPM=25000\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-13400" ]
printf "OFFSET_MS=-9000\nELAPSED_SEC=90000\nDRIFT_PPM=450\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-13400" ]

# Test hourly auto-sync scheduling logic
CURRENT_FRAME_EPOCH=3600
AUTO_TIME_SYNC_INTERVAL_HOURS=1
SYNC_PID=""
CURRENT_FRAME_BATTERY=80
AUTO_SYNC_RESULT_FILE="$RUNTIME_DIR/auto_sync.result"
AUTO_SYNC_RESULT_TMP="$RUNTIME_DIR/auto_sync.result.tmp"
get_battery_voltage() { echo 4000; }
get_battery_level() { echo 80; }
BATTERY_REFRESH_SETTLE_SECONDS=0

# Mock scheduler_now to 19:00:00 (epoch 3600)
scheduler_now() { echo 3600; }
time_sync_now() { return 0; }

# Case 1: First top-of-the-hour after startup (LAST_AUTO_SYNC_EPOCH=0, startup at 1620, elapsed=1980s >= 300s)
LAST_AUTO_SYNC_EPOCH=0
LAST_SYNC_EPOCH=1620
SYNC_PID=""
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 1 ]

# Case 2: Cooldown active (synced 100s ago at epoch 3500)
LAST_SYNC_EPOCH=3500
SYNC_PID=""
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 0 ]

# Case 3: Regular hourly sync (interval=1, last sync at epoch 0)
LAST_AUTO_SYNC_EPOCH=0
LAST_SYNC_EPOCH=0
SYNC_PID=""
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 1 ]

# Case 4: Unconverged (DRIFT_CONVERGED_STREAK < 2) forces 1h sync even when AUTO_TIME_SYNC_INTERVAL_HOURS=6
AUTO_TIME_SYNC_INTERVAL_HOURS=6
DRIFT_CONVERGED_STREAK=0
LAST_AUTO_SYNC_EPOCH=3600
LAST_SYNC_EPOCH=3600
SYNC_PID=""
scheduler_now() { echo 7200; }
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 1 ]

# Two consecutive accurate syncs (|DRIFT_PPM| <= 300 and |OFFSET_MS| <= 2000) reach DRIFT_CONVERGED_STREAK=2
printf "OFFSET_MS=-360\nELAPSED_SEC=3600\nDRIFT_PPM=100\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$DRIFT_CONVERGED_STREAK" = 1 ]
SYNC_PID=""
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 1 ]

printf "OFFSET_MS=180\nELAPSED_SEC=3600\nDRIFT_PPM=-50\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$DRIFT_CONVERGED_STREAK" = 2 ]

# Case 5: Converged (DRIFT_CONVERGED_STREAK=2), Interval=2: 1 hour later at 20:00 (not due), 2 hours later at 21:00 (due)
AUTO_TIME_SYNC_INTERVAL_HOURS=2
LAST_AUTO_SYNC_EPOCH=3600
LAST_SYNC_EPOCH=3600
SYNC_PID=""
scheduler_now() { echo 7200; }
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 0 ]

scheduler_now() { echo 10800; }
SYNC_PID=""
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 1 ]

# Case 6: Converged (DRIFT_CONVERGED_STREAK=2), Interval=4: 3 hours later at 22:00 (not due), 4 hours later at 23:00 (due)
AUTO_TIME_SYNC_INTERVAL_HOURS=4
LAST_AUTO_SYNC_EPOCH=3600
LAST_SYNC_EPOCH=3600
scheduler_now() { echo 14400; }
SYNC_PID=""
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 0 ]
scheduler_now() { echo 18000; }
SYNC_PID=""
refresh_battery_sample_after_hourly_full_refresh >/dev/null
[ "$AUTO_SYNC_DUE" = 1 ]

# Test low-voltage adaptive drift damping (< 3600mV clamped to +/-500) and streak reset on large drift
get_battery_voltage() { echo 3500; }
printf "OFFSET_MS=-7200\nELAPSED_SEC=3600\nDRIFT_PPM=2000\n" > "$SYNC_STAT_FILE"
ADAPTIVE_PPM_TRIM=0
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "500" ]
[ "$DRIFT_CONVERGED_STREAK" = "0" ]

# Test monotonic discharge filter (when not charging, sampled 85 > current 80 is capped to 80)
get_battery_level() { echo 85; }
get_battery_voltage() { echo 4000; }
is_battery_charging() { return 1; }
CURRENT_FRAME_BATTERY=80
NEXT_FRAME_EPOCH=3600
SYNC_PID=""
cancel_next_frame_render
start_next_frame_render
[ "$NEXT_FRAME_BATTERY" = 80 ]

# When charging, battery level can rise (sampled 85 is allowed)
is_battery_charging() { return 0; }
CURRENT_FRAME_BATTERY=80
NEXT_FRAME_EPOCH=3600
SYNC_PID=""
cancel_next_frame_render
start_next_frame_render
[ "$NEXT_FRAME_BATTERY" = 85 ]
cancel_next_frame_render

# Test that render_current_frame preserves locked CURRENT_FRAME_BATTERY instead of re-sampling under load
get_battery_level() { echo 65; }
CURRENT_FRAME_BATTERY=82
CURRENT_FRAME_EPOCH=3660
render_frame() { :; }
render_current_frame
[ "$CURRENT_FRAME_BATTERY" = 82 ]
[ "$BATTERY_LEVEL" = 82 ]

# Test ACCUMULATED_SLEPT_SECONDS denominator in update_adaptive_drift_trim
# OFFSET_MS=-1800ms over ELAPSED_SEC=3600s (naive 500ppm), but actual sleep was 1800s -> true residual is 1000ppm -> 50% step = +500ppm
get_battery_voltage() { echo 4000; }
rm -f "$RUNTIME_DIR/battery.volt"
ADAPTIVE_PPM_TRIM=0
ACCUMULATED_SLEPT_SECONDS=1800
printf "OFFSET_MS=-1800\nELAPSED_SEC=3600\nDRIFT_PPM=500\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "500" ]
[ "$ACCUMULATED_SLEPT_SECONDS" = "0" ]

# Test synchronous partial pre-render when PARTIAL_ELIGIBLE=1 (zero background subshell fork)
RENDER_SERVER_READY=1
HELP_VISIBLE=0
CURRENT_FRAME_EPOCH=3600
NEXT_FRAME_EPOCH=3660
CURRENT_FRAME_BATTERY=82
NEXT_RENDER_PID=""
rm -f "$PARTIAL_DISABLED_FILE"
prepare_partial_frame() {
  PARTIAL_CHANGED_COUNT=2
  return 0
}
start_next_frame_render
[ -z "$NEXT_RENDER_PID" ]
[ "$NEXT_FRAME_READY" = 1 ]
[ "$NEXT_FRAME_KIND" = "partial" ]
[ "$NEXT_FRAME_CHANGED_DIGITS" = "2" ]
[ "$(cat "$NEXT_FRAME_META")" = "partial 3660 82 2" ]

# Test WAIT_UNTIL FFI boundary assignment in prepare_refresh_release
run_wait_until_renderer() {
  REFRESH_BOUNDARY_UPTIME_CS=7500
  REFRESH_PLANNED_START_UPTIME_CS=7460
  return 0
}
REFRESH_SCHEDULE_EPOCH=0
prepare_refresh_release 3659
[ "$REFRESH_BOUNDARY_UPTIME_CS" = "7500" ]
[ "$REFRESH_PLANNED_START_UPTIME_CS" = "7460" ]

# Test DISPLAY_SETTLE_DEADLINE_CS wait before RTC suspend and >= 5s minimum alarm
RTC_PATH="$RUNTIME_DIR/wakeup_enable"
POWER_STATE_PATH="$RUNTIME_DIR/power_state"
RTC_PMIC_EPOCH_PATH="$RUNTIME_DIR/pmic_epoch"
LOG_FILE="$RUNTIME_DIR/test.log"
echo "0" > "$RTC_PATH"
echo "1000" > "$RTC_PMIC_EPOCH_PATH"
: > "$POWER_STATE_PATH"
DISPLAY_SETTLE_DEADLINE_CS=7560
TEST_SLEEP_TARGET=""
date() { echo 3600; }
# Short alarm (3604 - 3600 = 4s < 5s) must be rejected after waiting for settle deadline
if try_rtc_suspend 3604; then exit 1; fi
[ "$TEST_SLEEP_TARGET" = "7560" ]
[ -z "$DISPLAY_SETTLE_DEADLINE_CS" ]

# Rejected suspend (kernel refuses `echo mem`): must return a plain failure
# status instead of aborting the shell, disarm the RTC alarm, and not count
# the interval as RTC sleep.
rm -f "$POWER_STATE_PATH"
mkdir -p "$POWER_STATE_PATH"
echo "0" > "$RTC_PATH"
ACCUMULATED_SLEPT_SECONDS=0
RTC_FAILURE_LOGGED=0
REJECT_STATUS=0
try_rtc_suspend 3700 2>/dev/null || REJECT_STATUS=$?
[ "$REJECT_STATUS" -ge 1 ] && [ "$REJECT_STATUS" -le 255 ]
[ "$(cat "$RTC_PATH")" = "0" ]
[ "$ACCUMULATED_SLEPT_SECONDS" = "0" ]
rmdir "$POWER_STATE_PATH"

# Test 6-hour convergence retention (slept=20745s, offset=-5879ms -> 283ppm <= 350ppm stays converged)
DRIFT_CONVERGED_STREAK=2
ACCUMULATED_SLEPT_SECONDS=20745
printf "OFFSET_MS=-5879\nELAPSED_SEC=21604\nDRIFT_PPM=272\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$DRIFT_CONVERGED_STREAK" = "3" ]

# Test 9-hour calibration acceptance (elapsed=32418s <= 86400s is calibrated rather than dropped)
ADAPTIVE_PPM_TRIM=0
ACCUMULATED_SLEPT_SECONDS=31000
printf "OFFSET_MS=18600\nELAPSED_SEC=32418\nDRIFT_PPM=-600\n" > "$SYNC_STAT_FILE"
update_adaptive_drift_trim
[ "$ADAPTIVE_PPM_TRIM" = "-300" ]

# Test should_keep_displayed_frame_after_sync prevents backward :00 -> :59 -> :00 double full refresh
CURRENT_FRAME_EPOCH=3600
SYNC_REASON=auto
should_keep_displayed_frame_after_sync 3609
should_keep_displayed_frame_after_sync 3581
should_keep_displayed_frame_after_sync 3555
if should_keep_displayed_frame_after_sync 3554; then exit 1; fi
if should_keep_displayed_frame_after_sync 3660; then exit 1; fi
SYNC_REASON=manual
if should_keep_displayed_frame_after_sync 3609; then exit 1; fi

rm -rf "$RUNTIME_DIR"

printf 'refresh timing tests passed\n'

