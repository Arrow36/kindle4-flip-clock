#!/bin/sh

BASE_DIR="/mnt/us/extensions/kfc"
SRC_DIR="$BASE_DIR/src"
SETTINGS_FILE="$BASE_DIR/settings.conf"
RUNTIME_DIR="/tmp/kfc"
LOG_DIR="$BASE_DIR/logs"
LOG_FILE="$LOG_DIR/kfc.log"
LAUNCHER_LOG="$LOG_DIR/launcher.log"
CURRENT_FRAME="$RUNTIME_DIR/current.png"
NEXT_FRAME="$RUNTIME_DIR/next.png"
NEXT_RENDER_WORK="$RUNTIME_DIR/next.rendering.png"
NEXT_FRAME_META="$RUNTIME_DIR/next.meta"
EXIT_FILE="$RUNTIME_DIR/EXIT"
KEY_EVENT_FILE="$RUNTIME_DIR/KEY_EVENT"
PID_FILE="$RUNTIME_DIR/kfc.pid"
KEY_PID_FILE="$RUNTIME_DIR/keywatch.pid"
NEXT_RENDER_PID_FILE="$RUNTIME_DIR/next_render.pid"
SYNC_PID_FILE="$RUNTIME_DIR/time_sync.pid"
SYNC_RESULT_FILE="$RUNTIME_DIR/time_sync.result"
SYNC_RESULT_TMP="$RUNTIME_DIR/time_sync.result.tmp"
RTC_PATH="/sys/devices/platform/mxc_rtc.0/wakeup_enable"
RTC_PMIC_EPOCH_PATH="/sys/devices/platform/mxc_rtc.0/rtc_pmic_epoch_time"
POWER_STATE_PATH="/sys/power/state"

ORIENTATION=landscape_right
HOUR_MODE=24
THEME=light
TIMEZONE=CST-8
TIME_SYNC_TIMEOUT=45
NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com"
IDLE_SUSPEND_SECONDS=180
RTC_WAKE_LEAD_SECONDS=3
PARTIAL_REFRESH_DURATION_MS=800
FULL_REFRESH_DURATION_MS=1400

HELP_VISIBLE=0
BATTERY_LEVEL=0
CURRENT_FRAME_EPOCH=0
CURRENT_FRAME_BATTERY=0
NEXT_FRAME_EPOCH=0
NEXT_FRAME_READY=0
NEXT_FRAME_RENDER_EPOCH=0
NEXT_FRAME_BATTERY=0
NEXT_DISPLAY_CLOCK=0
CLOCK_SOURCE=system
KEY_PID=""
NEXT_RENDER_PID=""
SYNC_PID=""
KEY_ACTION=""
WAIT_REASON=""
ORIGINAL_WIFI_STATE=""
LAST_INTERACTION_CLOCK=0
RTC_FAILURE_LOGGED=0
RTC_WOKE_EARLY=0
RTC_RESUME_LATENESS_SECONDS=0
CLEANED=0
UI_STOPPED=0

is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

log_message() {
  mkdir -p "$LOG_DIR"
  echo "[$(date)] $1" >> "$LOG_FILE"
}

. "$SRC_DIR/time_sync.sh"

load_settings() {
  [ -f "$SETTINGS_FILE" ] && . "$SETTINGS_FILE"

  case "$ORIENTATION" in portrait|portrait_down|landscape_right|landscape_left) ;; *) ORIENTATION=landscape_right ;; esac
  case "$HOUR_MODE" in 12|24) ;; *) HOUR_MODE=24 ;; esac
  case "$THEME" in light|dark) ;; *) THEME=light ;; esac
  is_uint "$TIME_SYNC_TIMEOUT" || TIME_SYNC_TIMEOUT=45
  is_uint "$IDLE_SUSPEND_SECONDS" || IDLE_SUSPEND_SECONDS=180
  is_uint "$RTC_WAKE_LEAD_SECONDS" || RTC_WAKE_LEAD_SECONDS=3
  is_uint "$PARTIAL_REFRESH_DURATION_MS" || PARTIAL_REFRESH_DURATION_MS=800
  is_uint "$FULL_REFRESH_DURATION_MS" || FULL_REFRESH_DURATION_MS=1400
  [ "$TIME_SYNC_TIMEOUT" -lt 10 ] && TIME_SYNC_TIMEOUT=10
  [ "$TIME_SYNC_TIMEOUT" -gt 180 ] && TIME_SYNC_TIMEOUT=180
  [ "$IDLE_SUSPEND_SECONDS" -lt 60 ] && IDLE_SUSPEND_SECONDS=60
  [ "$IDLE_SUSPEND_SECONDS" -gt 3600 ] && IDLE_SUSPEND_SECONDS=3600
  [ "$RTC_WAKE_LEAD_SECONDS" -lt 1 ] && RTC_WAKE_LEAD_SECONDS=1
  [ "$RTC_WAKE_LEAD_SECONDS" -gt 10 ] && RTC_WAKE_LEAD_SECONDS=10
  [ "$PARTIAL_REFRESH_DURATION_MS" -lt 100 ] && PARTIAL_REFRESH_DURATION_MS=100
  [ "$PARTIAL_REFRESH_DURATION_MS" -gt 5000 ] && PARTIAL_REFRESH_DURATION_MS=5000
  [ "$FULL_REFRESH_DURATION_MS" -lt 100 ] && FULL_REFRESH_DURATION_MS=100
  [ "$FULL_REFRESH_DURATION_MS" -gt 5000 ] && FULL_REFRESH_DURATION_MS=5000
  [ -z "$TIMEZONE" ] && TIMEZONE=CST-8
  case "$NTP_SERVERS" in
    ''|*[!A-Za-z0-9._\ -]*) NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com" ;;
  esac
  export TZ="$TIMEZONE"
}

