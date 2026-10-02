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
NEXT_RENDER_RESULT="$RUNTIME_DIR/next.rendering.meta"
NEXT_FRAME_META="$RUNTIME_DIR/next.meta"
EXIT_FILE="$RUNTIME_DIR/EXIT"
KEY_EVENT_FILE="$RUNTIME_DIR/KEY_EVENT"
PID_FILE="$RUNTIME_DIR/kfc.pid"
KEY_PID_FILE="$RUNTIME_DIR/keywatch.pid"
NEXT_RENDER_PID_FILE="$RUNTIME_DIR/next_render.pid"
SYNC_PID_FILE="$RUNTIME_DIR/time_sync.pid"
SYNC_RESULT_FILE="$RUNTIME_DIR/time_sync.result"
SYNC_RESULT_TMP="$RUNTIME_DIR/time_sync.result.tmp"
AUTO_SYNC_RESULT_FILE="$RUNTIME_DIR/auto_sync.result"
AUTO_SYNC_RESULT_TMP="$RUNTIME_DIR/auto_sync.result.tmp"
RENDER_REQUEST_FIFO="$RUNTIME_DIR/render.request"
RENDER_SERVER_PID_FILE="$RUNTIME_DIR/render_server.pid"
PARTIAL_DISABLED_FILE="$RUNTIME_DIR/partial.disabled"
RTC_PATH="/sys/devices/platform/mxc_rtc.0/wakeup_enable"
RTC_PMIC_EPOCH_PATH="/sys/devices/platform/mxc_rtc.0/rtc_pmic_epoch_time"
POWER_STATE_PATH="/sys/power/state"
ORIENTATION=landscape_right
HOUR_MODE=24
THEME=light
TIMEZONE=CST-8
TIME_SYNC_TIMEOUT=45
NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com"
AUTO_TIME_SYNC_INTERVAL_HOURS=0
AUTO_TIME_CHECK_HOURLY=0
AUTO_DRIFT_CALIBRATION=1
RTC_DRIFT_COMPENSATION_PPM=5400
ADAPTIVE_PPM_TRIM=0
IDLE_SUSPEND_SECONDS=15
RTC_WAKE_LEAD_SECONDS=3
PARTIAL_REFRESH_DURATION_MS=800
FULL_REFRESH_DURATION_MS=1400
BATTERY_REFRESH_SETTLE_SECONDS=25
LAST_AUTO_SYNC_EPOCH=0
LAST_SAMPLED_VOLTAGE=""
SETTINGS_VERSION=""
CURRENT_SETTINGS_VERSION=6
SETTINGS_MIGRATED=0
DEBUG_LOG=0
LOG_MAX_BYTES=4194304
LAUNCHER_LOG_MAX_BYTES=131072
HELP_VISIBLE=0
BATTERY_LEVEL=0
CURRENT_FRAME_EPOCH=0
CURRENT_FRAME_BATTERY=0
NEXT_FRAME_EPOCH=0
NEXT_FRAME_READY=0
NEXT_FRAME_KIND=""
NEXT_FRAME_CHANGED_DIGITS=0
NEXT_FRAME_RENDER_EPOCH=0
NEXT_FRAME_BATTERY=0
NEXT_DISPLAY_CLOCK=0
CLOCK_SOURCE=system
KEY_PID=""
NEXT_RENDER_PID=""
SYNC_PID=""
RENDER_SERVER_PID=""
RENDER_SERVER_READY=0
RENDER_REQUEST_SEQUENCE=0
KEY_ACTION=""
WAIT_REASON=""
ORIGINAL_WIFI_STATE=""
LAST_INTERACTION_CLOCK=0
RTC_FAILURE_LOGGED=0
RTC_WOKE_EARLY=0
RTC_RESUME_LATENESS_SECONDS=0
REFRESH_SCHEDULE_EPOCH=0
DRIFT_REMAINDER_MS=0
REFRESH_BOUNDARY_UPTIME_CS=""
REFRESH_PLANNED_START_UPTIME_CS=""
REFRESH_PROFILE_KIND=""
REFRESH_DURATION_MS=0
CLEANED=0
UI_STOPPED=0

is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}
log_message() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}
log_debug() {
  [ "$DEBUG_LOG" = "1" ] && log_message "debug: $1"
  return 0
}
file_size_bytes() {
  [ -f "$1" ] || { echo 0; return; }
  wc -c < "$1" 2>/dev/null | tr -d ' '
}
truncate_log_if_oversize() {
  ROTATE_PATH="$1"
  ROTATE_LIMIT="$2"
  ROTATE_SIZE=$(file_size_bytes "$ROTATE_PATH")
  is_uint "$ROTATE_SIZE" || return 1
  if [ "$ROTATE_SIZE" -gt "$ROTATE_LIMIT" ]; then
    : > "$ROTATE_PATH"
    return 0
  fi
  return 1
}
start_new_session_log() {
  truncate_log_if_oversize "$LOG_FILE" "$LOG_MAX_BYTES"
  if [ -s "$LOG_FILE" ]; then
    rm -f "$LOG_FILE.1"
    mv "$LOG_FILE" "$LOG_FILE.1"
  fi
  : > "$LOG_FILE"
}

. "$SRC_DIR/time_sync.sh"

