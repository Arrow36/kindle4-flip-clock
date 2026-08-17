#!/bin/sh

BASE_DIR="/mnt/us/extensions/kclock"
SRC_DIR="$BASE_DIR/src"
OUTPUT_DIR="$BASE_DIR/output"
SETTINGS_FILE="$BASE_DIR/settings.conf"
EXIT_FILE="$OUTPUT_DIR/EXIT"
KEY_EVENT_FILE="$OUTPUT_DIR/KEY_EVENT"
ORIENTATION=landscape_right
HOUR_MODE=24
THEME=light
TIMEZONE=CST-8
HELP_VISIBLE=0
KEY_PID=""
CLEANED=0
UI_STOPPED=0
PID_FILE="$OUTPUT_DIR/kclock.pid"

load_settings() {
  ORIENTATION=landscape_right
  HOUR_MODE=24
  THEME=light
  TIMEZONE=CST-8
  [ -f "$SETTINGS_FILE" ] && . "$SETTINGS_FILE"
  case "$ORIENTATION" in portrait|portrait_down|landscape_right|landscape_left) ;; *) ORIENTATION=landscape_right ;; esac
  case "$HOUR_MODE" in 12|24) ;; *) HOUR_MODE=24 ;; esac
  case "$THEME" in light|dark) ;; *) THEME=light ;; esac
  [ -z "$TIMEZONE" ] && TIMEZONE=CST-8
  export TZ="$TIMEZONE"
}

cleanup() {
  [ "$CLEANED" = "1" ] && return
  CLEANED=1
  [ -n "$KEY_PID" ] && kill "$KEY_PID" 2>/dev/null
  if [ "$UI_STOPPED" = "1" ]; then
    /usr/bin/lipc-set-prop -- com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
    /etc/init.d/framework start >/dev/null 2>&1
  fi
  rm -f "$EXIT_FILE" "$KEY_EVENT_FILE" "$KEY_EVENT_FILE.tmp" "$PID_FILE"
}

save_settings() {
  {
    echo "ORIENTATION=$ORIENTATION"
    echo "HOUR_MODE=$HOUR_MODE"
    echo "THEME=$THEME"
    echo "TIMEZONE=$TIMEZONE"
  } > "$SETTINGS_FILE.tmp"
  mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
}

weekday_name() {
  case "$1" in
    0) echo "星期日" ;; 1) echo "星期一" ;; 2) echo "星期二" ;; 3) echo "星期三" ;;
    4) echo "星期四" ;; 5) echo "星期五" ;; *) echo "星期六" ;;
  esac
}

get_battery_level() {
  LEVEL=$(gasgauge-info -c 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
  case "$LEVEL" in ''|*[!0-9]*) LEVEL=0 ;; esac
  [ "$LEVEL" -gt 100 ] && LEVEL=100
  echo "$LEVEL"
}

render_frame() {
  TOP_H1="$1"; TOP_H2="$2"; TOP_M1="$3"; TOP_M2="$4"
  BOTTOM_H1="$5"; BOTTOM_H2="$6"; BOTTOM_M1="$7"; BOTTOM_M2="$8"
  OUTPUT_STEM="$9"

  rm -f "$OUTPUT_DIR/${OUTPUT_STEM}_optimized.png"
  echo "[$(date)] rendering $OUTPUT_STEM" >> "$OUTPUT_DIR/render.log"
  (
    cd /mnt/us/koreader || exit 1
    ./luajit "$SRC_DIR/render.lua" "$OUTPUT_DIR/${OUTPUT_STEM}_optimized.png" \
      "$ORIENTATION" "$THEME" "$INFO_TEXT" "$PERIOD" "$BATTERY_LEVEL" \
      "$TOP_H1" "$TOP_H2" "$TOP_M1" "$TOP_M2" \
      "$BOTTOM_H1" "$BOTTOM_H2" "$BOTTOM_M1" "$BOTTOM_M2" "$HELP_VISIBLE" "$HOUR_MODE"
  ) >> "$OUTPUT_DIR/render.log" 2>&1
  RENDER_STATUS=$?
  if [ "$RENDER_STATUS" -ne 0 ]; then
    echo "KOReader renderer failed with status $RENDER_STATUS" >> "$OUTPUT_DIR/render.log"
    return 1
  fi
  if [ ! -s "$OUTPUT_DIR/${OUTPUT_STEM}_optimized.png" ]; then
    echo "KOReader renderer produced an empty PNG" >> "$OUTPUT_DIR/render.log"
    return 1
  fi
  return 0
}