save_settings() {
  {
    echo "ORIENTATION=$ORIENTATION"
    echo "HOUR_MODE=$HOUR_MODE"
    echo "THEME=$THEME"
    echo "TIMEZONE=$TIMEZONE"
    echo "TIME_SYNC_TIMEOUT=$TIME_SYNC_TIMEOUT"
    echo "NTP_SERVERS=\"$NTP_SERVERS\""
    echo "IDLE_SUSPEND_SECONDS=$IDLE_SUSPEND_SECONDS"
    echo "RTC_WAKE_LEAD_SECONDS=$RTC_WAKE_LEAD_SECONDS"
    echo "PARTIAL_REFRESH_DURATION_MS=$PARTIAL_REFRESH_DURATION_MS"
    echo "FULL_REFRESH_DURATION_MS=$FULL_REFRESH_DURATION_MS"
  } > "$SETTINGS_FILE.tmp"
  mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
}

next_render_in_progress() {
  [ -n "$NEXT_RENDER_PID" ] && kill -0 "$NEXT_RENDER_PID" 2>/dev/null
}

cancel_next_frame_render() {
  if [ -n "$NEXT_RENDER_PID" ]; then
    if kill -0 "$NEXT_RENDER_PID" 2>/dev/null; then
      kill "$NEXT_RENDER_PID" 2>/dev/null
    fi
    wait "$NEXT_RENDER_PID" 2>/dev/null
  fi
  NEXT_RENDER_PID=""
  NEXT_FRAME_READY=0
  rm -f "$NEXT_RENDER_PID_FILE" "$NEXT_RENDER_WORK" "$NEXT_FRAME" "$NEXT_FRAME_META"
}

cleanup() {
  [ "$CLEANED" = "1" ] && return
  CLEANED=1

  [ -n "$KEY_PID" ] && kill "$KEY_PID" 2>/dev/null
  cancel_next_frame_render
  if [ -n "$SYNC_PID" ]; then
    if kill -0 "$SYNC_PID" 2>/dev/null; then
      kill "$SYNC_PID" 2>/dev/null
    fi
    wait "$SYNC_PID" 2>/dev/null
  fi
  SYNC_PID=""

  # A killed synchronization worker may not have reached its own Wi-Fi
  # cleanup trap yet. Force Wi-Fi off before restoring the launch-time state.
  wifi_set_enabled 0
  case "$ORIGINAL_WIFI_STATE" in
    0|1) wifi_set_enabled "$ORIGINAL_WIFI_STATE" ;;
  esac

  if [ "$UI_STOPPED" = "1" ]; then
    /usr/bin/lipc-set-prop -- com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
    /etc/init.d/framework start >/dev/null 2>&1
  fi

  [ -w "$RTC_PATH" ] && echo -n 0 > "$RTC_PATH" 2>/dev/null

  rm -f "$EXIT_FILE" "$KEY_EVENT_FILE" "$KEY_EVENT_FILE.tmp" \
    "$PID_FILE" "$KEY_PID_FILE" "$NEXT_RENDER_PID_FILE" "$SYNC_PID_FILE" \
    "$SYNC_RESULT_FILE" "$SYNC_RESULT_TMP" "$CURRENT_FRAME" "$NEXT_FRAME" \
    "$NEXT_RENDER_WORK" "$NEXT_FRAME_META"
}