load_settings() {
  [ -f "$SETTINGS_FILE" ] && . "$SETTINGS_FILE"
  is_uint "$SETTINGS_VERSION" || SETTINGS_VERSION=0
  if [ "$SETTINGS_VERSION" -lt "$CURRENT_SETTINGS_VERSION" ]; then
    # Version 3 shortened idle; version 4 adjusted lead;
    # Version 5 adds auto NTP sync, drift compensation, and power optimizations.
    [ "$SETTINGS_VERSION" -lt 3 ] && IDLE_SUSPEND_SECONDS=15
    if [ "$SETTINGS_VERSION" -lt 5 ]; then
      IDLE_SUSPEND_SECONDS=15
      RTC_WAKE_LEAD_SECONDS=3
      BATTERY_REFRESH_SETTLE_SECONDS=25
      AUTO_TIME_SYNC_INTERVAL_HOURS=0
      RTC_DRIFT_COMPENSATION_PPM=5400
    fi
    if [ "$SETTINGS_VERSION" -lt 6 ]; then
      AUTO_DRIFT_CALIBRATION=1
    fi
    SETTINGS_VERSION="$CURRENT_SETTINGS_VERSION"
    SETTINGS_MIGRATED=1
  fi
  case "$ORIENTATION" in portrait|portrait_down|landscape_right|landscape_left) ;; *) ORIENTATION=landscape_right ;; esac
  case "$HOUR_MODE" in 12|24) ;; *) HOUR_MODE=24 ;; esac
  case "$THEME" in light|dark) ;; *) THEME=light ;; esac
  is_uint "$TIME_SYNC_TIMEOUT" || TIME_SYNC_TIMEOUT=45
  is_uint "$AUTO_TIME_SYNC_INTERVAL_HOURS" || AUTO_TIME_SYNC_INTERVAL_HOURS=0
  is_uint "$RTC_DRIFT_COMPENSATION_PPM" || RTC_DRIFT_COMPENSATION_PPM=0
  is_uint "$IDLE_SUSPEND_SECONDS" || IDLE_SUSPEND_SECONDS=15
  is_uint "$RTC_WAKE_LEAD_SECONDS" || RTC_WAKE_LEAD_SECONDS=3
  is_uint "$PARTIAL_REFRESH_DURATION_MS" || PARTIAL_REFRESH_DURATION_MS=800
  is_uint "$FULL_REFRESH_DURATION_MS" || FULL_REFRESH_DURATION_MS=1400
  is_uint "$BATTERY_REFRESH_SETTLE_SECONDS" || BATTERY_REFRESH_SETTLE_SECONDS=25
  case "$DEBUG_LOG" in 0|1) ;; *) DEBUG_LOG=0 ;; esac
  case "$AUTO_TIME_CHECK_HOURLY" in 0|1) ;; *) AUTO_TIME_CHECK_HOURLY=0 ;; esac
  case "$AUTO_DRIFT_CALIBRATION" in 0|1) ;; *) AUTO_DRIFT_CALIBRATION=1 ;; esac
  is_uint "$LOG_MAX_BYTES" || LOG_MAX_BYTES=4194304
  [ "$TIME_SYNC_TIMEOUT" -lt 10 ] && TIME_SYNC_TIMEOUT=10
  [ "$TIME_SYNC_TIMEOUT" -gt 180 ] && TIME_SYNC_TIMEOUT=180
  [ "$AUTO_TIME_SYNC_INTERVAL_HOURS" -gt 72 ] && AUTO_TIME_SYNC_INTERVAL_HOURS=72
  [ "$IDLE_SUSPEND_SECONDS" -lt 5 ] && IDLE_SUSPEND_SECONDS=5
  [ "$IDLE_SUSPEND_SECONDS" -gt 3600 ] && IDLE_SUSPEND_SECONDS=3600
  [ "$RTC_WAKE_LEAD_SECONDS" -lt 1 ] && RTC_WAKE_LEAD_SECONDS=1
  [ "$RTC_WAKE_LEAD_SECONDS" -gt 10 ] && RTC_WAKE_LEAD_SECONDS=10
  [ "$PARTIAL_REFRESH_DURATION_MS" -lt 100 ] && PARTIAL_REFRESH_DURATION_MS=100
  [ "$PARTIAL_REFRESH_DURATION_MS" -gt 5000 ] && PARTIAL_REFRESH_DURATION_MS=5000
  [ "$FULL_REFRESH_DURATION_MS" -lt 100 ] && FULL_REFRESH_DURATION_MS=100
  [ "$FULL_REFRESH_DURATION_MS" -gt 5000 ] && FULL_REFRESH_DURATION_MS=5000
  [ "$BATTERY_REFRESH_SETTLE_SECONDS" -gt 50 ] && BATTERY_REFRESH_SETTLE_SECONDS=50
  [ "$LOG_MAX_BYTES" -lt 65536 ] && LOG_MAX_BYTES=65536
  [ "$LOG_MAX_BYTES" -gt 16777216 ] && LOG_MAX_BYTES=16777216
  [ -z "$TIMEZONE" ] && TIMEZONE=CST-8
  case "$NTP_SERVERS" in
    ''|*[!A-Za-z0-9._\ -]*) NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com" ;;
  esac
  export TZ="$TIMEZONE"
  [ "$SETTINGS_MIGRATED" = "1" ] && save_settings
}
save_settings() {
  {
    echo "SETTINGS_VERSION=$CURRENT_SETTINGS_VERSION"
    echo "ORIENTATION=$ORIENTATION"
    echo "HOUR_MODE=$HOUR_MODE"
    echo "THEME=$THEME"
    echo "TIMEZONE=$TIMEZONE"
    echo "TIME_SYNC_TIMEOUT=$TIME_SYNC_TIMEOUT"
    echo "NTP_SERVERS=\"$NTP_SERVERS\""
    echo "AUTO_TIME_SYNC_INTERVAL_HOURS=$AUTO_TIME_SYNC_INTERVAL_HOURS"
    echo "AUTO_TIME_CHECK_HOURLY=$AUTO_TIME_CHECK_HOURLY"
    echo "AUTO_DRIFT_CALIBRATION=$AUTO_DRIFT_CALIBRATION"
    echo "RTC_DRIFT_COMPENSATION_PPM=$RTC_DRIFT_COMPENSATION_PPM"
    echo "IDLE_SUSPEND_SECONDS=$IDLE_SUSPEND_SECONDS"
    echo "RTC_WAKE_LEAD_SECONDS=$RTC_WAKE_LEAD_SECONDS"
    echo "PARTIAL_REFRESH_DURATION_MS=$PARTIAL_REFRESH_DURATION_MS"
    echo "FULL_REFRESH_DURATION_MS=$FULL_REFRESH_DURATION_MS"
    echo "BATTERY_REFRESH_SETTLE_SECONDS=$BATTERY_REFRESH_SETTLE_SECONDS"
    echo "DEBUG_LOG=$DEBUG_LOG"
    echo "LOG_MAX_BYTES=$LOG_MAX_BYTES"
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
  NEXT_FRAME_KIND=""
  NEXT_FRAME_CHANGED_DIGITS=0
  rm -f "$NEXT_RENDER_PID_FILE" "$NEXT_RENDER_WORK" "$NEXT_RENDER_RESULT" \
    "$NEXT_FRAME" "$NEXT_FRAME_META"
}

stop_render_server() {
  # Close the request pipe before stopping the server. File descriptor 8 is
  # reserved for the persistent renderer for the lifetime of this process.
  exec 8>&- 2>/dev/null
  if [ -n "$RENDER_SERVER_PID" ]; then
    if kill -0 "$RENDER_SERVER_PID" 2>/dev/null; then
      kill "$RENDER_SERVER_PID" 2>/dev/null
    fi
    wait "$RENDER_SERVER_PID" 2>/dev/null
  fi
  RENDER_SERVER_PID=""
  RENDER_SERVER_READY=0
  rm -f "$RENDER_SERVER_PID_FILE" "$RENDER_REQUEST_FIFO"
}

create_render_request_fifo() {
  FIFO_CREATE_METHOD=""
  rm -f "$RENDER_REQUEST_FIFO"

  if command -v mkfifo >/dev/null 2>&1 && \
     mkfifo "$RENDER_REQUEST_FIFO" 2>> "$LOG_FILE"; then
    FIFO_CREATE_METHOD=mkfifo
  else
    rm -f "$RENDER_REQUEST_FIFO"
    if command -v busybox >/dev/null 2>&1 && \
       busybox mkfifo "$RENDER_REQUEST_FIFO" 2>> "$LOG_FILE"; then
      FIFO_CREATE_METHOD=busybox-mkfifo
    else
      rm -f "$RENDER_REQUEST_FIFO"
      if [ -x /bin/busybox ] && \
         /bin/busybox mkfifo "$RENDER_REQUEST_FIFO" 2>> "$LOG_FILE"; then
        FIFO_CREATE_METHOD=/bin/busybox-mkfifo
      else
        rm -f "$RENDER_REQUEST_FIFO"
        if command -v mknod >/dev/null 2>&1 && \
           mknod "$RENDER_REQUEST_FIFO" p 2>> "$LOG_FILE"; then
          FIFO_CREATE_METHOD=mknod
        else
          rm -f "$RENDER_REQUEST_FIFO"
          if command -v busybox >/dev/null 2>&1 && \
             busybox mknod "$RENDER_REQUEST_FIFO" p 2>> "$LOG_FILE"; then
            FIFO_CREATE_METHOD=busybox-mknod
          elif [ -x /bin/busybox ] && \
               /bin/busybox mknod "$RENDER_REQUEST_FIFO" p 2>> "$LOG_FILE"; then
            FIFO_CREATE_METHOD=/bin/busybox-mknod
          fi
        fi
      fi
    fi
  fi

  if [ -z "$FIFO_CREATE_METHOD" ] || [ ! -p "$RENDER_REQUEST_FIFO" ]; then
    rm -f "$RENDER_REQUEST_FIFO"
    return 1
  fi
  log_message "persistent renderer pipe ready: method=$FIFO_CREATE_METHOD"
  return 0
}

ping_render_server() {
  RENDER_REQUEST_SEQUENCE=$((RENDER_REQUEST_SEQUENCE + 1))
  PING_STATUS_PATH="$RUNTIME_DIR/render-status-$$-$RENDER_REQUEST_SEQUENCE"
  rm -f "$PING_STATUS_PATH" "$PING_STATUS_PATH.tmp"
  if ! (printf 'PING\t%s\n' "$PING_STATUS_PATH" >&8) 2>/dev/null; then
    return 1
  fi
  if wait_renderer_reply "$PING_STATUS_PATH"; then
    if [ "$SERVER_REPLY" = "OK PONG" ]; then
      return 0
    fi
    log_message "persistent renderer handshake unexpected: ${SERVER_REPLY:-empty}"
  fi
  return 1
}

start_render_server() {
  RENDER_SERVER_READY=0
  rm -f "$RENDER_SERVER_PID_FILE" "$RENDER_REQUEST_FIFO"
  if ! create_render_request_fifo; then
    log_message "persistent renderer unavailable: all FIFO creation methods failed"
    return 1
  fi

  (
    cd /mnt/us/koreader || exit 1
    exec ./luajit "$SRC_DIR/render_server.lua" < "$RENDER_REQUEST_FIFO"
  ) >> "$LOG_FILE" 2>&1 &
  RENDER_SERVER_PID=$!
  echo "$RENDER_SERVER_PID" > "$RENDER_SERVER_PID_FILE"

  # Opening the writer unblocks the server's FIFO reader and keeps stdin open
  # between requests, allowing LuaJIT and its native libraries to stay loaded.
  if ! exec 8>"$RENDER_REQUEST_FIFO"; then
    log_message "persistent renderer unavailable: could not open request pipe"
    stop_render_server
    return 1
  fi
  if ! kill -0 "$RENDER_SERVER_PID" 2>/dev/null; then
    log_message "persistent renderer exited during startup"
    stop_render_server
    return 1
  fi
  RENDER_SERVER_READY=1
  if ! ping_render_server; then
    log_message "persistent renderer unavailable: startup handshake failed"
    stop_render_server
    return 1
  fi
  log_message "persistent renderer started: pid=$RENDER_SERVER_PID handshake=pong"
  return 0
}

cleanup() {
  [ "$CLEANED" = "1" ] && return
  CLEANED=1
  [ -n "$KEY_PID" ] && kill "$KEY_PID" 2>/dev/null
  cancel_next_frame_render
  stop_render_server
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
    "$SYNC_RESULT_FILE" "$SYNC_RESULT_TMP" "$RENDER_SERVER_PID_FILE" \
    "$AUTO_SYNC_RESULT_FILE" "$AUTO_SYNC_RESULT_TMP" \
    "$RENDER_REQUEST_FIFO" "$CURRENT_FRAME" "$NEXT_FRAME" \
    "$NEXT_RENDER_WORK" "$NEXT_RENDER_RESULT" "$NEXT_FRAME_META" \
    "$PARTIAL_DISABLED_FILE"
}
calc_battery_from_voltage() {
  V="$1"
  is_uint "$V" || return 1
  [ "$V" -ge 2500 ] && [ "$V" -le 4500 ] || return 1
  if [ "$V" -ge 4120 ]; then
    echo 100
  elif [ "$V" -ge 4050 ]; then
    echo $(( 85 + (V - 4050) * 15 / 70 ))
  elif [ "$V" -ge 3950 ]; then
    echo $(( 70 + (V - 3950) * 15 / 100 ))
  elif [ "$V" -ge 3850 ]; then
    echo $(( 55 + (V - 3850) * 15 / 100 ))
  elif [ "$V" -ge 3770 ]; then
    echo $(( 40 + (V - 3770) * 15 / 80 ))
  elif [ "$V" -ge 3700 ]; then
    echo $(( 25 + (V - 3700) * 15 / 70 ))
  elif [ "$V" -ge 3620 ]; then
    echo $(( 15 + (V - 3620) * 10 / 80 ))
  elif [ "$V" -ge 3520 ]; then
    echo $(( 5 + (V - 3520) * 10 / 100 ))
  elif [ "$V" -ge 3420 ]; then
    echo $(( 1 + (V - 3420) * 4 / 100 ))
  else
    echo 0
  fi
}

calc_effective_ppm() {
  V="$1"
  BASE_PPM="$2"
  TRIM="${3:-0}"
  is_uint "$BASE_PPM" || BASE_PPM=0
  [ "$BASE_PPM" -le 0 ] && { echo 0; return 0; }
  is_uint "$V" || { echo "$BASE_PPM"; return 0; }
  is_uint "${TRIM#-}" || TRIM=0

  # Kindle 4 crystal oscillator drift scales strongly with supply voltage:
  # - High voltage (>= 4050mV): raw crystal runs fast by ~18.5s/h -> full BASE_PPM (~5400)
  # - Transition zone (3950mV - 4050mV): drift linearly reduces to 0 around 3950mV
  # - Low voltage (< 3950mV): raw crystal runs neutral/slow -> suppress setback (PPM=0)
  if [ "$V" -ge 4050 ]; then
    EFF_PPM=$(( BASE_PPM + TRIM ))
  elif [ "$V" -ge 3950 ]; then
    VOLT_BASE=$(( BASE_PPM * (V - 3950) / 100 ))
    EFF_PPM=$(( VOLT_BASE + TRIM ))
  else
    if [ "$TRIM" -gt 0 ]; then
      EFF_PPM="$TRIM"
    else
      EFF_PPM=0
    fi
  fi
  [ "$EFF_PPM" -lt 0 ] && EFF_PPM=0
  [ "$EFF_PPM" -gt 8000 ] && EFF_PPM=8000
  echo "$EFF_PPM"
}

update_adaptive_drift_trim() {
  [ "$AUTO_DRIFT_CALIBRATION" = "1" ] || return 0
  SYNC_STAT_FILE="$RUNTIME_DIR/last_sntp_sync"
  [ -f "$SYNC_STAT_FILE" ] || return 0

  OFFSET_MS=""
  ELAPSED_SEC=""
  DRIFT_PPM=""
  while IFS='=' read -r key val; do
    case "$key" in
      OFFSET_MS) OFFSET_MS="$val" ;;
      ELAPSED_SEC) ELAPSED_SEC="$val" ;;
      DRIFT_PPM) DRIFT_PPM="$val" ;;
    esac
  done < "$SYNC_STAT_FILE"
  rm -f "$SYNC_STAT_FILE"

  is_uint "$ELAPSED_SEC" || return 0
  [ "$ELAPSED_SEC" -ge 1800 ] && [ "$ELAPSED_SEC" -le 10800 ] || return 0

  is_uint "${OFFSET_MS#-}" || return 0
  ABS_OFFSET_MS="${OFFSET_MS#-}"
  [ "$ABS_OFFSET_MS" -le 60000 ] || return 0

  is_uint "${DRIFT_PPM#-}" || return 0

  # Damping factor 0.5 to prevent hunting / oscillation
  ADAPT_STEP=$(( DRIFT_PPM / 2 ))
  [ "$ADAPT_STEP" -gt 1500 ] && ADAPT_STEP=1500
  [ "$ADAPT_STEP" -lt -1500 ] && ADAPT_STEP=-1500

  is_uint "${ADAPTIVE_PPM_TRIM#-}" || ADAPTIVE_PPM_TRIM=0
  ADAPTIVE_PPM_TRIM=$(( ADAPTIVE_PPM_TRIM + ADAPT_STEP ))
  [ "$ADAPTIVE_PPM_TRIM" -gt 3000 ] && ADAPTIVE_PPM_TRIM=3000
  [ "$ADAPTIVE_PPM_TRIM" -lt -3000 ] && ADAPTIVE_PPM_TRIM=-3000

  echo "$ADAPTIVE_PPM_TRIM" > "$RUNTIME_DIR/adaptive_ppm.trim"
  CURRENT_VOLT=""
  [ -f "$RUNTIME_DIR/battery.volt" ] && CURRENT_VOLT=$(cat "$RUNTIME_DIR/battery.volt" 2>/dev/null)
  NEXT_EFF_PPM=$(calc_effective_ppm "$CURRENT_VOLT" "$RTC_DRIFT_COMPENSATION_PPM" "$ADAPTIVE_PPM_TRIM")
  log_message "adaptive drift calibration: offset=${OFFSET_MS}ms elapsed=${ELAPSED_SEC}s residual=${DRIFT_PPM}ppm step=${ADAPT_STEP}ppm trim=${ADAPTIVE_PPM_TRIM}ppm next_eff=${NEXT_EFF_PPM}ppm"
}

