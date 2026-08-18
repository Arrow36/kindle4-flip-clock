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
EXIT_FILE="$RUNTIME_DIR/EXIT"
KEY_EVENT_FILE="$RUNTIME_DIR/KEY_EVENT"
PID_FILE="$RUNTIME_DIR/kfc.pid"
KEY_PID_FILE="$RUNTIME_DIR/keywatch.pid"
NEXT_RENDER_PID_FILE="$RUNTIME_DIR/next_render.pid"
SYNC_PID_FILE="$RUNTIME_DIR/time_sync.pid"
SYNC_RESULT_FILE="$RUNTIME_DIR/time_sync.result"
SYNC_RESULT_TMP="$RUNTIME_DIR/time_sync.result.tmp"
RTC_PATH="/sys/devices/platform/mxc_rtc.0/wakeup_enable"
POWER_STATE_PATH="/sys/power/state"

ORIENTATION=landscape_right
HOUR_MODE=24
THEME=light
TIMEZONE=CST-8
TIME_SYNC_TIMEOUT=45
NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com"
IDLE_SUSPEND_SECONDS=600
RTC_WAKE_LEAD_SECONDS=3

HELP_VISIBLE=0
BATTERY_LEVEL=0
NEXT_FRAME_EPOCH=0
NEXT_FRAME_READY=0
KEY_PID=""
NEXT_RENDER_PID=""
SYNC_PID=""
KEY_ACTION=""
WAIT_REASON=""
ORIGINAL_WIFI_STATE=""
LAST_INTERACTION_EPOCH=0
RTC_FAILURE_LOGGED=0
RTC_WOKE_EARLY=0
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
  is_uint "$IDLE_SUSPEND_SECONDS" || IDLE_SUSPEND_SECONDS=600
  is_uint "$RTC_WAKE_LEAD_SECONDS" || RTC_WAKE_LEAD_SECONDS=3
  [ "$TIME_SYNC_TIMEOUT" -lt 10 ] && TIME_SYNC_TIMEOUT=10
  [ "$TIME_SYNC_TIMEOUT" -gt 180 ] && TIME_SYNC_TIMEOUT=180
  [ "$IDLE_SUSPEND_SECONDS" -lt 60 ] && IDLE_SUSPEND_SECONDS=60
  [ "$IDLE_SUSPEND_SECONDS" -gt 3600 ] && IDLE_SUSPEND_SECONDS=3600
  [ "$RTC_WAKE_LEAD_SECONDS" -lt 1 ] && RTC_WAKE_LEAD_SECONDS=1
  [ "$RTC_WAKE_LEAD_SECONDS" -gt 10 ] && RTC_WAKE_LEAD_SECONDS=10
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
  rm -f "$NEXT_RENDER_PID_FILE" "$NEXT_RENDER_WORK" "$NEXT_FRAME"
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
    "$NEXT_RENDER_WORK"
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
  NOW_EPOCH=$(date +%s)
  CURRENT_EPOCH=$(minute_epoch "$NOW_EPOCH")
  BATTERY_LEVEL=$(get_battery_level)
  render_frame "$CURRENT_EPOCH" "$CURRENT_FRAME"
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
  DISPLAY_MINUTE=$(date +%M)
  if [ "$FORCE_FULL" = "1" ] || [ "$DISPLAY_MINUTE" = "00" ]; then
    full_refresh "$FRAME_PATH"
  else
    eips -g "$FRAME_PATH" >> "$LOG_FILE" 2>&1
  fi
}