get_battery_level() {
  LEVEL=$(gasgauge-info -c 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
  case "$LEVEL" in ''|*[!0-9]*) LEVEL=0 ;; esac
  [ "$LEVEL" -gt 100 ] && LEVEL=100
  echo "$LEVEL"
}

minute_epoch() {
  EPOCH_VALUE="$1"
  echo $((EPOCH_VALUE / 60 * 60))
}

next_minute_epoch() {
  EPOCH_VALUE="$1"
  echo $(((EPOCH_VALUE / 60 + 1) * 60))
}

read_pmic_epoch() {
  [ -r "$RTC_PMIC_EPOCH_PATH" ] || return 1
  PMIC_HEX=$(cat "$RTC_PMIC_EPOCH_PATH" 2>/dev/null)
  case "$PMIC_HEX" in ''|*[!0-9A-Fa-f]*) return 1 ;; esac
  PMIC_EPOCH=$((0x$PMIC_HEX))
  [ "$PMIC_EPOCH" -gt 0 ] || return 1
  echo "$PMIC_EPOCH"
}

scheduler_now() {
  if [ "$CLOCK_SOURCE" = "pmic" ]; then
    read_pmic_epoch
  else
    date +%s
  fi
}

monotonic_stamp() {
  UPTIME_VALUE=$(cat /proc/uptime 2>/dev/null)
  echo "${UPTIME_VALUE%% *}"
}

sleep_ms() {
  DELAY_MS="$1"
  [ "$DELAY_MS" -gt 0 ] || return 0
  if command -v usleep >/dev/null 2>&1; then
    usleep $((DELAY_MS * 1000))
  else
    DELAY_SECONDS=$(((DELAY_MS + 999) / 1000))
    sleep "$DELAY_SECONDS"
  fi
}

refresh_duration_for_epoch() {
  REFRESH_EPOCH="$1"
  REFRESH_MINUTE=$(((REFRESH_EPOCH / 60) % 60))
  if [ "$REFRESH_MINUTE" -eq 0 ]; then
    echo "$FULL_REFRESH_DURATION_MS"
  else
    echo "$PARTIAL_REFRESH_DURATION_MS"
  fi
}

initialize_virtual_clock() {
  SYSTEM_NOW=$(date +%s)
  CURRENT_FRAME_EPOCH=$(minute_epoch "$SYSTEM_NOW")
  NEXT_FRAME_EPOCH=$((CURRENT_FRAME_EPOCH + 60))

  PMIC_NOW=$(read_pmic_epoch 2>/dev/null)
  if is_uint "$PMIC_NOW" && [ "$PMIC_NOW" -gt 0 ]; then
    CLOCK_SOURCE=pmic
    SCHEDULER_NOW="$PMIC_NOW"
  else
    CLOCK_SOURCE=system
    SCHEDULER_NOW="$SYSTEM_NOW"
  fi

  SECONDS_TO_NEXT=$((NEXT_FRAME_EPOCH - SYSTEM_NOW))
  [ "$SECONDS_TO_NEXT" -lt 1 ] && SECONDS_TO_NEXT=1
  NEXT_DISPLAY_CLOCK=$((SCHEDULER_NOW + SECONDS_TO_NEXT))
  log_message "virtual clock anchored: system=$SYSTEM_NOW current=$CURRENT_FRAME_EPOCH next=$NEXT_FRAME_EPOCH source=$CLOCK_SOURCE clock_now=$SCHEDULER_NOW display_clock=$NEXT_DISPLAY_CLOCK"
}

advance_virtual_clock() {
  CURRENT_FRAME_EPOCH="$NEXT_FRAME_EPOCH"
  NEXT_FRAME_EPOCH=$((NEXT_FRAME_EPOCH + 60))
  NEXT_DISPLAY_CLOCK=$((NEXT_DISPLAY_CLOCK + 60))
}

render_frame() {
  TARGET_EPOCH="$1"
  OUTPUT_PATH="$2"
  rm -f "$OUTPUT_PATH"
  log_message "rendering epoch $TARGET_EPOCH to $OUTPUT_PATH"
  (
    cd /mnt/us/koreader || exit 1
    ./luajit "$SRC_DIR/render.lua" "$OUTPUT_PATH" \
      "$ORIENTATION" "$THEME" "$TARGET_EPOCH" "$BATTERY_LEVEL" \
      "$HELP_VISIBLE" "$HOUR_MODE"
  ) >> "$LOG_FILE" 2>&1
  RENDER_STATUS=$?
  if [ "$RENDER_STATUS" -ne 0 ]; then
    log_message "KOReader renderer failed with status $RENDER_STATUS"
    return 1
  fi
  if [ ! -s "$OUTPUT_PATH" ]; then
    log_message "KOReader renderer produced an empty PNG"
    return 1
  fi
  return 0
}