get_battery_level() {
  VOLT=$(get_battery_voltage)
  if [ -n "$VOLT" ]; then
    LEVEL=$(calc_battery_from_voltage "$VOLT")
    if is_uint "$LEVEL"; then
      [ "$LEVEL" -gt 100 ] && LEVEL=100
      echo "$LEVEL"
      return 0
    fi
  fi
  LEVEL=$(gasgauge-info -c 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
  case "$LEVEL" in ''|*[!0-9]*) LEVEL=0 ;; esac
  [ "$LEVEL" -gt 100 ] && LEVEL=100
  echo "$LEVEL"
}

get_battery_voltage() {
  VOLT=$(gasgauge-info -v 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
  case "$VOLT" in
    ''|*[!0-9]*)
      if [ -r /sys/devices/system/yoshi_battery/yoshi_battery0/battery_voltage ]; then
        VOLT=$(cat /sys/devices/system/yoshi_battery/yoshi_battery0/battery_voltage 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
      fi
      ;;
  esac
  case "$VOLT" in
    ''|*[!0-9]*) VOLT="" ;;
    *)
      if [ "$VOLT" -gt 10000 ]; then
        VOLT=$((VOLT / 1000))
      fi
      ;;
  esac
  echo "$VOLT"
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
  # rtc_pmic_epoch_time is not a continuously advancing clock on K4NT.
  # Use wall-clock epoch time for all scheduling and deadline decisions.
  date +%s
}

monotonic_stamp() {
  UPTIME_VALUE=$(cat /proc/uptime 2>/dev/null)
  echo "${UPTIME_VALUE%% *}"
}
monotonic_centiseconds() {
  UPTIME_VALUE=$(cat /proc/uptime 2>/dev/null)
  UPTIME_VALUE=${UPTIME_VALUE%% *}
  case "$UPTIME_VALUE" in
    *.*) ;;
    *) return 1 ;;
  esac
  UPTIME_SECONDS=${UPTIME_VALUE%%.*}
  UPTIME_FRACTION=${UPTIME_VALUE#*.}
  is_uint "$UPTIME_SECONDS" || return 1
  UPTIME_FRACTION=$(printf '%.2s' "${UPTIME_FRACTION}00")
  is_uint "$UPTIME_FRACTION" || return 1
  echo $((UPTIME_SECONDS * 100 + 1$UPTIME_FRACTION - 100))
}
format_monotonic_centiseconds() {
  FORMAT_CS="$1"
  is_uint "$FORMAT_CS" || { echo unknown; return 1; }
  printf '%s.%02d' "$((FORMAT_CS / 100))" "$((FORMAT_CS % 100))"
}
sleep_ms() {
  DELAY_MS="$1"
  [ "$DELAY_MS" -gt 0 ] || return 0

  DELAY_US=$((DELAY_MS * 1000))
  if command -v usleep >/dev/null 2>&1; then
    usleep "$DELAY_US"
    return
  fi

  if [ -x /bin/busybox-usleep ]; then
    /bin/busybox-usleep "$DELAY_US"
    return
  fi

  if [ -x /bin/busybox ] && \
     /bin/busybox usleep "$DELAY_US" 2>/dev/null; then
    return
  fi

  DELAY_TEXT=$(printf '%d.%03d' \
    "$((DELAY_MS / 1000))" "$((DELAY_MS % 1000))")
  sleep "$DELAY_TEXT" 2>/dev/null && return

  DELAY_SECONDS=$(((DELAY_MS + 999) / 1000))
  sleep "$DELAY_SECONDS"
}

