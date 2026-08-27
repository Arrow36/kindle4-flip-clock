# kfc (Kindle Flip Clock)

[中文说明](README.md) · A full-screen KUAL flip-clock-style display for the Kindle 4 Non-Touch (K4NT).

**Current version: 2.5.0** · [Download the latest release](https://github.com/Arrow36/kindle4-flip-clock/releases/latest) · [Changelog](CHANGELOG.md)

![kfc preview](docs/preview.svg)

The extension shows the time, Gregorian date, weekday, Chinese lunar date, and battery level. Screen orientation, 12/24-hour mode, and light/dark themes are controlled with the Kindle's physical keys while the clock is running.

The current release caches digit cards, prepares only the changed part of the next minute, and publishes that region directly through the framebuffer without an animated transition.

## What changed in 2.5.0

- Added configurable periodic SNTP synchronization, checked hourly and scheduled from the last successful synchronization.
- Added passive NTP offset checks and configurable `RTC_DRIFT_COMPENSATION_PPM` suspend-clock compensation.
- Wi-Fi shutdown now also applies the Kindle hardware RF-kill property.
- Wi-Fi, synchronization, and battery-settle durations use monotonic `/proc/uptime` measurements and are unaffected by SNTP wall-clock steps.
- Idle suspend now starts after 15 seconds; the hourly full refresh waits 25 seconds for one final battery sample without per-second queries or logs.
- Fixed `--check-only` modifying system time and positive synchronization intervals always running every hour.
- Increased the log limit to 4 MiB and upgraded the settings schema to version 5.

See [CHANGELOG.md](CHANGELOG.md) for the complete release notes.

## Features

- Four screen orientations
- 12-hour and 24-hour formats
- Light and dark themes
- Gregorian date, weekday, Chinese lunar date, and battery percentage
- ByteDance Douyin Sans font
- Changed-digit pre-rendering and direct partial framebuffer refreshes
- Clear-then-redraw full refresh at startup, every hour, and after successful synchronization
- Back forces a full refresh; Home safely exits
- Keyboard-key manual synchronization directly through KOReader LuaSocket SNTP
- Configurable periodic synchronization and optional passive hourly offset checks
- Alibaba Cloud NTP defaults: `ntp1.aliyun.com`, `ntp2.aliyun.com`, and `ntp.aliyun.com`
- Persistent settings and physical-key shortcuts
- First-frame validation before the Kindle framework is stopped
- Wi-Fi off while the clock runs, temporarily enabled for synchronization, and restored to its launch-time state on exit
- RTC Suspend-to-RAM after 15 seconds without a physical-key press; the power button wakes the Kindle and restarts the awake interval
- A persistent renderer avoids loading KOReader graphics libraries and rebuilding digit cards every minute
- Runtime frames, PIDs, and events in `/tmp/kfc`; persistent USB-visible logs in `kfc/logs`

## Tested setup

- Kindle 4 Non-Touch
- Firmware 4.1.4
- Jailbreak and [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326)
- [KOReader](https://github.com/koreader/koreader) installed at `/mnt/us/koreader`

Other Kindle models use different resolutions, framebuffer rotations, and key codes and are not currently supported.

## Installation

1. Download and extract the latest ZIP from [Releases](https://github.com/Arrow36/kindle4-flip-clock/releases).
2. Copy the complete `kfc` directory to the Kindle's `extensions` directory.
3. Verify that the final path is `/mnt/us/extensions/kfc`.
4. Safely eject the Kindle.
5. Select `kfc` in KUAL.

Do not rename the `kfc` directory; the current scripts use an absolute path.

### Upgrading from an older release

Version 2.2.3 renamed the extension directory from `kclock` to lowercase `kfc`. Exit the running clock and back up `settings.conf` before upgrading. Version 2.5.0 uses settings schema 5 and adds automatic synchronization, RTC drift compensation, and new power defaults. Remove `/mnt/us/extensions/kclock` only after the new version starts correctly.

## Physical-key shortcuts

| Key | Action | K4NT key code |
|---|---|---:|
| Left previous-page | Previous screen orientation | 193 |
| Left next-page | Next screen orientation | 104 |
| Right previous-page | Toggle light/dark theme | 109 |
| Five-way center | Toggle 12/24-hour format | 194 |
| Keyboard | Synchronize time now | 29 |
| Menu | Show/hide shortcut help | 139 |
| Back | Clear and force a complete redraw | 158 |
| Home | Exit | 102 |

The directional pad and right next-page key are currently unassigned.

## Configuration

`kfc/settings.conf` contains:

```sh
SETTINGS_VERSION=5
ORIENTATION=landscape_left
HOUR_MODE=24
THEME=dark
TIMEZONE=CST-8
TIME_SYNC_TIMEOUT=45
NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com"
AUTO_TIME_SYNC_INTERVAL_HOURS=1
AUTO_TIME_CHECK_HOURLY=0
RTC_DRIFT_COMPENSATION_PPM=1414
IDLE_SUSPEND_SECONDS=15
RTC_WAKE_LEAD_SECONDS=3
PARTIAL_REFRESH_DURATION_MS=800
FULL_REFRESH_DURATION_MS=1400
BATTERY_REFRESH_SETTLE_SECONDS=25
DEBUG_LOG=0
LOG_MAX_BYTES=4194304
```

`TIMEZONE` uses POSIX TZ syntax. Note that the sign is reversed compared with the usual UTC notation; UTC+8 is written as `CST-8`. `TIME_SYNC_TIMEOUT` accepts 10–180 seconds. `AUTO_TIME_SYNC_INTERVAL_HOURS` accepts 0–72 (`0` disables it), `AUTO_TIME_CHECK_HOURLY=1` enables passive checks, and `RTC_DRIFT_COMPENSATION_PPM=0` disables drift compensation. `IDLE_SUSPEND_SECONDS` accepts 5–3600 seconds, `RTC_WAKE_LEAD_SECONDS` accepts 1–10 seconds, both fixed refresh-duration estimates accept 100–5000 milliseconds, and `BATTERY_REFRESH_SETTLE_SECONDS` accepts 0–50 seconds.

## Rendering

The extension uses KOReader's LuaJIT, FreeType, and BlitBuffer. A persistent worker receives `RENDER`, `PREPARE`, `DISPLAY`, and clock-adjustment commands over a FIFO. Full frames are still encoded as 600×800 PNGs for startup, hourly cleanup, setting/help changes, synchronization, and fallbacks. Ordinary minutes compare four digits, assemble only the changed card region, rotate it to physical framebuffer coordinates, copy it into `/dev/fb0`, and submit an eInkFB partial update. The worker keeps its font faces, digit cache, framebuffer mapping, and prepared region alive between minutes. After 15 seconds without a key press, the clock suspends and requests an RTC wake three seconds before the next target. Home restores Wi-Fi, the sleep policy, and the Kindle framework before exit.

Logs:

```text
/mnt/us/extensions/kfc/logs/launcher.log
/mnt/us/extensions/kfc/logs/kfc.log
```

## Font

`kfc/fonts/DouyinSansBold.ttf` is the official Douyin Sans Bold file from [ByteDance Fonts](https://github.com/bytedance/fonts). It is redistributed under the SIL Open Font License 1.1; see `kfc/fonts/OFL.txt`.

## Known limitations

- Designed for the Kindle 4 Non-Touch 600×800 framebuffer and its physical key codes.
- RTC low-power phase scheduling requires `/sys/devices/platform/mxc_rtc.0/wakeup_enable` and the adjacent `rtc_pmic_epoch_time`; when unavailable, the clock remains awake and uses the system clock for scheduling.
- Battery reading depends on the Kindle 4 `gasgauge-info -c` output.
- Lunar dates are supported from 1900 through 2100.
- Seconds and per-second updates are intentionally omitted.
- Minute changes use direct refreshes and do not include a flip animation.
- Kindle 4 suspend/resume can make the system wall clock run fast; long unattended sessions still benefit from periodic SNTP synchronization.
- The eInkFB ioctl may return before the visible waveform finishes, so recorded return time is not the physical end of screen motion.
- Manual SNTP crossing a minute boundary can briefly race with minute publication; the subsequent re-anchor and full redraw recover the display.
- If the Kindle environment does not expose a sub-second `usleep`, the fallback rounds waits to whole seconds and refresh submission can be later than planned; inspect `kfc.log` offsets when tuning.

## Credits and license

Inspired by [LaisRast/kclock](https://github.com/LaisRast/kclock). This public edition removes the original SVG/rsvg/pngcrush pipeline and uses a new Lua/KOReader renderer.

Code is licensed under the [MIT License](LICENSE). The bundled font remains under its separate [SIL Open Font License 1.1](kfc/fonts/OFL.txt). See [NOTICE.md](NOTICE.md).

Use jailbreak software and third-party extensions at your own risk.