render_current_frame() {
  BATTERY_LEVEL=$(get_battery_level)
  CURRENT_FRAME_BATTERY="$BATTERY_LEVEL"
  log_message "current-frame sample: target=$CURRENT_FRAME_EPOCH battery=$CURRENT_FRAME_BATTERY"
  render_frame "$CURRENT_FRAME_EPOCH" "$CURRENT_FRAME"
}

full_refresh() {
  FRAME_PATH="$1"
  log_message "full refresh: $FRAME_PATH"
  # Match the upstream refresh that is visibly effective on Kindle 4: clear
  # the framebuffer first, then draw the complete PNG.
  eips -c >> "$LOG_FILE" 2>&1
  eips -g "$FRAME_PATH" >> "$LOG_FILE" 2>&1
}

display_frame() {
  FRAME_PATH="$1"
  FORCE_FULL="$2"
  DISPLAY_EPOCH="$3"
  DISPLAY_BATTERY="$4"
  DISPLAY_MINUTE=$(((DISPLAY_EPOCH / 60) % 60))
  DISPLAY_START_CLOCK=$(scheduler_now 2>/dev/null)
  DISPLAY_START_UPTIME=$(monotonic_stamp)
  log_message "display start: target=$DISPLAY_EPOCH battery=$DISPLAY_BATTERY source=$CLOCK_SOURCE clock=${DISPLAY_START_CLOCK:-unknown} uptime=${DISPLAY_START_UPTIME:-unknown}"
  if [ "$FORCE_FULL" = "1" ] || [ "$DISPLAY_MINUTE" -eq 0 ]; then
    full_refresh "$FRAME_PATH"
  else
    eips -g "$FRAME_PATH" >> "$LOG_FILE" 2>&1
  fi
  DISPLAY_END_CLOCK=$(scheduler_now 2>/dev/null)
  DISPLAY_END_UPTIME=$(monotonic_stamp)
  log_message "display end: target=$DISPLAY_EPOCH clock=${DISPLAY_END_CLOCK:-unknown} uptime=${DISPLAY_END_UPTIME:-unknown}"
}

start_next_frame_render() {
  [ -n "$SYNC_PID" ] && return 1
  next_render_in_progress && return 1

  BATTERY_LEVEL=$(get_battery_level)
  NEXT_FRAME_RENDER_EPOCH="$NEXT_FRAME_EPOCH"
  NEXT_FRAME_BATTERY="$BATTERY_LEVEL"
  NEXT_FRAME_READY=0
  rm -f "$NEXT_FRAME" "$NEXT_RENDER_WORK" "$NEXT_RENDER_PID_FILE" "$NEXT_FRAME_META"
  log_message "pre-rendering next minute: target=$NEXT_FRAME_RENDER_EPOCH battery=$NEXT_FRAME_BATTERY"
  (
    cd /mnt/us/koreader || exit 1
    exec ./luajit "$SRC_DIR/render.lua" "$NEXT_RENDER_WORK" \
      "$ORIENTATION" "$THEME" "$NEXT_FRAME_RENDER_EPOCH" "$NEXT_FRAME_BATTERY" \
      "$HELP_VISIBLE" "$HOUR_MODE"
  ) >> "$LOG_FILE" 2>&1 &
  NEXT_RENDER_PID=$!
  echo "$NEXT_RENDER_PID" > "$NEXT_RENDER_PID_FILE"
  return 0
}

next_render_finished() {
  [ -n "$NEXT_RENDER_PID" ] && ! kill -0 "$NEXT_RENDER_PID" 2>/dev/null
}

finish_next_frame_render() {
  [ -n "$NEXT_RENDER_PID" ] || return 1
  wait "$NEXT_RENDER_PID" 2>/dev/null
  RENDER_STATUS=$?
  NEXT_RENDER_PID=""
  rm -f "$NEXT_RENDER_PID_FILE"

  if [ "$RENDER_STATUS" -eq 0 ] && [ -s "$NEXT_RENDER_WORK" ]; then
    mv "$NEXT_RENDER_WORK" "$NEXT_FRAME"
    echo "$NEXT_FRAME_RENDER_EPOCH $NEXT_FRAME_BATTERY" > "$NEXT_FRAME_META"
    NEXT_FRAME_READY=1
    log_message "next-minute frame ready: target=$NEXT_FRAME_RENDER_EPOCH battery=$NEXT_FRAME_BATTERY"
    return 0
  fi

  rm -f "$NEXT_RENDER_WORK"
  NEXT_FRAME_READY=0
  log_message "next-minute renderer failed with status $RENDER_STATUS"
  return 1
}