sleep_until_monotonic_centiseconds() {
  SLEEP_TARGET_CS="$1"
  is_uint "$SLEEP_TARGET_CS" || return 1
  while :; do
    SLEEP_NOW_CS=$(monotonic_centiseconds) || return 1
    SLEEP_REMAINING_CS=$((SLEEP_TARGET_CS - SLEEP_NOW_CS))
    [ "$SLEEP_REMAINING_CS" -gt 0 ] || return 0
    if [ "$SLEEP_REMAINING_CS" -gt 10 ]; then
      sleep_ms $(((SLEEP_REMAINING_CS - 5) * 10))
    else
      sleep_ms $((SLEEP_REMAINING_CS * 10))
    fi
  done
}
select_refresh_profile() {
  REFRESH_EPOCH="$1"
  REFRESH_MINUTE=$(((REFRESH_EPOCH / 60) % 60))
  if [ "$REFRESH_MINUTE" -eq 0 ]; then
    REFRESH_PROFILE_KIND=full
    REFRESH_DURATION_MS="$FULL_REFRESH_DURATION_MS"
  elif [ "$NEXT_FRAME_KIND" = "partial" ] && [ "$NEXT_FRAME_CHANGED_DIGITS" = "1" ]; then
    REFRESH_PROFILE_KIND=digit1
    REFRESH_DURATION_MS="$PARTIAL_REFRESH_DURATION_MS"
  elif [ "$NEXT_FRAME_KIND" = "partial" ]; then
    REFRESH_PROFILE_KIND=digit2
    REFRESH_DURATION_MS="$PARTIAL_REFRESH_DURATION_MS"
  else
    REFRESH_PROFILE_KIND=full
    REFRESH_DURATION_MS="$FULL_REFRESH_DURATION_MS"
  fi
}
prepare_refresh_release() {
  RELEASE_NOW_CLOCK="$1"
  is_uint "$RELEASE_NOW_CLOCK" || return 1
  if [ "$REFRESH_SCHEDULE_EPOCH" != "$NEXT_FRAME_EPOCH" ]; then
    select_refresh_profile "$NEXT_FRAME_EPOCH"
    REFRESH_SCHEDULE_EPOCH="$NEXT_FRAME_EPOCH"
    REFRESH_BOUNDARY_UPTIME_CS=""
    REFRESH_PLANNED_START_UPTIME_CS=""
  fi
  if ! is_uint "$REFRESH_BOUNDARY_UPTIME_CS"; then
    RELEASE_SAMPLE_CS=$(monotonic_centiseconds) || return 1
    if [ "$RELEASE_NOW_CLOCK" -lt "$NEXT_DISPLAY_CLOCK" ]; then
      REFRESH_BOUNDARY_UPTIME_CS=$((RELEASE_SAMPLE_CS + (NEXT_DISPLAY_CLOCK - RELEASE_NOW_CLOCK) * 100))
    else
      REFRESH_BOUNDARY_UPTIME_CS=$((RELEASE_SAMPLE_CS - (RELEASE_NOW_CLOCK - NEXT_DISPLAY_CLOCK) * 100))
    fi
    REFRESH_HALF_CS=$(((REFRESH_DURATION_MS + 19) / 20))
    REFRESH_PLANNED_START_UPTIME_CS=$((REFRESH_BOUNDARY_UPTIME_CS - REFRESH_HALF_CS))
    log_debug "refresh schedule: target=$NEXT_FRAME_EPOCH profile=$REFRESH_PROFILE_KIND estimate_ms=$REFRESH_DURATION_MS start_uptime=$(format_monotonic_centiseconds "$REFRESH_PLANNED_START_UPTIME_CS") boundary_uptime=$(format_monotonic_centiseconds "$REFRESH_BOUNDARY_UPTIME_CS")"
  fi
  sleep_until_monotonic_centiseconds "$REFRESH_PLANNED_START_UPTIME_CS"
}
initialize_virtual_clock() {
  SYSTEM_NOW=$(date +%s)
  CURRENT_FRAME_EPOCH=$(minute_epoch "$SYSTEM_NOW")
  NEXT_FRAME_EPOCH=$((CURRENT_FRAME_EPOCH + 60))
  CLOCK_SOURCE=system
  NEXT_DISPLAY_CLOCK="$NEXT_FRAME_EPOCH"
  DRIFT_REMAINDER_MS=0
  log_message "virtual clock anchored: system=$SYSTEM_NOW current=$CURRENT_FRAME_EPOCH next=$NEXT_FRAME_EPOCH source=system display_clock=$NEXT_DISPLAY_CLOCK"
}
advance_virtual_clock() {
  CURRENT_FRAME_EPOCH="$NEXT_FRAME_EPOCH"
  NEXT_FRAME_EPOCH=$((NEXT_FRAME_EPOCH + 60))
  NEXT_DISPLAY_CLOCK=$((NEXT_DISPLAY_CLOCK + 60))
}
run_one_shot_renderer() {
  ONE_SHOT_OUTPUT="$1"
  ONE_SHOT_ORIENTATION="$2"
  ONE_SHOT_THEME="$3"
  ONE_SHOT_EPOCH="$4"
  ONE_SHOT_BATTERY="$5"
  ONE_SHOT_HELP="$6"
  ONE_SHOT_HOUR_MODE="$7"
  (
    cd /mnt/us/koreader || exit 1
    ./luajit "$SRC_DIR/render.lua" "$ONE_SHOT_OUTPUT" \
      "$ONE_SHOT_ORIENTATION" "$ONE_SHOT_THEME" "$ONE_SHOT_EPOCH" \
      "$ONE_SHOT_BATTERY" "$ONE_SHOT_HELP" "$ONE_SHOT_HOUR_MODE"
  ) >> "$LOG_FILE" 2>&1
}

wait_renderer_reply() {
  STATUS_PATH="$1"
  [ "$RENDER_SERVER_READY" = "1" ] || return 1
  [ -n "$RENDER_SERVER_PID" ] && kill -0 "$RENDER_SERVER_PID" 2>/dev/null || return 1
  SERVER_WAIT_DEADLINE=$(($(date +%s) + 30))
  while [ ! -f "$STATUS_PATH" ]; do
    if ! kill -0 "$RENDER_SERVER_PID" 2>/dev/null; then
      return 1
    fi
    SERVER_WAIT_NOW=$(date +%s)
    if [ "$SERVER_WAIT_NOW" -ge "$SERVER_WAIT_DEADLINE" ]; then
      log_message "persistent renderer timed out; stopping server before fallback"
      kill "$RENDER_SERVER_PID" 2>/dev/null
      return 1
    fi
    pause_briefly
  done
  SERVER_REPLY=$(cat "$STATUS_PATH" 2>/dev/null)
  rm -f "$STATUS_PATH" "$STATUS_PATH.tmp"
  case "$SERVER_REPLY" in
    OK|OK\ *) return 0 ;;
    ERROR*) log_message "persistent renderer error: ${SERVER_REPLY#ERROR }" ;;
  esac
  return 1
}

adjust_system_time() {
  OFFSET_SEC="$1"
  is_uint "${OFFSET_SEC#-}" || return 1
  [ "$OFFSET_SEC" -eq 0 ] && return 0

  if [ "$RENDER_SERVER_READY" = "1" ]; then
    RENDER_REQUEST_SEQUENCE=$((RENDER_REQUEST_SEQUENCE + 1))
    STATUS_PATH="$RUNTIME_DIR/render-status-$RENDER_REQUEST_SEQUENCE"
    rm -f "$STATUS_PATH" "$STATUS_PATH.tmp"
    printf 'ADJUST\t%s\t%s\n' "$STATUS_PATH" "$OFFSET_SEC" > "$RENDER_REQUEST_FIFO" 2>/dev/null
    wait_renderer_reply "$STATUS_PATH" 500 >/dev/null 2>&1
    rm -f "$STATUS_PATH"
    return 0
  fi

  if [ -x /mnt/us/koreader/luajit ]; then
    /mnt/us/koreader/luajit -e "local ffi=require('ffi'); ffi.cdef[[struct timeval{long tv_sec;long tv_usec;}; int gettimeofday(struct timeval*,void*); int settimeofday(const struct timeval*,const void*);]]; local tv=ffi.new('struct timeval'); if ffi.C.gettimeofday(tv,nil)==0 then tv.tv_sec=tv.tv_sec+($OFFSET_SEC); ffi.C.settimeofday(tv,nil); end" >/dev/null 2>&1
    return 0
  fi
  return 1
}

