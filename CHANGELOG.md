# Changelog

All notable changes to this project are documented here.

## 2.5.3 - 2026-10-02

### Added

- Closed-loop adaptive crystal drift calibration (`AUTO_DRIFT_CALIBRATION=1`, enabled by default):
  - Automatically measures residual time offset $\Delta t$ and elapsed interval $T_{\text{elapsed}}$ against NTP during hourly syncs (`sntp.lua` exports `/tmp/kfc/last_sntp_sync`)
  - Calculates residual drift error rate: $\Delta \text{PPM} = \frac{-\Delta t}{T_{\text{elapsed}}} \times 10^6$
  - Applies damped integral feedback trim ($\alpha = 0.5$, $\text{step} = \Delta \text{PPM} / 2$, clamped to $\pm 1500$ PPM/hr) to smoothly calibrate individual crystal variations across temperature and hardware aging without hunting or overshoot
  - Dynamically combines feedforward voltage scaling with closed-loop trim: $\text{Effective PPM} = \text{clamp}(\text{Base}(V) + \text{Trim}, 0, 8000)$
  - Restricts calibration to reliable time intervals ($1800\text{s} \le T_{\text{elapsed}} \le 10800\text{s}$, $|\Delta t| \le 60\text{s}$) and bounds total trim to $[-3000, +3000]$ PPM
  - Persists learned trim across suspends via `/tmp/kfc/adaptive_ppm.trim` and automatically preserves the last converged value when offline or when Wi-Fi is unavailable
- Comprehensive unit test coverage in `tests/test_refresh_timing.sh` for adaptive PPM trim, damping calculations, bounds clamping, and schema version 6 migration

### Changed

- Bumped settings schema to version 6 with `AUTO_DRIFT_CALIBRATION=1` in `kfc/settings.conf` and automatic migration for existing configurations

## 2.5.2 - 2026-10-02

### Changed

- Updated default `RTC_DRIFT_COMPENSATION_PPM` from 1414 to 5400 based on 150-hour empirical discharge telemetry, perfectly counteracting ~18.5s/h fast crystal drift at high battery voltage (>=4050mV)
- Implemented `calc_effective_ppm()` continuous piecewise linear scaling for RTC drift compensation:
  - $\ge 4050\text{mV}$: 100% of base PPM (5400 PPM, compensating ~18.3s/h fast drift)
  - $3950\text{mV} \sim 4050\text{mV}$: linear ramp down to 0 PPM across the 100mV transition zone (e.g. 2700 PPM at 4000mV, matching ~8.2s/h drift)
  - $< 3950\text{mV}$: completely suppressed (0 PPM) to avoid compounding crystal lag
- Added low-battery Wi-Fi protection in hourly auto-sync: skips Wi-Fi initiation when battery voltage is below 3550mV (~7%), preventing 200-300mA inrush current spikes from triggering PMIC brownout shutdowns and allowing the device to run on local RTC down to empty

### Added

- Unit test coverage in `tests/test_refresh_timing.sh` for `calc_effective_ppm()` voltage interpolation

## 2.5.1 - 2026-09-25

### Added

- Physical battery voltage sampling (`gasgauge-info -v` and sysfs fallback) with runtime IPC export (`battery.volt`) and millivolt telemetry in runtime logs
- Empirical non-linear voltage-to-percentage piecewise estimation model (`calc_battery_from_voltage()`) calibrated against actual Kindle 4 discharge telemetry (4120mV down to 3420mV)

### Changed

- Battery percentage calculation in `get_battery_level()` now prioritizes physical voltage over the distorted Kindle 4 fuel gauge coulomb counter (`gasgauge-info -c`)
- RTC suspend wall-clock drift compensation dynamically adapts to battery voltage: setback (`PPM`) is automatically suppressed when battery voltage is below 3950mV, preventing reverse clock lag caused by crystal oscillator slowdown under low voltage

### Fixed

- Hourly automatic SNTP time synchronization interval check: added a 300-second (5-minute) tolerance margin to prevent Wi-Fi handshake and NTP network latency (~7-10s) from skipping the next hourly interval check
- Migrated settings version check in `tests/test_refresh_timing.sh` to match schema version 5