prepare_next_minute() {
  NEXT_FRAME_READY=0
  rm -f "$NEXT_FRAME" "$NEXT_FRAME_META"
  [ -n "$SYNC_PID" ] || start_next_frame_render
}

publish_key_event() {
  echo "$1" > "$KEY_EVENT_FILE.tmp"
  mv "$KEY_EVENT_FILE.tmp" "$KEY_EVENT_FILE"
}

watch_keys() {
  while [ ! -f "$EXIT_FILE" ]; do
    KEY=$(waitforkey)
    case "$KEY" in
      "193 1") publish_key_event orientation_prev ;;
      "104 1") publish_key_event orientation_next ;;
      "109 1") publish_key_event theme_toggle ;;
      "194 1") publish_key_event hour_toggle ;;
      "29 1") publish_key_event time_sync ;;
      "139 1") publish_key_event help_toggle ;;
      "158 1") publish_key_event force_refresh ;;
      "102 1") touch "$EXIT_FILE" ;;
      *" 1") publish_key_event activity ;;
    esac
  done
}

pause_briefly() {
  if command -v usleep >/dev/null 2>&1; then
    usleep 100000
  else
    sleep 0.1 2>/dev/null || sleep 1
  fi
}

try_rtc_suspend() {
  EXPECTED_WAKE_PMIC="$1"
  [ "$CLOCK_SOURCE" = "pmic" ] || return 1
  is_uint "$EXPECTED_WAKE_PMIC" || return 1
  [ "$EXPECTED_WAKE_PMIC" -gt 0 ] || return 1
  [ -r "$RTC_PATH" ] && [ -w "$RTC_PATH" ] && [ -w "$POWER_STATE_PATH" ] && \
    [ -r "$RTC_PMIC_EPOCH_PATH" ] || return 1

  SUSPEND_START_PMIC=$(read_pmic_epoch) || return 1
  SUSPEND_SECONDS=$((EXPECTED_WAKE_PMIC - SUSPEND_START_PMIC))
  [ "$SUSPEND_SECONDS" -gt 0 ] || return 1

  RTC_STATE=$(cat "$RTC_PATH" 2>/dev/null)
  [ "$RTC_STATE" = "0" ] || return 1
  echo -n "$SUSPEND_SECONDS" > "$RTC_PATH" 2>/dev/null || return 1
  RTC_WOKE_EARLY=0
  RTC_RESUME_LATENESS_SECONDS=0
  log_message "RTC suspend: planned_wake_pmic=$EXPECTED_WAKE_PMIC current_pmic=$SUSPEND_START_PMIC delay=$SUSPEND_SECONDS display_clock=$NEXT_DISPLAY_CLOCK"
  echo mem > "$POWER_STATE_PATH" 2>> "$LOG_FILE"
  SUSPEND_STATUS=$?
  RESUME_PMIC=$(read_pmic_epoch 2>/dev/null)
  RESUME_SYSTEM=$(date +%s)
  if is_uint "$RESUME_PMIC" && [ "$RESUME_PMIC" -gt 0 ]; then
    RTC_RESUME_LATENESS_SECONDS=$((RESUME_PMIC - EXPECTED_WAKE_PMIC))
    # A value at least two seconds before the alarm indicates a different
    # hardware source, normally the power button. One second is tolerated for
    # the PMIC RTC's integer-second sampling boundary.
    if [ $((RESUME_PMIC + 1)) -lt "$EXPECTED_WAKE_PMIC" ]; then
      RTC_WOKE_EARLY=1
    fi
    log_message "RTC resume: planned_wake_pmic=$EXPECTED_WAKE_PMIC actual_pmic=$RESUME_PMIC lateness=$RTC_RESUME_LATENESS_SECONDS system=$RESUME_SYSTEM early=$RTC_WOKE_EARLY status=$SUSPEND_STATUS"
  else
    log_message "RTC resume: planned_wake_pmic=$EXPECTED_WAKE_PMIC actual_pmic=unknown system=$RESUME_SYSTEM early=unknown status=$SUSPEND_STATUS"
  fi
  return "$SUSPEND_STATUS"
}

