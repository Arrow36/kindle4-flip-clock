# Changelog

All notable changes to this project are documented here.

## 2.2.3 - 2026-08-18

### Changed

- Renamed the extension from `kclock` to lowercase `kfc`
- The install path is now `/mnt/us/extensions/kfc`, runtime state is in `/tmp/kfc`, and the main log is `kfc/logs/kfc.log`
- Updated the KUAL menu name, extension ID, renderer paths, documentation, and release directory to use `kfc`

## 2.2.2 - 2026-08-18

### Fixed

- Resume time is now compared with the scheduled RTC wake time
- A hardware wake occurring at least about two seconds early is treated as a power-button wake and restarts the ten-minute awake interval
- Normal minute RTC wakes do not restart the awake interval, so the clock returns to suspend after updating and pre-rendering

## 2.2.1 - 2026-08-18

### Changed

- Manual synchronization now uses KOReader LuaSocket SNTP directly instead of probing `ntpdate` and `ntpd`
- After ten minutes without a physical-key press, the clock uses RTC Suspend-to-RAM between minute updates
- The power button can wake the suspended Kindle; ordinary physical keys restart the interval while the clock is already awake
- RTC wake is scheduled shortly before the next absolute minute boundary; unsupported RTC suspend falls back to awake waiting

## 2.2.0 - 2026-08-18

### Added

- Background pre-rendering of the next minute for direct publication at the absolute minute boundary
- Manual synchronization on the Kindle Keyboard key, trying `ntpdate`, `ntpd`, then KOReader LuaSocket SNTP
- Alibaba Cloud NTP defaults: `ntp1.aliyun.com`, `ntp2.aliyun.com`, and `ntp.aliyun.com`
- Back-key forced full refresh using the upstream clear-then-redraw sequence

### Changed

- Wi-Fi remains off while the clock runs, is enabled temporarily for synchronization, and returns to its launch-time state on exit
- Startup, hourly boundaries, and successful synchronization use a full clear and redraw
- Frames, PID files, and key/synchronization events now live in `/tmp/kclock`
- Launcher and runtime logs now persist under `kclock/logs` for USB access

## 2.1.0 - 2026-08-18

Initial public release of the custom Kindle 4 flip clock edition.

### Added

- Flip-clock-style four-digit layout rendered with KOReader's graphics stack
- Portrait and landscape orientations in all four rotations
- Light/dark themes and 12/24-hour formats
- Gregorian date, weekday, Chinese lunar date, AM/PM, and battery display
- Persistent settings controlled by physical keys
- Physical-key shortcuts and an on-screen shortcut page
- Direct minute refresh with periodic full clears
- First-frame validation and guarded cleanup to restore the Kindle framework
- Official Douyin Sans Bold font with its OFL-1.1 license

### Changed from the original concept

- Replaced the SVG, `rsvg-convert`, and `pngcrush` pipeline with LuaJIT, FreeType, and BlitBuffer from KOReader
- Kept Wi-Fi state unchanged
- Removed the simulated transition frame in favor of direct refreshes