read_clock_data() {
  YEAR=$(date +%Y)
  MONTH=$(date +%-m)
  DAY=$(date +%-d)
  WEEKDAY=$(weekday_name "$(date +%w)")
  LUNAR=$(/mnt/us/koreader/luajit "$SRC_DIR/lunar.lua" "$YEAR" "$MONTH" "$DAY" 2>/dev/null)
  [ -z "$LUNAR" ] && LUNAR="未知"
  INFO_TEXT="${YEAR}年${MONTH}月${DAY}日  ${WEEKDAY}  农历${LUNAR}"

  HOUR24=$(date +%-H)
  MINUTE=$(date +%-M)
  PERIOD=""
  DISPLAY_HOUR=$HOUR24
  if [ "$HOUR_MODE" = "12" ]; then
    [ "$HOUR24" -lt 12 ] && PERIOD="AM" || PERIOD="PM"
    DISPLAY_HOUR=$((HOUR24 % 12))
    [ "$DISPLAY_HOUR" -eq 0 ] && DISPLAY_HOUR=12
  fi
  HOUR_PADDED=$(printf "%02d" "$DISPLAY_HOUR")
  MINUTE_PADDED=$(printf "%02d" "$MINUTE")
  H1=$(echo "$HOUR_PADDED" | cut -c1); H2=$(echo "$HOUR_PADDED" | cut -c2)
  M1=$(echo "$MINUTE_PADDED" | cut -c1); M2=$(echo "$MINUTE_PADDED" | cut -c2)

  BATTERY_LEVEL=$(get_battery_level)
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
      "139 1") publish_key_event help_toggle ;;
      "158 1"|"102 1") touch "$EXIT_FILE" ;;
    esac
  done
}

wait_for_update() {
  CURRENT_MINUTE="$1"
  WAIT_REASON=""
  KEY_ACTION=""
  while [ ! -f "$EXIT_FILE" ]; do
    sleep 1
    if [ -f "$KEY_EVENT_FILE" ]; then
      KEY_ACTION=$(cat "$KEY_EVENT_FILE" 2>/dev/null)
      rm -f "$KEY_EVENT_FILE"
      WAIT_REASON="key"
      return
    fi
    if [ "$(date +%-M)" != "$CURRENT_MINUTE" ]; then
      WAIT_REASON="minute"
      return
    fi
  done
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
    *) return 1 ;;
  esac
  [ "$SETTINGS_CHANGED" = "1" ] && save_settings
  return 0
}

main() {
  mkdir -p "$OUTPUT_DIR"
  rm -f "$EXIT_FILE" "$KEY_EVENT_FILE" "$KEY_EVENT_FILE.tmp"
  : > "$OUTPUT_DIR/render.log"
  load_settings

  # Render and validate the first frame before hiding the Kindle UI. If the
  # renderer fails, KUAL stays visible instead of leaving a blank screen.
  read_clock_data
  if ! render_frame "$H1" "$H2" "$M1" "$M2" "$H1" "$H2" "$M1" "$M2" current; then
    return 1
  fi

  /etc/init.d/framework stop >/dev/null 2>&1
  UI_STOPPED=1
  /usr/bin/lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1
  watch_keys &
  KEY_PID=$!

  REFRESH_COUNT=1
  eips -c
  eips -g "$OUTPUT_DIR/current_optimized.png"
  wait_for_update "$MINUTE"

  while [ ! -f "$EXIT_FILE" ]; do
    if [ "$WAIT_REASON" = "key" ]; then
      if ! handle_key_action "$KEY_ACTION"; then
        wait_for_update "$MINUTE"
        continue
      fi
    fi

    read_clock_data
    if render_frame "$H1" "$H2" "$M1" "$M2" "$H1" "$H2" "$M1" "$M2" current; then
      REFRESH_COUNT=$((REFRESH_COUNT + 1))
      if [ "$WAIT_REASON" = "key" ] || [ $((REFRESH_COUNT % 10)) -eq 0 ]; then
        eips -c
      fi
      eips -g "$OUTPUT_DIR/current_optimized.png"
    fi

    wait_for_update "$MINUTE"
  done
}

if [ "$1" != "--run" ]; then
  "$0" --run > /tmp/root/kclock.log 2>&1 &
  exit 0
fi

mkdir -p "$OUTPUT_DIR"
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    exit 0
  fi
fi
echo $$ > "$PID_FILE"
trap cleanup 0 1 2 15
main