sync_finished() {
  [ -f "$SYNC_RESULT_FILE" ] && return 0
  [ -n "$SYNC_PID" ] && ! kill -0 "$SYNC_PID" 2>/dev/null
}

wait_for_event_or_minute() {
  WAIT_REASON=""
  KEY_ACTION=""

  while [ ! -f "$EXIT_FILE" ]; do
    if [ -f "$KEY_EVENT_FILE" ]; then
      KEY_ACTION=$(cat "$KEY_EVENT_FILE" 2>/dev/null)
      rm -f "$KEY_EVENT_FILE"
      WAIT_REASON="key"
      return
    fi

    if sync_finished; then
      WAIT_REASON="sync"
      return
    fi

    if next_render_finished; then
      WAIT_REASON="render"
      return
    fi

    NOW_CLOCK=$(scheduler_now 2>/dev/null)
    if ! is_uint "$NOW_CLOCK" || [ "$NOW_CLOCK" -le 0 ]; then
      if [ "$CLOCK_SOURCE" = "pmic" ]; then
        CLOCK_SOURCE=system
        NEXT_DISPLAY_CLOCK="$NEXT_FRAME_EPOCH"
        log_message "PMIC clock read failed; falling back to awake system-clock scheduling"
      fi
      NOW_CLOCK=$(date +%s)
    fi

    CLOCK_LATENESS=$((NOW_CLOCK - NEXT_DISPLAY_CLOCK))
    if [ "$CLOCK_LATENESS" -ge 60 ]; then
      MISSED_MINUTES=$((CLOCK_LATENESS / 60))
      cancel_next_frame_render
      NEXT_FRAME_EPOCH=$((NEXT_FRAME_EPOCH + MISSED_MINUTES * 60))
      NEXT_DISPLAY_CLOCK=$((NEXT_DISPLAY_CLOCK + MISSED_MINUTES * 60))
      log_message "virtual clock catch-up: skipped=$MISSED_MINUTES next_target=$NEXT_FRAME_EPOCH next_display_clock=$NEXT_DISPLAY_CLOCK"
      continue
    fi

    REFRESH_DURATION_MS=$(refresh_duration_for_epoch "$NEXT_FRAME_EPOCH")
    REFRESH_HALF_MS=$((REFRESH_DURATION_MS / 2))
    REFRESH_EARLY_SECONDS=$(((REFRESH_HALF_MS + 999) / 1000))
    [ "$REFRESH_EARLY_SECONDS" -lt 1 ] && REFRESH_EARLY_SECONDS=1
    REFRESH_START_CLOCK=$((NEXT_DISPLAY_CLOCK - REFRESH_EARLY_SECONDS))
    REFRESH_DELAY_MS=$((REFRESH_EARLY_SECONDS * 1000 - REFRESH_HALF_MS))

    if [ "$NOW_CLOCK" -ge "$REFRESH_START_CLOCK" ]; then
      if [ "$NOW_CLOCK" -eq "$REFRESH_START_CLOCK" ]; then
        sleep_ms "$REFRESH_DELAY_MS"
      fi
      REFRESH_ACTUAL_CLOCK=$(scheduler_now 2>/dev/null)
      log_message "refresh release: target=$NEXT_FRAME_EPOCH display_clock=$NEXT_DISPLAY_CLOCK duration_ms=$REFRESH_DURATION_MS start_clock=$REFRESH_START_CLOCK delay_ms=$REFRESH_DELAY_MS actual_clock=${REFRESH_ACTUAL_CLOCK:-unknown} uptime=$(monotonic_stamp)"
      WAIT_REASON="minute"
      return
    fi

    IDLE_DEADLINE=$((LAST_INTERACTION_CLOCK + IDLE_SUSPEND_SECONDS))
    WAKE_CLOCK=$((NEXT_DISPLAY_CLOCK - RTC_WAKE_LEAD_SECONDS))
    if [ -z "$SYNC_PID" ] && ! next_render_in_progress && \
       [ "$CLOCK_SOURCE" = "pmic" ] && [ "$NOW_CLOCK" -ge "$IDLE_DEADLINE" ] && \
       [ "$NOW_CLOCK" -lt "$WAKE_CLOCK" ]; then
      if try_rtc_suspend "$WAKE_CLOCK"; then
        RTC_FAILURE_LOGGED=0
        if [ "$RTC_WOKE_EARLY" = "1" ]; then
          LAST_INTERACTION_CLOCK="$RESUME_PMIC"
          log_message "early hardware wake; awake interval restarted for ${IDLE_SUSPEND_SECONDS}s"
        fi
        # Give waitforkey time to publish a physical key that caused wake-up.
        pause_briefly
        continue
      fi
      if [ "$RTC_FAILURE_LOGGED" = "0" ]; then
        log_message "RTC suspend unavailable; continuing awake"
        RTC_FAILURE_LOGGED=1
      fi
      sleep 1
      continue
    fi

    pause_briefly
  done
  WAIT_REASON="exit"
}