run_persistent_renderer() {
  STATUS_PATH="$1"
  SERVER_OUTPUT="$2"
  SERVER_ORIENTATION="$3"
  SERVER_THEME="$4"
  SERVER_EPOCH="$5"
  SERVER_BATTERY="$6"
  SERVER_HELP="$7"
  SERVER_HOUR_MODE="$8"
  [ "$RENDER_SERVER_READY" = "1" ] || return 1
  [ -n "$RENDER_SERVER_PID" ] && kill -0 "$RENDER_SERVER_PID" 2>/dev/null || return 1
  rm -f "$STATUS_PATH" "$STATUS_PATH.tmp"

  # Every request is below PIPE_BUF, so background preparation and foreground
  # display requests cannot be interleaved in the FIFO.
  if ! (printf 'RENDER\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$STATUS_PATH" "$SERVER_OUTPUT" "$SERVER_ORIENTATION" "$SERVER_THEME" \
      "$SERVER_EPOCH" "$SERVER_BATTERY" "$SERVER_HELP" "$SERVER_HOUR_MODE" >&8) 2>/dev/null; then
    return 1
  fi
  wait_renderer_reply "$STATUS_PATH"
}

parse_partial_detail() {
  set -- $1
  [ "$5" = "DIGITS" ] || return 1
  is_uint "$1" && is_uint "$2" && is_uint "$3" && is_uint "$4" && \
    is_uint "$6" || return 1
  PARTIAL_X="$1"
  PARTIAL_Y="$2"
  PARTIAL_WIDTH="$3"
  PARTIAL_HEIGHT="$4"
  PARTIAL_CHANGED_COUNT="$6"
  PARTIAL_START_CS=""
  PARTIAL_END_CS=""
  if [ "${7:-}" = "START_CS" ] && is_uint "${8:-}" && \
     [ "${9:-}" = "END_CS" ] && is_uint "${10:-}"; then
    PARTIAL_START_CS="$8"
    PARTIAL_END_CS="${10}"
  fi
  return 0
}

prepare_partial_frame() {
  STATUS_PATH="$1"
  PARTIAL_ORIENTATION="$2"
  PARTIAL_THEME="$3"
  PARTIAL_CURRENT_EPOCH="$4"
  PARTIAL_EPOCH="$5"
  PARTIAL_HOUR_MODE="$6"
  [ "$RENDER_SERVER_READY" = "1" ] || return 1
  [ -n "$RENDER_SERVER_PID" ] && kill -0 "$RENDER_SERVER_PID" 2>/dev/null || return 1
  rm -f "$STATUS_PATH" "$STATUS_PATH.tmp"
  if ! (printf 'PREPARE\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$STATUS_PATH" "$PARTIAL_ORIENTATION" "$PARTIAL_THEME" \
      "$PARTIAL_CURRENT_EPOCH" "$PARTIAL_EPOCH" "$PARTIAL_HOUR_MODE" >&8) 2>/dev/null; then
    return 1
  fi
  if wait_renderer_reply "$STATUS_PATH"; then
    PARTIAL_DETAIL=${SERVER_REPLY#OK PARTIAL }
    parse_partial_detail "$PARTIAL_DETAIL" || PARTIAL_CHANGED_COUNT=1
    log_debug "partial frame prepared: target=$PARTIAL_EPOCH region=$PARTIAL_DETAIL"
    return 0
  fi
  return 1
}

display_partial_frame() {
  DISPLAY_EPOCH="$1"
  RENDER_REQUEST_SEQUENCE=$((RENDER_REQUEST_SEQUENCE + 1))
  STATUS_PATH="$RUNTIME_DIR/render-status-$$-$RENDER_REQUEST_SEQUENCE"
  [ "$RENDER_SERVER_READY" = "1" ] || return 1
  [ -n "$RENDER_SERVER_PID" ] && kill -0 "$RENDER_SERVER_PID" 2>/dev/null || return 1
  rm -f "$STATUS_PATH" "$STATUS_PATH.tmp"
  if ! (printf 'DISPLAY\t%s\t%s\n' "$STATUS_PATH" "$DISPLAY_EPOCH" >&8) 2>/dev/null; then
    return 1
  fi
  if ! wait_renderer_reply "$STATUS_PATH"; then
    return 1
  fi
  PARTIAL_DETAIL=${SERVER_REPLY#OK PARTIAL }
  parse_partial_detail "$PARTIAL_DETAIL" || return 1
  DISPLAY_CHANGED_DIGITS="$PARTIAL_CHANGED_COUNT"
  DISPLAY_START_UPTIME_CS="$PARTIAL_START_CS"
  DISPLAY_END_UPTIME_CS="$PARTIAL_END_CS"
  DISPLAY_END_CLOCK=$(scheduler_now 2>/dev/null)
  if is_uint "$DISPLAY_START_UPTIME_CS" && is_uint "$DISPLAY_END_UPTIME_CS" && \
     [ "$DISPLAY_END_UPTIME_CS" -ge "$DISPLAY_START_UPTIME_CS" ]; then
    DISPLAY_DURATION_MS=$(((DISPLAY_END_UPTIME_CS - DISPLAY_START_UPTIME_CS) * 10))
    if [ "$REFRESH_SCHEDULE_EPOCH" = "$DISPLAY_EPOCH" ] && is_uint "$REFRESH_BOUNDARY_UPTIME_CS"; then
      DISPLAY_START_OFFSET_MS=$(((DISPLAY_START_UPTIME_CS - REFRESH_BOUNDARY_UPTIME_CS) * 10))
      DISPLAY_END_OFFSET_MS=$(((DISPLAY_END_UPTIME_CS - REFRESH_BOUNDARY_UPTIME_CS) * 10))
      log_message "minute: target=$DISPLAY_EPOCH kind=digits region=$PARTIAL_X $PARTIAL_Y $PARTIAL_WIDTH $PARTIAL_HEIGHT DIGITS $DISPLAY_CHANGED_DIGITS refresh_start=$(format_monotonic_centiseconds "$DISPLAY_START_UPTIME_CS") minute_boundary=$(format_monotonic_centiseconds "$REFRESH_BOUNDARY_UPTIME_CS") refresh_end=$(format_monotonic_centiseconds "$DISPLAY_END_UPTIME_CS") start_offset_ms=$DISPLAY_START_OFFSET_MS end_offset_ms=$DISPLAY_END_OFFSET_MS duration_ms=$DISPLAY_DURATION_MS fixed_ms=$PARTIAL_REFRESH_DURATION_MS rtc_late=${RTC_RESUME_LATENESS_SECONDS:-unknown}"
    else
      log_message "minute: target=$DISPLAY_EPOCH kind=digits region=$PARTIAL_X $PARTIAL_Y $PARTIAL_WIDTH $PARTIAL_HEIGHT DIGITS $DISPLAY_CHANGED_DIGITS refresh_start=$(format_monotonic_centiseconds "$DISPLAY_START_UPTIME_CS") minute_boundary=unknown refresh_end=$(format_monotonic_centiseconds "$DISPLAY_END_UPTIME_CS") duration_ms=$DISPLAY_DURATION_MS fixed_ms=$PARTIAL_REFRESH_DURATION_MS rtc_late=${RTC_RESUME_LATENESS_SECONDS:-unknown}"
    fi
  else
    log_message "minute: target=$DISPLAY_EPOCH kind=digits region=$PARTIAL_DETAIL timing=unavailable display_clock=${DISPLAY_END_CLOCK:-unknown} rtc_late=${RTC_RESUME_LATENESS_SECONDS:-unknown}"
  fi
  return 0
}

run_renderer() {
  STATUS_PATH="$1"
  shift
  if run_persistent_renderer "$STATUS_PATH" "$@"; then
    return 0
  fi
  log_message "persistent renderer request failed; using one-shot fallback"
  run_one_shot_renderer "$@"
}

render_frame() {
  TARGET_EPOCH="$1"
  OUTPUT_PATH="$2"
  rm -f "$OUTPUT_PATH"
  log_debug "rendering epoch $TARGET_EPOCH to $OUTPUT_PATH"
  RENDER_REQUEST_SEQUENCE=$((RENDER_REQUEST_SEQUENCE + 1))
  RENDER_STATUS_PATH="$RUNTIME_DIR/render-status-$$-$RENDER_REQUEST_SEQUENCE"
  run_renderer "$RENDER_STATUS_PATH" "$OUTPUT_PATH" \
    "$ORIENTATION" "$THEME" "$TARGET_EPOCH" "$BATTERY_LEVEL" \
    "$HELP_VISIBLE" "$HOUR_MODE"
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
  log_debug "current-frame sample: target=$CURRENT_FRAME_EPOCH battery=$CURRENT_FRAME_BATTERY"
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
  DISPLAY_START_UPTIME_CS=$(monotonic_centiseconds 2>/dev/null)
  log_debug "display start: target=$DISPLAY_EPOCH battery=$DISPLAY_BATTERY source=$CLOCK_SOURCE clock=${DISPLAY_START_CLOCK:-unknown} uptime=${DISPLAY_START_UPTIME:-unknown}"
  if [ "$FORCE_FULL" = "1" ] || [ "$DISPLAY_MINUTE" -eq 0 ]; then
    full_refresh "$FRAME_PATH"
  else
    eips -g "$FRAME_PATH" >> "$LOG_FILE" 2>&1
  fi
  DISPLAY_END_CLOCK=$(scheduler_now 2>/dev/null)
  DISPLAY_END_UPTIME=$(monotonic_stamp)
  DISPLAY_END_UPTIME_CS=$(monotonic_centiseconds 2>/dev/null)
  if is_uint "$DISPLAY_START_UPTIME_CS" && is_uint "$DISPLAY_END_UPTIME_CS" && \
     [ "$DISPLAY_END_UPTIME_CS" -ge "$DISPLAY_START_UPTIME_CS" ]; then
    DISPLAY_DURATION_MS=$(((DISPLAY_END_UPTIME_CS - DISPLAY_START_UPTIME_CS) * 10))
    if [ "$REFRESH_SCHEDULE_EPOCH" = "$DISPLAY_EPOCH" ] && is_uint "$REFRESH_BOUNDARY_UPTIME_CS"; then
      DISPLAY_START_OFFSET_MS=$(((DISPLAY_START_UPTIME_CS - REFRESH_BOUNDARY_UPTIME_CS) * 10))
      DISPLAY_END_OFFSET_MS=$(((DISPLAY_END_UPTIME_CS - REFRESH_BOUNDARY_UPTIME_CS) * 10))
      log_message "frame: target=$DISPLAY_EPOCH kind=png battery=$DISPLAY_BATTERY refresh_start=$(format_monotonic_centiseconds "$DISPLAY_START_UPTIME_CS") minute_boundary=$(format_monotonic_centiseconds "$REFRESH_BOUNDARY_UPTIME_CS") refresh_end=$(format_monotonic_centiseconds "$DISPLAY_END_UPTIME_CS") start_offset_ms=$DISPLAY_START_OFFSET_MS end_offset_ms=$DISPLAY_END_OFFSET_MS duration_ms=$DISPLAY_DURATION_MS fixed_ms=$FULL_REFRESH_DURATION_MS"
    else
      log_message "frame: target=$DISPLAY_EPOCH kind=png battery=$DISPLAY_BATTERY refresh_start=$(format_monotonic_centiseconds "$DISPLAY_START_UPTIME_CS") minute_boundary=none refresh_end=$(format_monotonic_centiseconds "$DISPLAY_END_UPTIME_CS") duration_ms=$DISPLAY_DURATION_MS fixed_ms=$FULL_REFRESH_DURATION_MS"
    fi
  else
    log_message "frame: target=$DISPLAY_EPOCH kind=png battery=$DISPLAY_BATTERY clock=${DISPLAY_END_CLOCK:-unknown} uptime=${DISPLAY_END_UPTIME:-unknown} timing=unavailable"
  fi
}
start_next_frame_render() {
  BATTERY_OVERRIDE="$1"
  [ -n "$SYNC_PID" ] && return 1
  next_render_in_progress && return 1
  if is_uint "$BATTERY_OVERRIDE"; then
    BATTERY_LEVEL="$BATTERY_OVERRIDE"
  else
    # The K4 gas gauge is deliberately sampled after the hourly refresh. Keep
    # that displayed value between samples so ordinary minutes remain a pure
    # changed-digit update.
    BATTERY_LEVEL="$CURRENT_FRAME_BATTERY"
    is_uint "$BATTERY_LEVEL" || BATTERY_LEVEL=$(get_battery_level)
  fi
  NEXT_FRAME_RENDER_EPOCH="$NEXT_FRAME_EPOCH"
  NEXT_FRAME_BATTERY="$BATTERY_LEVEL"
  NEXT_FRAME_READY=0
  NEXT_FRAME_KIND=""
  NEXT_FRAME_CHANGED_DIGITS=0
  rm -f "$NEXT_FRAME" "$NEXT_RENDER_WORK" "$NEXT_RENDER_RESULT" \
    "$NEXT_RENDER_PID_FILE" "$NEXT_FRAME_META"
  log_debug "pre-rendering next minute: target=$NEXT_FRAME_RENDER_EPOCH battery=$NEXT_FRAME_BATTERY"
  RENDER_REQUEST_SEQUENCE=$((RENDER_REQUEST_SEQUENCE + 1))
  NEXT_RENDER_STATUS_PATH="$RUNTIME_DIR/render-status-$$-$RENDER_REQUEST_SEQUENCE"
  NEXT_RENDER_MINUTE=$(((NEXT_FRAME_RENDER_EPOCH / 60) % 60))
  NEXT_RENDER_STEP=$((NEXT_FRAME_RENDER_EPOCH - CURRENT_FRAME_EPOCH))
  PARTIAL_ELIGIBLE=0
  if [ "$HELP_VISIBLE" = "0" ] && [ "$NEXT_RENDER_MINUTE" -ne 0 ] && \
     [ "$NEXT_RENDER_STEP" -eq 60 ] && \
     [ "$NEXT_FRAME_BATTERY" = "$CURRENT_FRAME_BATTERY" ] && \
     [ "$RENDER_SERVER_READY" = "1" ] && [ ! -f "$PARTIAL_DISABLED_FILE" ]; then
    PARTIAL_ELIGIBLE=1
  fi
  (
    if [ "$PARTIAL_ELIGIBLE" = "1" ] && \
       prepare_partial_frame "$NEXT_RENDER_STATUS_PATH" "$ORIENTATION" "$THEME" \
         "$CURRENT_FRAME_EPOCH" "$NEXT_FRAME_RENDER_EPOCH" "$HOUR_MODE"; then
      echo "partial $NEXT_FRAME_RENDER_EPOCH $NEXT_FRAME_BATTERY ${PARTIAL_CHANGED_COUNT:-1}" > "$NEXT_RENDER_RESULT"
    else
      if [ "$PARTIAL_ELIGIBLE" = "1" ]; then
        log_message "partial preparation unavailable; pre-rendering full PNG fallback"
        touch "$PARTIAL_DISABLED_FILE"
      fi
      if run_renderer "$NEXT_RENDER_STATUS_PATH" "$NEXT_RENDER_WORK" \
        "$ORIENTATION" "$THEME" "$NEXT_FRAME_RENDER_EPOCH" "$NEXT_FRAME_BATTERY" \
        "$HELP_VISIBLE" "$HOUR_MODE" && [ -s "$NEXT_RENDER_WORK" ]; then
        echo "png $NEXT_FRAME_RENDER_EPOCH $NEXT_FRAME_BATTERY 0" > "$NEXT_RENDER_RESULT"
      else
        false
      fi
    fi
  ) &
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
  RESULT_KIND=""
  RESULT_EPOCH=""
  RESULT_BATTERY=""
  RESULT_CHANGED_DIGITS=0
  [ -f "$NEXT_RENDER_RESULT" ] && \
    read RESULT_KIND RESULT_EPOCH RESULT_BATTERY RESULT_CHANGED_DIGITS < "$NEXT_RENDER_RESULT"
  rm -f "$NEXT_RENDER_RESULT"
  if [ "$RENDER_STATUS" -eq 0 ] && [ "$RESULT_EPOCH" = "$NEXT_FRAME_RENDER_EPOCH" ] && \
     [ "$RESULT_BATTERY" = "$NEXT_FRAME_BATTERY" ]; then
    case "$RESULT_KIND" in
      partial)
        is_uint "$RESULT_CHANGED_DIGITS" || RESULT_CHANGED_DIGITS=1
        NEXT_FRAME_KIND=partial
        NEXT_FRAME_CHANGED_DIGITS="$RESULT_CHANGED_DIGITS"
        ;;
      png)
        if [ ! -s "$NEXT_RENDER_WORK" ]; then
          RESULT_KIND=""
        else
          mv "$NEXT_RENDER_WORK" "$NEXT_FRAME"
          NEXT_FRAME_KIND=png
          NEXT_FRAME_CHANGED_DIGITS=0
        fi
        ;;
      *) RESULT_KIND="" ;;
    esac
    if [ -n "$RESULT_KIND" ]; then
      echo "$NEXT_FRAME_KIND $NEXT_FRAME_RENDER_EPOCH $NEXT_FRAME_BATTERY $NEXT_FRAME_CHANGED_DIGITS" > "$NEXT_FRAME_META"
      NEXT_FRAME_READY=1
      log_debug "next-minute frame ready: kind=$NEXT_FRAME_KIND target=$NEXT_FRAME_RENDER_EPOCH battery=$NEXT_FRAME_BATTERY"
      return 0
    fi
  fi

  rm -f "$NEXT_RENDER_WORK" "$NEXT_FRAME"
  NEXT_FRAME_READY=0
  NEXT_FRAME_KIND=""
  NEXT_FRAME_CHANGED_DIGITS=0
  log_message "next-minute renderer failed with status $RENDER_STATUS"
  return 1
}
prepare_next_minute() {
  BATTERY_OVERRIDE="$1"
  NEXT_FRAME_READY=0
  NEXT_FRAME_KIND=""
  NEXT_FRAME_CHANGED_DIGITS=0
  rm -f "$NEXT_FRAME" "$NEXT_RENDER_RESULT" "$NEXT_FRAME_META"
  [ -n "$SYNC_PID" ] || start_next_frame_render "$BATTERY_OVERRIDE"
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

refresh_battery_sample_after_hourly_full_refresh() {
  # CURRENT_FRAME_EPOCH is the frame just displayed. display_frame() performs
  # a full refresh whenever its minute field is 00, so this condition binds
  # the gas-gauge awake window to that same hourly refresh.
  DISPLAYED_MINUTE=$(((CURRENT_FRAME_EPOCH / 60) % 60))
  [ "$DISPLAYED_MINUTE" -eq 0 ] || return 1

  # Concurrently perform active NTP time sync (when its configured interval is
  # due) or a passive check while already awake for the battery sample.
  NTP_SYNC_PID=""
  AUTO_SYNC_DUE=0
  AUTO_SYNC_NOW=$(scheduler_now 2>/dev/null)
  is_uint "$AUTO_SYNC_NOW" || AUTO_SYNC_NOW=0
  if [ "$AUTO_TIME_SYNC_INTERVAL_HOURS" -gt 0 ] && [ -z "$SYNC_PID" ]; then
    AUTO_SYNC_THRESHOLD_SECONDS=$(( AUTO_TIME_SYNC_INTERVAL_HOURS * 3600 - 300 ))
    [ "$AUTO_SYNC_THRESHOLD_SECONDS" -lt 1800 ] && AUTO_SYNC_THRESHOLD_SECONDS=1800
    if [ "$LAST_AUTO_SYNC_EPOCH" -le 0 ] || \
       [ "$AUTO_SYNC_NOW" -lt "$LAST_AUTO_SYNC_EPOCH" ] || \
       [ $((AUTO_SYNC_NOW - LAST_AUTO_SYNC_EPOCH)) -ge "$AUTO_SYNC_THRESHOLD_SECONDS" ]; then
      CURRENT_SYNC_VOLT=$(get_battery_voltage)
      if is_uint "$CURRENT_SYNC_VOLT" && [ "$CURRENT_SYNC_VOLT" -lt 3550 ]; then
        log_message "auto sync skipped: low battery (${CURRENT_SYNC_VOLT}mV < 3550mV)"
      else
        AUTO_SYNC_DUE=1
      fi
    fi
  fi
  if [ "$AUTO_SYNC_DUE" = "1" ]; then
    rm -f "$AUTO_SYNC_RESULT_FILE" "$AUTO_SYNC_RESULT_TMP"
    (
      if time_sync_now "auto"; then
        date +%s > "$AUTO_SYNC_RESULT_TMP"
        mv "$AUTO_SYNC_RESULT_TMP" "$AUTO_SYNC_RESULT_FILE"
      fi
    ) &
    NTP_SYNC_PID=$!
  elif [ "$AUTO_TIME_CHECK_HOURLY" = "1" ] && [ -z "$SYNC_PID" ]; then
    CURRENT_SYNC_VOLT=$(get_battery_voltage)
    if is_uint "$CURRENT_SYNC_VOLT" && [ "$CURRENT_SYNC_VOLT" -lt 3550 ]; then
      log_message "auto time check skipped: low battery (${CURRENT_SYNC_VOLT}mV < 3550mV)"
    else
      (
        time_sync_now "check_only"
      ) &
      NTP_SYNC_PID=$!
    fi
  fi

  if [ "$BATTERY_REFRESH_SETTLE_SECONDS" -le 0 ]; then
    [ -n "$NTP_SYNC_PID" ] && wait "$NTP_SYNC_PID" 2>/dev/null
    FRESH_BATTERY_LEVEL=$(get_battery_level)
    FRESH_BATTERY_VOLT=$(get_battery_voltage)
    VOLT_MSG=""
    if [ -n "$FRESH_BATTERY_VOLT" ]; then
      VOLT_MSG=" (${FRESH_BATTERY_VOLT}mV)"
      echo "$FRESH_BATTERY_VOLT" > "$RUNTIME_DIR/battery.volt"
    fi
    log_message "battery refresh sample: old=$CURRENT_FRAME_BATTERY new=$FRESH_BATTERY_LEVEL$VOLT_MSG (instant)"
    echo "$FRESH_BATTERY_LEVEL"
    return 0
  fi

  REFRESH_AWAKE_START_CS=$(monotonic_centiseconds 2>/dev/null)
  is_uint "$REFRESH_AWAKE_START_CS" || return 1
  REFRESH_AWAKE_DEADLINE_CS=$((REFRESH_AWAKE_START_CS + BATTERY_REFRESH_SETTLE_SECONDS * 100))
  START_VOLT=$(get_battery_voltage)
  START_VOLT_MSG=""
  [ -n "$START_VOLT" ] && START_VOLT_MSG=" (${START_VOLT}mV)"
  log_message "battery refresh window started: settle=${BATTERY_REFRESH_SETTLE_SECONDS}s old=${CURRENT_FRAME_BATTERY}%$START_VOLT_MSG"

  while [ ! -f "$EXIT_FILE" ]; do
    if [ -f "$KEY_EVENT_FILE" ]; then
      [ -n "$NTP_SYNC_PID" ] && kill "$NTP_SYNC_PID" 2>/dev/null
      wifi_set_enabled 0
      log_message "battery refresh window interrupted by key event"
      return 1
    fi
    REFRESH_AWAKE_NOW_CS=$(monotonic_centiseconds 2>/dev/null)
    is_uint "$REFRESH_AWAKE_NOW_CS" || return 1

    [ "$REFRESH_AWAKE_NOW_CS" -ge "$REFRESH_AWAKE_DEADLINE_CS" ] && break
    sleep 1
  done

  [ -n "$NTP_SYNC_PID" ] && wait "$NTP_SYNC_PID" 2>/dev/null
  [ -f "$EXIT_FILE" ] && return 1
  FRESH_BATTERY_LEVEL=$(get_battery_level)
  FRESH_BATTERY_VOLT=$(get_battery_voltage)
  VOLT_MSG=""
  if [ -n "$FRESH_BATTERY_VOLT" ]; then
    VOLT_MSG=" (${FRESH_BATTERY_VOLT}mV)"
    echo "$FRESH_BATTERY_VOLT" > "$RUNTIME_DIR/battery.volt"
  fi
  log_message "battery refresh sample: old=$CURRENT_FRAME_BATTERY new=$FRESH_BATTERY_LEVEL$VOLT_MSG awake_uptime_cs=$REFRESH_AWAKE_START_CS"
  echo "$FRESH_BATTERY_LEVEL"
  return 0
}

try_rtc_suspend() {
  EXPECTED_WAKE_SYSTEM="$1"
  is_uint "$EXPECTED_WAKE_SYSTEM" || return 1
  [ "$EXPECTED_WAKE_SYSTEM" -gt 0 ] || return 1
  [ -r "$RTC_PATH" ] && [ -w "$RTC_PATH" ] && [ -w "$POWER_STATE_PATH" ] && \
    [ -r "$RTC_PMIC_EPOCH_PATH" ] || return 1
  SUSPEND_START_SYSTEM=$(date +%s)
  is_uint "$SUSPEND_START_SYSTEM" || return 1
  SUSPEND_SECONDS=$((EXPECTED_WAKE_SYSTEM - SUSPEND_START_SYSTEM))
  # Very short RTC alarms are unreliable on K4NT; stay awake instead.
  [ "$SUSPEND_SECONDS" -ge 2 ] || return 1
  RTC_STATE=$(cat "$RTC_PATH" 2>/dev/null)
  [ "$RTC_STATE" = "0" ] || return 1

  # Set hardware alarm countdown to exact planned suspend duration
  RTC_ALARM_SECONDS="$SUSPEND_SECONDS"
  echo -n "$RTC_ALARM_SECONDS" > "$RTC_PATH" 2>/dev/null || return 1
  RTC_WOKE_EARLY=0
  RTC_RESUME_LATENESS_SECONDS=0
  if [ "$DEBUG_LOG" = "1" ]; then
    SUSPEND_START_PMIC=$(read_pmic_epoch 2>/dev/null)
    log_debug "RTC suspend: planned_wake_system=$EXPECTED_WAKE_SYSTEM current_system=$SUSPEND_START_SYSTEM delay=$SUSPEND_SECONDS rtc_alarm=$RTC_ALARM_SECONDS pmic=${SUSPEND_START_PMIC:-unknown} display_clock=$NEXT_DISPLAY_CLOCK"
  fi
  echo mem > "$POWER_STATE_PATH" 2>> "$LOG_FILE"
  SUSPEND_STATUS=$?
  RESUME_SYSTEM=$(date +%s)
  if is_uint "$RESUME_SYSTEM" && [ "$RESUME_SYSTEM" -gt 0 ]; then
    RTC_RESUME_LATENESS_SECONDS=$((RESUME_SYSTEM - EXPECTED_WAKE_SYSTEM))
    if [ $((RESUME_SYSTEM + 1)) -lt "$EXPECTED_WAKE_SYSTEM" ]; then
      RTC_WOKE_EARLY=1
    fi

    # Calculate exact drift accrued during actual sleep time and set back system clock
    ACTUAL_SLEPT_SECONDS=$((RESUME_SYSTEM - SUSPEND_START_SYSTEM))
    CURRENT_VOLT=""
    [ -f "$RUNTIME_DIR/battery.volt" ] && CURRENT_VOLT=$(cat "$RUNTIME_DIR/battery.volt" 2>/dev/null)
    if [ -r "$RUNTIME_DIR/adaptive_ppm.trim" ]; then
      TRIM_VAL=$(cat "$RUNTIME_DIR/adaptive_ppm.trim" 2>/dev/null)
      is_uint "${TRIM_VAL#-}" && ADAPTIVE_PPM_TRIM="$TRIM_VAL"
    fi
    EFFECTIVE_PPM=$(calc_effective_ppm "$CURRENT_VOLT" "$RTC_DRIFT_COMPENSATION_PPM" "$ADAPTIVE_PPM_TRIM")
    if [ "$ACTUAL_SLEPT_SECONDS" -gt 0 ] && is_uint "$EFFECTIVE_PPM" && [ "$EFFECTIVE_PPM" -gt 0 ]; then
      is_uint "$DRIFT_REMAINDER_MS" || DRIFT_REMAINDER_MS=0
      REDUCTION_MS=$(( (ACTUAL_SLEPT_SECONDS * EFFECTIVE_PPM * 1000) / (1000000 + EFFECTIVE_PPM) ))
      TOTAL_REDUCTION_MS=$(( REDUCTION_MS + DRIFT_REMAINDER_MS ))
      REDUCTION_SECONDS=$(( TOTAL_REDUCTION_MS / 1000 ))
      DRIFT_REMAINDER_MS=$(( TOTAL_REDUCTION_MS % 1000 ))
      if [ "$REDUCTION_SECONDS" -gt 0 ]; then
        adjust_system_time "-$REDUCTION_SECONDS"
        log_message "drift clock adjust: setback ${REDUCTION_SECONDS}s (ppm=$EFFECTIVE_PPM, slept=${ACTUAL_SLEPT_SECONDS}s, rem=${DRIFT_REMAINDER_MS}ms)"
      fi
    fi
  fi
  if [ "$DEBUG_LOG" = "1" ]; then
    RESUME_PMIC=$(read_pmic_epoch 2>/dev/null)
    log_debug "RTC resume: planned_wake_system=$EXPECTED_WAKE_SYSTEM actual_system=$RESUME_SYSTEM lateness=$RTC_RESUME_LATENESS_SECONDS pmic=${RESUME_PMIC:-unknown} early=$RTC_WOKE_EARLY status=$SUSPEND_STATUS"
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
      NOW_CLOCK=$(date +%s)
    fi
    CLOCK_LATENESS=$((NOW_CLOCK - NEXT_DISPLAY_CLOCK))
    if [ "$CLOCK_LATENESS" -ge 60 ]; then
      cancel_next_frame_render
      # Re-anchor to the minute that is actually on the wall clock. Advancing
      # by a count of missed minutes can select the following minute instead.
      NEXT_FRAME_EPOCH=$(minute_epoch "$NOW_CLOCK")
      NEXT_DISPLAY_CLOCK="$NEXT_FRAME_EPOCH"
      log_message "virtual clock catch-up: now=$NOW_CLOCK next_target=$NEXT_FRAME_EPOCH next_display_clock=$NEXT_DISPLAY_CLOCK"
      continue
    fi
    REFRESH_REFERENCE_CLOCK=$((NEXT_DISPLAY_CLOCK - 1))
    if [ "$NOW_CLOCK" -ge "$REFRESH_REFERENCE_CLOCK" ]; then
      prepare_refresh_release "$NOW_CLOCK" || true
      REFRESH_ACTUAL_CLOCK=$(scheduler_now 2>/dev/null)
      if [ "$DEBUG_LOG" = "1" ]; then
        log_debug "refresh release: target=$NEXT_FRAME_EPOCH display_clock=$NEXT_DISPLAY_CLOCK profile=$REFRESH_PROFILE_KIND estimate_ms=$REFRESH_DURATION_MS actual_clock=${REFRESH_ACTUAL_CLOCK:-unknown} uptime=$(monotonic_stamp)"
      fi
      WAIT_REASON="minute"
      return
    fi
    IDLE_DEADLINE=$((LAST_INTERACTION_CLOCK + IDLE_SUSPEND_SECONDS))
    WAKE_CLOCK=$((NEXT_DISPLAY_CLOCK - RTC_WAKE_LEAD_SECONDS))
    LATEST_SUSPEND_CLOCK=$((WAKE_CLOCK - 1))
    if [ -z "$SYNC_PID" ] && ! next_render_in_progress && \
       [ "$NOW_CLOCK" -ge "$IDLE_DEADLINE" ] && \
       [ "$NOW_CLOCK" -lt "$LATEST_SUSPEND_CLOCK" ]; then
      if try_rtc_suspend "$WAKE_CLOCK"; then
        RTC_FAILURE_LOGGED=0
        if [ "$RTC_WOKE_EARLY" = "1" ]; then
          LAST_INTERACTION_CLOCK="$RESUME_SYSTEM"
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
    if [ "$NOW_CLOCK" -ge $((NEXT_DISPLAY_CLOCK - RTC_WAKE_LEAD_SECONDS)) ]; then
      sleep_ms 20
    else
      pause_briefly
    fi
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
  SYNC_REASON="${1:-manual}"
  [ -n "$SYNC_PID" ] && return 1
  rm -f "$SYNC_RESULT_FILE" "$SYNC_RESULT_TMP" "$SYNC_PID_FILE"
  log_message "$SYNC_REASON time synchronization requested"
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
  META_KIND=""
  META_EPOCH=""
  META_BATTERY=""
  META_CHANGED_DIGITS=0
  [ -f "$NEXT_FRAME_META" ] && read META_KIND META_EPOCH META_BATTERY META_CHANGED_DIGITS < "$NEXT_FRAME_META"
  if [ "$NEXT_FRAME_READY" = "1" ] && [ "$META_EPOCH" = "$NEXT_FRAME_EPOCH" ] && \
     is_uint "$META_BATTERY"; then
    case "$META_KIND" in
      partial)
        NEXT_FRAME_CHANGED_DIGITS="$META_CHANGED_DIGITS"
        if display_partial_frame "$META_EPOCH"; then
          rm -f "$NEXT_FRAME_META"
          CURRENT_FRAME_BATTERY="$META_BATTERY"
          NEXT_FRAME_READY=0
          NEXT_FRAME_KIND=""
          return 0
        fi
        log_message "partial display failed; rendering full PNG fallback"
        touch "$PARTIAL_DISABLED_FILE"
        BATTERY_LEVEL="$META_BATTERY"
        CURRENT_FRAME_BATTERY="$META_BATTERY"
        if render_frame "$META_EPOCH" "$CURRENT_FRAME"; then
          display_frame "$CURRENT_FRAME" 0 "$META_EPOCH" "$META_BATTERY"
          rm -f "$NEXT_FRAME_META"
          NEXT_FRAME_READY=0
          NEXT_FRAME_KIND=""
          return 0
        fi
        ;;
      png)
        if [ -s "$NEXT_FRAME" ]; then
          display_frame "$NEXT_FRAME" 0 "$META_EPOCH" "$META_BATTERY"
          mv "$NEXT_FRAME" "$CURRENT_FRAME"
          rm -f "$NEXT_FRAME_META"
          CURRENT_FRAME_BATTERY="$META_BATTERY"
          NEXT_FRAME_READY=0
          NEXT_FRAME_KIND=""
          return 0
        fi
        ;;
    esac
  fi
  log_message "next-minute frame rejected: expected_target=$NEXT_FRAME_EPOCH ready=$NEXT_FRAME_READY kind=${META_KIND:-missing} meta_target=${META_EPOCH:-missing} meta_battery=${META_BATTERY:-missing}"
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
    "$CURRENT_FRAME" "$NEXT_FRAME" "$NEXT_RENDER_WORK" "$NEXT_RENDER_RESULT" \
    "$NEXT_FRAME_META" \
    "$KEY_PID_FILE" "$NEXT_RENDER_PID_FILE" "$SYNC_PID_FILE" \
    "$SYNC_RESULT_FILE" "$SYNC_RESULT_TMP" "$RENDER_SERVER_PID_FILE" \
    "$AUTO_SYNC_RESULT_FILE" "$AUTO_SYNC_RESULT_TMP" \
    "$RENDER_REQUEST_FIFO" "$PARTIAL_DISABLED_FILE" \
    "$RUNTIME_DIR"/render-status-*
  load_settings
  if [ -r "$RUNTIME_DIR/adaptive_ppm.trim" ]; then
    TRIM_VAL=$(cat "$RUNTIME_DIR/adaptive_ppm.trim" 2>/dev/null)
    is_uint "${TRIM_VAL#-}" && ADAPTIVE_PPM_TRIM="$TRIM_VAL"
  fi
  start_new_session_log
  log_message "startup: active settings: ppm=$RTC_DRIFT_COMPENSATION_PPM auto_check=$AUTO_TIME_CHECK_HOURLY auto_sync_interval=$AUTO_TIME_SYNC_INTERVAL_HOURS idle_suspend=${IDLE_SUSPEND_SECONDS}s wake_lead=${RTC_WAKE_LEAD_SECONDS}s settle=${BATTERY_REFRESH_SETTLE_SECONDS}s auto_drift=$AUTO_DRIFT_CALIBRATION trim=${ADAPTIVE_PPM_TRIM}ppm"
  ORIGINAL_WIFI_STATE=$(wifi_get_enabled)
  case "$ORIGINAL_WIFI_STATE" in 0|1) ;; *) ORIGINAL_WIFI_STATE="" ;; esac
  log_message "startup: original Wi-Fi state=${ORIGINAL_WIFI_STATE:-unknown}"

  log_message "startup time synchronization requested"
  if time_sync_now; then
    log_message "startup time synchronization succeeded"
    LAST_AUTO_SYNC_EPOCH=$(date +%s)
    update_adaptive_drift_trim
  else
    log_message "startup time synchronization failed; continuing with system time"
    LAST_AUTO_SYNC_EPOCH=0
  fi
  # time_sync_now normally turns Wi-Fi off itself. Enforce the requested
  # post-sync state on every success and failure path.
  wifi_set_enabled 0
  initialize_virtual_clock
  start_render_server || log_message "using one-shot renderer for this session"

  # Validate the first frame before hiding the Kindle UI.
  if ! render_current_frame; then
    return 1
  fi
  STARTUP_VOLT=$(get_battery_voltage)
  STARTUP_VOLT_MSG=""
  if [ -n "$STARTUP_VOLT" ]; then
    STARTUP_VOLT_MSG=" (${STARTUP_VOLT}mV)"
    echo "$STARTUP_VOLT" > "$RUNTIME_DIR/battery.volt"
  fi
  log_message "startup battery: level=${CURRENT_FRAME_BATTERY}%$STARTUP_VOLT_MSG"
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
          cancel_next_frame_render
          if render_current_frame; then
            display_frame "$CURRENT_FRAME" 1 "$CURRENT_FRAME_EPOCH" "$CURRENT_FRAME_BATTERY"
          fi
          prepare_next_minute
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
          LAST_AUTO_SYNC_EPOCH=$(date +%s)
          update_adaptive_drift_trim
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
        if truncate_log_if_oversize "$LOG_FILE" "$LOG_MAX_BYTES"; then
          log_message "log truncated at ${LOG_MAX_BYTES} bytes"
        fi
        FRESH_BATTERY_LEVEL=""
        if FRESH_BATTERY_LEVEL=$(refresh_battery_sample_after_hourly_full_refresh); then
          if [ -f "$AUTO_SYNC_RESULT_FILE" ]; then
            AUTO_SYNC_COMPLETED_EPOCH=$(cat "$AUTO_SYNC_RESULT_FILE" 2>/dev/null)
            rm -f "$AUTO_SYNC_RESULT_FILE" "$AUTO_SYNC_RESULT_TMP"
            if is_uint "$AUTO_SYNC_COMPLETED_EPOCH" && [ "$AUTO_SYNC_COMPLETED_EPOCH" -gt 0 ]; then
              LAST_AUTO_SYNC_EPOCH="$AUTO_SYNC_COMPLETED_EPOCH"
            fi
            update_adaptive_drift_trim
            initialize_virtual_clock
          fi
          prepare_next_minute "$FRESH_BATTERY_LEVEL"
        else
          prepare_next_minute
        fi
        ;;
    esac
  done
}
if [ "$1" != "--run" ]; then
  mkdir -p "$LOG_DIR"
  truncate_log_if_oversize "$LAUNCHER_LOG" "$LAUNCHER_LOG_MAX_BYTES"
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
