# kfc (Kindle Flip Clock)

[中文说明](README.md) · A full-screen KUAL flip-clock-style display for the Kindle 4 Non-Touch (K4NT).

**Current version: 2.2.3** · [Download the latest release](https://github.com/Arrow36/kindle4-flip-clock/releases/latest) · [Changelog](CHANGELOG.md)

![kfc preview](docs/preview.svg)

The extension shows the time, Gregorian date, weekday, Chinese lunar date, and battery level. Screen orientation, 12/24-hour mode, and light/dark themes are controlled with the Kindle's physical keys while the clock is running.

The current release pre-renders the next minute in the background and publishes it at the absolute minute boundary, without an animated transition.

## Features

- Four screen orientations
- 12-hour and 24-hour formats
- Light and dark themes
- Gregorian date, weekday, Chinese lunar date, and battery percentage
- ByteDance Douyin Sans font
- Background pre-rendering with direct publication at each absolute minute boundary
- Clear-then-redraw full refresh at startup, every hour, and after successful synchronization
- Back forces a full refresh; Home safely exits
- Keyboard-key manual synchronization directly through KOReader LuaSocket SNTP
- Alibaba Cloud NTP defaults: `ntp1.aliyun.com`, `ntp2.aliyun.com`, and `ntp.aliyun.com`
- Persistent settings and physical-key shortcuts
- First-frame validation before the Kindle framework is stopped
- Wi-Fi off while the clock runs, temporarily enabled for synchronization, and restored to its launch-time state on exit
- RTC Suspend-to-RAM after ten minutes without a physical-key press; the power button wakes the Kindle and restarts the awake interval
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

### Upgrading from 2.1.0

Version 2.2.3 renames the extension directory from `kclock` to lowercase `kfc`. Exit the running clock before upgrading. If you want to preserve orientation, theme, or other preferences, back up `settings.conf` from the old directory and merge the values into the new configuration after installation. Once the new version starts correctly from KUAL, remove `/mnt/us/extensions/kclock` to avoid duplicate menu entries.

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
ORIENTATION=landscape_right
HOUR_MODE=24
THEME=light
TIMEZONE=CST-8
TIME_SYNC_TIMEOUT=45
NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com"
IDLE_SUSPEND_SECONDS=600
RTC_WAKE_LEAD_SECONDS=3
```

`TIMEZONE` uses POSIX TZ syntax. Note that the sign is reversed compared with the usual UTC notation; UTC+8 is written as `CST-8`. `TIME_SYNC_TIMEOUT` accepts 10–180 seconds. `IDLE_SUSPEND_SECONDS` accepts 60–3600 seconds, and `RTC_WAKE_LEAD_SECONDS` accepts 1–10 seconds.

## Rendering

The extension uses KOReader's LuaJIT, FreeType, and BlitBuffer to produce 600×800 grayscale PNGs in `/tmp/kfc`. After displaying the current frame, it renders the next minute in a cancellable background process. At the absolute boundary it displays the prepared image directly; a synchronous render is used only as a fallback. Startup, each hour, successful time synchronization, and Back use the upstream `eips -c` followed by `eips -g` clear-then-redraw sequence. After ten minutes without a key press, the clock suspends between minute updates and schedules RTC wake shortly before the next boundary. A resume at least about two seconds earlier than the RTC schedule is treated as a power-button wake and starts a new ten-minute awake interval. Normal minute RTC wakes do not restart the interval. Home restores Wi-Fi, the sleep policy, and the Kindle framework before exit.

Logs:

```text
/mnt/us/extensions/kfc/logs/launcher.log
/mnt/us/extensions/kfc/logs/kfc.log
```

## Font

`kfc/fonts/DouyinSansBold.ttf` is the official Douyin Sans Bold file from [ByteDance Fonts](https://github.com/bytedance/fonts). It is redistributed under the SIL Open Font License 1.1; see `kfc/fonts/OFL.txt`.

## Known limitations

- Designed for the Kindle 4 Non-Touch 600×800 framebuffer and its physical key codes.
- RTC low-power operation requires `/sys/devices/platform/mxc_rtc.0/wakeup_enable`; when unavailable, the clock remains awake and continues updating.
- Battery reading depends on the Kindle 4 `gasgauge-info -c` output.
- Lunar dates are supported from 1900 through 2100.
- Seconds and per-second updates are intentionally omitted.
- Minute changes use direct refreshes and do not include a flip animation.

## Credits and license

Inspired by [LaisRast/kclock](https://github.com/LaisRast/kclock). This public edition removes the original SVG/rsvg/pngcrush pipeline and uses a new Lua/KOReader renderer.

Code is licensed under the [MIT License](LICENSE). The bundled font remains under its separate [SIL Open Font License 1.1](kfc/fonts/OFL.txt). See [NOTICE.md](NOTICE.md).

Use jailbreak software and third-party extensions at your own risk.