handle_key_action() {
  SETTINGS_CHANGED=0
  case "$1" in
    orientation_prev)
      case "$ORIENTATION" in
        portrait) ORIENTATION=landscape_left ;;
        landscape_right) ORIENTATION=portrait ;;
        portrait_down) ORIENTATION=landscape_right ;;
        *) ORIENTATION=portrait_down ;;
      esac
      SETTINGS_CHANGED=1
      ;;
    orientation_next)
      case "$ORIENTATION" in
        portrait) ORIENTATION=landscape_right ;;
        landscape_right) ORIENTATION=portrait_down ;;
        portrait_down) ORIENTATION=landscape_left ;;
        *) ORIENTATION=portrait ;;
      esac
      SETTINGS_CHANGED=1
      ;;
    theme_toggle)
      [ "$THEME" = "light" ] && THEME=dark || THEME=light
      SETTINGS_CHANGED=1
      ;;
    hour_toggle)
      [ "$HOUR_MODE" = "24" ] && HOUR_MODE=12 || HOUR_MODE=24
      SETTINGS_CHANGED=1
      ;;
    help_toggle)
      [ "$HELP_VISIBLE" = "1" ] && HELP_VISIBLE=0 || HELP_VISIBLE=1
      ;;
    time_sync) return 2 ;;
    force_refresh) return 3 ;;
    activity) return 4 ;;
    *) return 1 ;;
  esac
  [ "$SETTINGS_CHANGED" = "1" ] && save_settings
  return 0
}

start_time_sync() {
  [ -n "$SYNC_PID" ] && return 1
  rm -f "$SYNC_RESULT_FILE" "$SYNC_RESULT_TMP" "$SYNC_PID_FILE"
  log_message "manual time synchronization requested"
  (
    trap 'wifi_set_enabled 0; exit 143' 1 2 15
    if time_sync_now; then
      echo success > "$SYNC_RESULT_TMP"
    else
      echo failure > "$SYNC_RESULT_TMP"
    fi
    mv "$SYNC_RESULT_TMP" "$SYNC_RESULT_FILE"
  ) &
  SYNC_PID=$!
  echo "$SYNC_PID" > "$SYNC_PID_FILE"
  return 0
}

finish_time_sync() {
  SYNC_STATUS=failure
  [ -f "$SYNC_RESULT_FILE" ] && SYNC_STATUS=$(cat "$SYNC_RESULT_FILE" 2>/dev/null)
  [ -n "$SYNC_PID" ] && wait "$SYNC_PID" 2>/dev/null
  SYNC_PID=""
  rm -f "$SYNC_PID_FILE" "$SYNC_RESULT_FILE" "$SYNC_RESULT_TMP"
  wifi_set_enabled 0
  [ "$SYNC_STATUS" = "success" ]
}

publish_minute_frame() {
  if next_render_finished; then
    finish_next_frame_render
  fi

  META_EPOCH=""
  META_BATTERY=""
  [ -f "$NEXT_FRAME_META" ] && read META_EPOCH META_BATTERY < "$NEXT_FRAME_META"
  if [ "$NEXT_FRAME_READY" = "1" ] && [ "$META_EPOCH" = "$NEXT_FRAME_EPOCH" ] && \
     is_uint "$META_BATTERY"; then
    display_frame "$NEXT_FRAME" 0 "$META_EPOCH" "$META_BATTERY"
    mv "$NEXT_FRAME" "$CURRENT_FRAME"
    rm -f "$NEXT_FRAME_META"
    CURRENT_FRAME_BATTERY="$META_BATTERY"
    NEXT_FRAME_READY=0
    return 0
  fi

  log_message "next-minute frame rejected: expected_target=$NEXT_FRAME_EPOCH ready=$NEXT_FRAME_READY meta_target=${META_EPOCH:-missing} meta_battery=${META_BATTERY:-missing}"
  cancel_next_frame_render
  BATTERY_LEVEL=$(get_battery_level)
  CURRENT_FRAME_BATTERY="$BATTERY_LEVEL"
  log_message "next-minute frame missing or stale; rendering target=$NEXT_FRAME_EPOCH battery=$CURRENT_FRAME_BATTERY"
  if render_frame "$NEXT_FRAME_EPOCH" "$CURRENT_FRAME"; then
    display_frame "$CURRENT_FRAME" 0 "$NEXT_FRAME_EPOCH" "$CURRENT_FRAME_BATTERY"
    return 0
  fi
  return 1
}