start_next_frame_render() {
  [ -n "$SYNC_PID" ] && return 1
  next_render_in_progress && return 1

  BATTERY_LEVEL=$(get_battery_level)
  NEXT_FRAME_READY=0
  rm -f "$NEXT_FRAME" "$NEXT_RENDER_WORK" "$NEXT_RENDER_PID_FILE"
  log_message "pre-rendering next minute epoch $NEXT_FRAME_EPOCH"
  (
    cd /mnt/us/koreader || exit 1
    exec ./luajit "$SRC_DIR/render.lua" "$NEXT_RENDER_WORK" \
      "$ORIENTATION" "$THEME" "$NEXT_FRAME_EPOCH" "$BATTERY_LEVEL" \
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
    NEXT_FRAME_READY=1
    log_message "next-minute frame ready for epoch $NEXT_FRAME_EPOCH"
    return 0
  fi

  rm -f "$NEXT_RENDER_WORK"
  NEXT_FRAME_READY=0
  log_message "next-minute renderer failed with status $RENDER_STATUS"
  return 1
}

prepare_next_minute() {
  NOW_EPOCH=$(date +%s)
  NEXT_FRAME_EPOCH=$(next_minute_epoch "$NOW_EPOCH")
  NEXT_FRAME_READY=0
  rm -f "$NEXT_FRAME"
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
  SUSPEND_SECONDS="$1"
  [ "$SUSPEND_SECONDS" -gt 0 ] || return 1
  [ -r "$RTC_PATH" ] && [ -w "$RTC_PATH" ] && [ -w "$POWER_STATE_PATH" ] || return 1

  RTC_STATE=$(cat "$RTC_PATH" 2>/dev/null)
  [ "$RTC_STATE" = "0" ] || return 1
  echo -n "$SUSPEND_SECONDS" > "$RTC_PATH" 2>/dev/null || return 1
  SUSPEND_START_EPOCH=$(date +%s)
  EXPECTED_RESUME_EPOCH=$((SUSPEND_START_EPOCH + SUSPEND_SECONDS))
  RTC_WOKE_EARLY=0
  log_message "RTC suspend for ${SUSPEND_SECONDS}s"
  echo mem > "$POWER_STATE_PATH" 2>> "$LOG_FILE"
  SUSPEND_STATUS=$?
  RESUME_EPOCH=$(date +%s)
  # Normal RTC resume may be rounded by about one second. A larger lead means
  # another hardware source—normally the power button—woke the Kindle.
  if [ $((RESUME_EPOCH + 1)) -lt "$EXPECTED_RESUME_EPOCH" ]; then
    RTC_WOKE_EARLY=1
  fi
  # A physical key may wake the Kindle before the RTC alarm. Clear the old
  # relative alarm so the next loop can schedule a fresh minute wake-up.
  echo -n 0 > "$RTC_PATH" 2>/dev/null
  return "$SUSPEND_STATUS"
}

sync_finished() {
  [ -f "$SYNC_RESULT_FILE" ] && return 0
  [ -n "$SYNC_PID" ] && ! kill -0 "$SYNC_PID" 2>/dev/null
}

wait_for_event_or_minute() {
  TARGET_EPOCH="$1"
  WAKE_EPOCH=$((TARGET_EPOCH - RTC_WAKE_LEAD_SECONDS))
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

    NOW_EPOCH=$(date +%s)
    if [ "$NOW_EPOCH" -ge "$TARGET_EPOCH" ]; then
      WAIT_REASON="minute"
      return
    fi

    IDLE_DEADLINE=$((LAST_INTERACTION_EPOCH + IDLE_SUSPEND_SECONDS))
    if [ -z "$SYNC_PID" ] && ! next_render_in_progress && \
       [ "$NOW_EPOCH" -ge "$IDLE_DEADLINE" ] && [ "$NOW_EPOCH" -lt "$WAKE_EPOCH" ]; then
      SUSPEND_SECONDS=$((WAKE_EPOCH - NOW_EPOCH))
      if try_rtc_suspend "$SUSPEND_SECONDS"; then
        RTC_FAILURE_LOGGED=0
        if [ "$RTC_WOKE_EARLY" = "1" ]; then
          LAST_INTERACTION_EPOCH="$RESUME_EPOCH"
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

  NOW_EPOCH=$(date +%s)
  ACTUAL_MINUTE_EPOCH=$(minute_epoch "$NOW_EPOCH")
  if [ "$NEXT_FRAME_READY" = "1" ] && [ "$ACTUAL_MINUTE_EPOCH" -eq "$NEXT_FRAME_EPOCH" ]; then
    display_frame "$NEXT_FRAME" 0
    mv "$NEXT_FRAME" "$CURRENT_FRAME"
    NEXT_FRAME_READY=0
    return 0
  fi

  cancel_next_frame_render
  log_message "next-minute frame missing or stale; rendering current time"
  if render_current_frame; then
    display_frame "$CURRENT_FRAME" 0
    return 0
  fi
  return 1
}

main() {
  mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
  rm -f "$EXIT_FILE" "$KEY_EVENT_FILE" "$KEY_EVENT_FILE.tmp" \
    "$CURRENT_FRAME" "$NEXT_FRAME" "$NEXT_RENDER_WORK" \
    "$KEY_PID_FILE" "$NEXT_RENDER_PID_FILE" "$SYNC_PID_FILE" \
    "$SYNC_RESULT_FILE" "$SYNC_RESULT_TMP"
  : > "$LOG_FILE"
  load_settings

  ORIGINAL_WIFI_STATE=$(wifi_get_enabled)
  case "$ORIGINAL_WIFI_STATE" in 0|1) ;; *) ORIGINAL_WIFI_STATE="" ;; esac
  log_message "startup: original Wi-Fi state=${ORIGINAL_WIFI_STATE:-unknown}"
  wifi_set_enabled 0

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

  display_frame "$CURRENT_FRAME" 1
  LAST_INTERACTION_EPOCH=$(date +%s)
  prepare_next_minute

  while [ ! -f "$EXIT_FILE" ]; do
    wait_for_event_or_minute "$NEXT_FRAME_EPOCH"
    [ -f "$EXIT_FILE" ] && break

    case "$WAIT_REASON" in
      key)
        log_message "key event: $KEY_ACTION"
        LAST_INTERACTION_EPOCH=$(date +%s)
        handle_key_action "$KEY_ACTION"
        KEY_STATUS=$?
        if [ "$KEY_STATUS" -eq 2 ]; then
          cancel_next_frame_render
          start_time_sync
        elif [ "$KEY_STATUS" -eq 3 ]; then
          [ -s "$CURRENT_FRAME" ] && display_frame "$CURRENT_FRAME" 1
        elif [ "$KEY_STATUS" -eq 0 ]; then
          cancel_next_frame_render
          if render_current_frame; then
            display_frame "$CURRENT_FRAME" 0
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
          if render_current_frame; then
            display_frame "$CURRENT_FRAME" 1
          fi
        else
          log_message "time synchronization failed"
        fi
        prepare_next_minute
        ;;
      minute)
        publish_minute_frame
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
