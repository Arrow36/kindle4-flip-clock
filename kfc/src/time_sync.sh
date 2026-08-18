#!/bin/sh

# Sourced by start.sh. The clock keeps Wi-Fi off while running; this worker
# enables it only long enough to run the KOReader LuaSocket SNTP client.

time_sync_log() {
  log_message "$1"
}

wifi_get_enabled() {
  /usr/bin/lipc-get-prop com.lab126.wifid enable 2>/dev/null
}

wifi_set_enabled() {
  /usr/bin/lipc-set-prop com.lab126.wifid enable "$1" >/dev/null 2>&1
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
  if [ -x /mnt/us/koreader/luajit ] && [ -f "$SRC_DIR/sntp.lua" ]; then
    time_sync_log "using KOReader LuaSocket SNTP client"
    # Intentional word splitting: the Lua client tries each peer in order.
    # shellcheck disable=SC2086
    (cd /mnt/us/koreader && ./luajit "$SRC_DIR/sntp.lua" $NTP_SERVERS) >> "$LOG_FILE" 2>&1
    return $?
  fi

  time_sync_log "KOReader LuaSocket SNTP client is unavailable"
  return 127
}

time_sync_now() {
  if [ ! -x /mnt/us/koreader/luajit ] || [ ! -f "$SRC_DIR/sntp.lua" ]; then
    time_sync_log "time synchronization skipped: KOReader SNTP is unavailable"
    return 127
  fi

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

  time_sync_log "synchronizing with: $NTP_SERVERS"
  run_koreader_sntp
  TIME_SYNC_STATUS=$?
  if [ "$TIME_SYNC_STATUS" -ne 0 ]; then
    time_sync_log "NTP synchronization failed with status $TIME_SYNC_STATUS"
    wifi_set_enabled 0
    return 1
  fi

  if command -v hwclock >/dev/null 2>&1; then
    hwclock -w >> "$LOG_FILE" 2>&1 || time_sync_log "system time set, but hwclock -w failed"
  else
    time_sync_log "system time set; hwclock is unavailable"
  fi

  wifi_set_enabled 0
  time_sync_log "time synchronization completed"
  return 0
}