main() {
  mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
  rm -f "$EXIT_FILE" "$KEY_EVENT_FILE" "$KEY_EVENT_FILE.tmp" \
    "$CURRENT_FRAME" "$NEXT_FRAME" "$NEXT_RENDER_WORK" "$NEXT_FRAME_META" \
    "$KEY_PID_FILE" "$NEXT_RENDER_PID_FILE" "$SYNC_PID_FILE" \
    "$SYNC_RESULT_FILE" "$SYNC_RESULT_TMP"
  : > "$LOG_FILE"
  load_settings

  ORIGINAL_WIFI_STATE=$(wifi_get_enabled)
  case "$ORIGINAL_WIFI_STATE" in 0|1) ;; *) ORIGINAL_WIFI_STATE="" ;; esac
  log_message "startup: original Wi-Fi state=${ORIGINAL_WIFI_STATE:-unknown}"
  wifi_set_enabled 0
  initialize_virtual_clock

  # Validate the first frame before hiding the Kindle UI.
  if ! render_current_frame; then
    return 1
  fi

  /etc/init.d/framework stop >/dev/null 2>&1
  UI_STOPPED=1
  /usr/bin/lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1
  watch_keys &
  KEY_PID=$!
  echo "$KEY_PID" > "$KEY_PID_FILE"

  display_frame "$CURRENT_FRAME" 1 "$CURRENT_FRAME_EPOCH" "$CURRENT_FRAME_BATTERY"
  LAST_INTERACTION_CLOCK=$(scheduler_now 2>/dev/null)
  if ! is_uint "$LAST_INTERACTION_CLOCK"; then
    CLOCK_SOURCE=system
    LAST_INTERACTION_CLOCK=$(date +%s)
    NEXT_DISPLAY_CLOCK="$NEXT_FRAME_EPOCH"
  fi
  prepare_next_minute

  while [ ! -f "$EXIT_FILE" ]; do
    wait_for_event_or_minute "$NEXT_FRAME_EPOCH"
    [ -f "$EXIT_FILE" ] && break

    case "$WAIT_REASON" in
      key)
        log_message "key event: $KEY_ACTION"
        LAST_INTERACTION_CLOCK=$(scheduler_now 2>/dev/null)
        is_uint "$LAST_INTERACTION_CLOCK" || LAST_INTERACTION_CLOCK=$(date +%s)
        handle_key_action "$KEY_ACTION"
        KEY_STATUS=$?
        if [ "$KEY_STATUS" -eq 2 ]; then
          cancel_next_frame_render
          start_time_sync
        elif [ "$KEY_STATUS" -eq 3 ]; then
          [ -s "$CURRENT_FRAME" ] && display_frame "$CURRENT_FRAME" 1 "$CURRENT_FRAME_EPOCH" "$CURRENT_FRAME_BATTERY"
        elif [ "$KEY_STATUS" -eq 0 ]; then
          cancel_next_frame_render
          if render_current_frame; then
            display_frame "$CURRENT_FRAME" 0 "$CURRENT_FRAME_EPOCH" "$CURRENT_FRAME_BATTERY"
          fi
          prepare_next_minute
        fi
        ;;
      render)
        finish_next_frame_render
        ;;
      sync)
        if finish_time_sync; then
          log_message "time synchronization succeeded"
          cancel_next_frame_render
          initialize_virtual_clock
          if render_current_frame; then
            display_frame "$CURRENT_FRAME" 1 "$CURRENT_FRAME_EPOCH" "$CURRENT_FRAME_BATTERY"
          fi
          LAST_INTERACTION_CLOCK=$(scheduler_now 2>/dev/null)
          is_uint "$LAST_INTERACTION_CLOCK" || LAST_INTERACTION_CLOCK=$(date +%s)
        else
          log_message "time synchronization failed"
        fi
        prepare_next_minute
        ;;
      minute)
        publish_minute_frame
        advance_virtual_clock
        prepare_next_minute
        ;;
    esac
  done
}

if [ "$1" != "--run" ]; then
  mkdir -p "$LOG_DIR"
  "$0" --run >> "$LAUNCHER_LOG" 2>&1 &
  exit 0
fi

mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    exit 0
  fi
fi

echo $$ > "$PID_FILE"
trap cleanup 0 1 2 15
main
