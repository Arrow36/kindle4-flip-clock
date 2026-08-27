#!/bin/sh

# Sourced by start.sh. The clock keeps Wi-Fi off while running; this worker
# enables it only long enough to run the KOReader LuaSocket SNTP client.

time_sync_log() {
  log_message "$1"
}

# Duration measurements must not use wall time: SNTP deliberately changes it.
time_sync_monotonic_seconds() {
  UPTIME_VALUE=$(cat /proc/uptime 2>/dev/null)
  UPTIME_VALUE=${UPTIME_VALUE%% *}
  UPTIME_SECONDS=${UPTIME_VALUE%%.*}
  case "$UPTIME_SECONDS" in ''|*[!0-9]*) return 1 ;; esac
  echo "$UPTIME_SECONDS"
}

time_sync_elapsed_seconds() {
  ELAPSED_START="$1"
  ELAPSED_END="$2"
  case "$ELAPSED_START:$ELAPSED_END" in
    *[!0-9:]*) echo 0 ;;
    *)
      ELAPSED_VALUE=$((ELAPSED_END - ELAPSED_START))
      [ "$ELAPSED_VALUE" -lt 0 ] && ELAPSED_VALUE=0
      echo "$ELAPSED_VALUE"
      ;;
  esac
}

wifi_get_enabled() {
  /usr/bin/lipc-get-prop com.lab126.wifid enable 2>/dev/null
}

wifi_set_enabled() {
  /usr/bin/lipc-set-prop com.lab126.wifid enable "$1" >/dev/null 2>&1
  if [ "$1" = "0" ]; then
    /usr/bin/lipc-set-prop com.lab126.cmd wirelessEnable 0 >/dev/null 2>&1
  else
    /usr/bin/lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1
  fi
}

wait_for_wifi() {
  WAITED=0
  while [ "$WAITED" -lt "$TIME_SYNC_TIMEOUT" ]; do
    WIFI_STATE=$(/usr/bin/lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
    [ "$WIFI_STATE" = "CONNECTED" ] && return 0
    sleep 2
    WAITED=$((WAITED + 2))
  done
  return 1
}

run_koreader_sntp() {
  EXTRA_OPTION="$1"
  if [ -x /mnt/us/koreader/luajit ] && [ -f "$SRC_DIR/sntp.lua" ]; then
    time_sync_log "using KOReader LuaSocket SNTP client"
    # Intentional word splitting: the Lua client tries each peer in order.
    # shellcheck disable=SC2086
    (cd /mnt/us/koreader && ./luajit "$SRC_DIR/sntp.lua" $EXTRA_OPTION $NTP_SERVERS) >> "$LOG_FILE" 2>&1
    return $?
  fi

  time_sync_log "KOReader LuaSocket SNTP client is unavailable"
  return 127
}

time_sync_now() {
  SYNC_MODE="$1"
  if [ ! -x /mnt/us/koreader/luajit ] || [ ! -f "$SRC_DIR/sntp.lua" ]; then
    time_sync_log "time synchronization skipped: KOReader SNTP is unavailable"
    return 127
  fi

  SYNC_START_TIME=$(time_sync_monotonic_seconds 2>/dev/null)
  case "$SYNC_START_TIME" in ''|*[!0-9]*) SYNC_START_TIME=0 ;; esac
  time_sync_log "enabling Wi-Fi for time synchronization"
  if ! wifi_set_enabled 1; then
    time_sync_log "failed to enable Wi-Fi"
    return 1
  fi

  if ! wait_for_wifi; then
    time_sync_log "Wi-Fi did not connect within ${TIME_SYNC_TIMEOUT}s"
    wifi_set_enabled 0
    return 1
  fi
  WIFI_READY_TIME=$(time_sync_monotonic_seconds 2>/dev/null)
  case "$WIFI_READY_TIME" in ''|*[!0-9]*) WIFI_READY_TIME="$SYNC_START_TIME" ;; esac
  WIFI_CONNECT_SEC=$(time_sync_elapsed_seconds "$SYNC_START_TIME" "$WIFI_READY_TIME")
  time_sync_log "Wi-Fi connected in ${WIFI_CONNECT_SEC}s"

  if [ "$SYNC_MODE" = "check_only" ]; then
    time_sync_log "checking NTP offset (passive monitor) with: $NTP_SERVERS"
    run_koreader_sntp "--check-only"
    TIME_SYNC_STATUS=$?
    SYNC_END_TIME=$(time_sync_monotonic_seconds 2>/dev/null)
    case "$SYNC_END_TIME" in ''|*[!0-9]*) SYNC_END_TIME="$WIFI_READY_TIME" ;; esac
    TOTAL_SYNC_SEC=$(time_sync_elapsed_seconds "$SYNC_START_TIME" "$SYNC_END_TIME")
    wifi_set_enabled 0
    if [ "$TIME_SYNC_STATUS" -ne 0 ]; then
      time_sync_log "NTP offset check failed with status $TIME_SYNC_STATUS (total=${TOTAL_SYNC_SEC}s)"
      return 1
    fi
    time_sync_log "NTP offset check completed (total=${TOTAL_SYNC_SEC}s, wifi=${WIFI_CONNECT_SEC}s)"
    return 0
  fi

  time_sync_log "synchronizing with: $NTP_SERVERS"
  run_koreader_sntp ""
  TIME_SYNC_STATUS=$?
  if [ "$TIME_SYNC_STATUS" -ne 0 ]; then
    SYNC_END_TIME=$(time_sync_monotonic_seconds 2>/dev/null)
    case "$SYNC_END_TIME" in ''|*[!0-9]*) SYNC_END_TIME="$WIFI_READY_TIME" ;; esac
    TOTAL_SYNC_SEC=$(time_sync_elapsed_seconds "$SYNC_START_TIME" "$SYNC_END_TIME")
    time_sync_log "NTP synchronization failed with status $TIME_SYNC_STATUS (total=${TOTAL_SYNC_SEC}s)"
    wifi_set_enabled 0
    return 1
  fi

  if command -v hwclock >/dev/null 2>&1; then
    hwclock -w >> "$LOG_FILE" 2>&1 || time_sync_log "system time set, but hwclock -w failed"
  else
    time_sync_log "system time set; hwclock is unavailable"
  fi

  SYNC_END_TIME=$(time_sync_monotonic_seconds 2>/dev/null)
  case "$SYNC_END_TIME" in ''|*[!0-9]*) SYNC_END_TIME="$WIFI_READY_TIME" ;; esac
  TOTAL_SYNC_SEC=$(time_sync_elapsed_seconds "$SYNC_START_TIME" "$SYNC_END_TIME")
  wifi_set_enabled 0
  time_sync_log "time synchronization completed (total=${TOTAL_SYNC_SEC}s, wifi=${WIFI_CONNECT_SEC}s)"
  return 0
}
