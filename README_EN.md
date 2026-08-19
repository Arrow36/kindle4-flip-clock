# kfc (Kindle Flip Clock)

[中文说明](README.md) · A full-screen KUAL flip-clock-style display for the Kindle 4 Non-Touch (K4NT).

**Current version: 2.2.4** · [Download the latest release](https://github.com/Arrow36/kindle4-flip-clock/releases/latest) · [Changelog](CHANGELOG.md)

![kfc preview](docs/preview.svg)

The extension shows the time, Gregorian date, weekday, Chinese lunar date, and battery level. Screen orientation, 12/24-hour mode, and light/dark themes are controlled with the Kindle's physical keys while the clock is running.

The current release pre-renders the next minute in the background and publishes it at the absolute minute boundary, without an animated transition.

## Features

- Four screen orientations
- 12-hour and 24-hour formats
- Light and dark themes
- Gregorian date, weekday, Chinese lunar date, and battery percentage
- ByteDance Douyin Sans font
- Background pre-rendering with the visible E Ink transition centered around each virtual minute boundary
- Clear-then-redraw full refresh at startup, every hour, and after successful synchronization
- Back forces a full refresh; Home safely exits
- Keyboard-key manual synchronization directly through KOReader LuaSocket SNTP
- Alibaba Cloud NTP defaults: `ntp1.aliyun.com`, `ntp2.aliyun.com`, and `ntp.aliyun.com`
- Persistent settings and physical-key shortcuts
- First-frame validation before the Kindle framework is stopped
- Wi-Fi off while the clock runs, temporarily enabled for synchronization, and restored to its launch-time state on exit
- RTC Suspend-to-RAM after three minutes without a physical-key press; the power button wakes the Kindle and restarts the awake interval
- A virtual minute clock controls displayed time while the RTC follows a phase-corrected absolute PMIC schedule; resume never rewrites the system clock
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
ORIENTATION=landscape_left
HOUR_MODE=12
THEME=dark
TIMEZONE=CST-8
TIME_SYNC_TIMEOUT=45
NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com"
IDLE_SUSPEND_SECONDS=180
RTC_WAKE_LEAD_SECONDS=3
PARTIAL_REFRESH_DURATION_MS=800
FULL_REFRESH_DURATION_MS=1400
```

`TIMEZONE` uses POSIX TZ syntax. Note that the sign is reversed compared with the usual UTC notation; UTC+8 is written as `CST-8`. `TIME_SYNC_TIMEOUT` accepts 10–180 seconds. `IDLE_SUSPEND_SECONDS` accepts 60–3600 seconds, `RTC_WAKE_LEAD_SECONDS` accepts 1–10 seconds, and both refresh-duration estimates accept 100–5000 milliseconds.

## Rendering

The extension uses KOReader's LuaJIT, FreeType, and BlitBuffer to produce 600×800 grayscale PNGs in `/tmp/kfc`. After displaying the current frame, it renders the next minute with a battery-and-target metadata record in a cancellable background process; a synchronous render is used only as a fallback. Startup and successful SNTP synchronization anchor a virtual minute clock. RTC alarms then follow an absolute PMIC-second schedule, while each relative delay is recomputed from the current PMIC value so one late resume cannot shift later cycles. Partial and full E Ink updates start half of their configured visible duration before the virtual boundary. After three minutes without a key press, the clock suspends between updates. A resume at least about two seconds earlier than the RTC schedule is treated as a power-button wake and starts a new three-minute awake interval. Normal RTC wakes neither restart the interval nor rewrite the system clock. Home restores Wi-Fi, the sleep policy, and the Kindle framework before exit.

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

## Credits and license

Inspired by [LaisRast/kclock](https://github.com/LaisRast/kclock). This public edition removes the original SVG/rsvg/pngcrush pipeline and uses a new Lua/KOReader renderer.

Code is licensed under the [MIT License](LICENSE). The bundled font remains under its separate [SIL Open Font License 1.1](kfc/fonts/OFL.txt). See [NOTICE.md](NOTICE.md).

Use jailbreak software and third-party extensions at your own risk.