## 2.5.0 - 2026-08-27

### Added

- Configurable periodic SNTP synchronization, checked at each hour and scheduled from the last successful synchronization
- Optional passive hourly NTP offset checks for clock-drift diagnostics
- Configurable RTC suspend/resume wall-clock compensation through `RTC_DRIFT_COMPENSATION_PPM`
- Persistent-renderer `ADJUST` requests for applying whole-second clock corrections without starting another LuaJIT process

### Changed

- Wi-Fi shutdown now also applies the Kindle hardware RF-kill property
- Idle suspend now defaults to 15 seconds and hourly battery settling to 25 seconds
- Wi-Fi connection, synchronization, and battery-settle durations now use monotonic `/proc/uptime` measurements, so SNTP wall-clock steps cannot create negative or extended waits
- Runtime logs now allow up to 4 MiB and no longer query or log battery status every second during the hourly settle window
- Settings schema is now version 5

### Fixed

- `--check-only` now observes NTP offset without calling `settimeofday`
- `AUTO_TIME_SYNC_INTERVAL_HOURS` now honors its configured interval instead of synchronizing every hour for every positive value
- Automatic synchronization only re-anchors the virtual clock after a successful result and retries a failure at the next hourly check
- KUAL metadata, packaged documentation, and release version now agree on 2.5.0

## 2.4.5 - 2026-08-21

### Added

- A persistent LuaJIT renderer with a FIFO command protocol and startup `PING/PONG` handshake
- Cached 0–9 digit cards and next-minute preparation of only the changed one- or two-card region
- Direct 8-bit framebuffer writes and Kindle 4 `FBIO_EINK_UPDATE_DISPLAY_AREA` partial refreshes, with an MXCFB compatibility branch
- Centisecond refresh diagnostics from `/proc/uptime`, including start, target-boundary, return time, offsets, and RTC lateness
- Bounded persistent logs, one previous-session log, optional debug logging, and renderer/RTC fallback diagnostics
- Hourly gas-gauge settling and sampling so battery changes do not force ordinary minutes into full redraws

### Changed

- Startup now synchronizes time before the first frame and always turns Wi-Fi off afterward
- The idle interval is 60 seconds and the RTC wake margin is fixed at three seconds
- Ordinary minutes no longer encode PNG files; they publish the prepared changed-digit buffer directly
- Refresh scheduling uses fixed 800 ms partial and 1400 ms full visible-duration estimates; runtime driver timings never modify them
- The persistent renderer retains FreeType faces, digit caches, the framebuffer mapping, and the prepared region between minutes

### Fixed

- FIFO creation now tries `mkfifo`, BusyBox, and `mknod`, and falls back safely if the persistent worker cannot start
- Partial-refresh failures disable the optimization for the current session and fall back to validated full PNG rendering
- Normal logs are limited to approximately one summary record per minute and rotate before unbounded growth

### Known limitations

- Kindle 4 suspend/resume can make the system wall clock run fast; periodic SNTP is still needed for long unattended runs
- The eInkFB ioctl may return before the visible waveform finishes, so recorded return time is not the physical end of screen motion
- A manual SNTP operation that crosses a minute boundary can briefly race with minute publication; the subsequent re-anchor and full refresh recover the display

## 2.2.4 - 2026-08-20

### Fixed

- A virtual minute clock now advances from the startup or SNTP anchor instead of deriving every frame from the post-resume system clock
- RTC alarms now follow an absolute PMIC schedule and compensate the next relative delay after an early or late resume
- Frame metadata binds the sampled battery level to its target minute so stale pre-rendered images are rejected

### Changed

- The startup and post-key awake interval now defaults to three minutes instead of ten
- The packaged defaults now use left landscape orientation, 12-hour time, and the dark theme
- Partial and full E Ink refreshes start before the virtual minute boundary so the visible transition is centered around it
- RTC diagnostics now record planned and actual PMIC epochs, resume lateness, selected relative delay, frame battery samples, and display timing

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
