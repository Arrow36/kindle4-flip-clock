# Changelog

All notable changes to this project are documented here.

## 2.5.8 - 2026-10-16

### Added

- **Duplex Reply Pipe (`RENDER_REPLY_FIFO`) & Zero-Latency IPC**: Added a synchronous completion notification pipe (`render.reply`, `fd 9`) between `render_server.lua` and `start.sh`. Instead of falling back to `sleep 1` (`1000ms`) on Kindle 4's BusyBox 1.7.2 while polling for `$STATUS_PATH`, `wait_renderer_reply()` blocks in the kernel on `read -r _ <&9` and wakes immediately when `render_server.lua` finishes (`0.5ms` for `ADJUST`, `2ms` for `PREPARE`, `20–80ms` for `DISPLAY`, `0%` CPU spin, safe EOF on server exit).
- **LuaJIT FFI Microsecond Timing (`WAIT_UNTIL` & `SLEEP_MS`)**: Integrated C `gettimeofday` and `usleep` in `render_server.lua` to align refresh releases with microsecond wall-clock precision, eliminating both the `date +%s` whole-second truncation jitter (`0~990ms`) and the BusyBox `sleep 1` overshoot (`+420ms`).
- **E Ink Physical Waveform Settle Guard (`DISPLAY_SETTLE_DEADLINE_CS`)**: Because Kindle 4's `FBIO_EINK_UPDATE_DISPLAY_AREA` ioctl returns asynchronously in `20–30ms` while the physical E Ink electrophoretic waveform takes `PARTIAL_REFRESH_DURATION_MS=800` (`1400ms` for full refresh), `display_partial_frame()` and `display_frame()` record `DISPLAY_SETTLE_DEADLINE_CS` (`refresh_start + 1000ms` partial / `1600ms` full, including `200ms` charge-pump discharge margin), and `try_rtc_suspend()` waits via `usleep` (0% CPU) until the physical scan finishes before writing `echo mem > /sys/power/state`, preventing premature suspend scanline artifacts while overlapping next-minute `PREPARE` with the hardware scan.

### Changed

- **Substantial Reduction in Per-Minute Userspace Awake Time**:
  - **Synchronous In-Process Pre-rendering**: When the persistent renderer is active (`RENDER_SERVER_READY=1`), `start_next_frame_render()` executes `PREPARE` (2ms) directly in the main process while the E Ink panel is physically scanning, without forking a background subshell or polling in `wait_for_event_or_minute()`. The Kindle enters `echo mem > /sys/power/state` at `:00.6s` right after the physical waveform finishes (previously delayed until `:03.5s`).
  - **Convergence-Gated Dynamic Auto-Sync Interval (`DRIFT_CONVERGED_STREAK`)**: Instead of jumping directly to a multi-hour sync interval before the crystal drift trim has proven stable, `update_adaptive_drift_trim()` tracks consecutive accurate syncs (`|DRIFT_PPM| <= 300` and `|OFFSET_MS| <= 2000`). While `DRIFT_CONVERGED_STREAK < 2`, auto-sync runs every `1` hour to rapidly lock in the trim; once `DRIFT_CONVERGED_STREAK >= 2` (at least two consecutive accurate syncs), it automatically switches to `AUTO_TIME_SYNC_INTERVAL_HOURS` (default `6` hours), and drops back to `1` hour if a later sync detects a regime shift. Also raised the minimum RTC alarm threshold in `try_rtc_suspend()` from `2s` to `5s` to avoid `mxc_rtc.0` short-alarm stalls.
  - **Zero-Fork Hot Path**: Replaced `$(cat ...)` and `$(printf '%.2s' ...)` in per-minute hot paths (`monotonic_centiseconds`, `monotonic_stamp`, `try_rtc_suspend`, `wait_renderer_reply`) with POSIX shell builtins (`read -r` and parameter expansion), and moved log size checks (`truncate_log_if_oversize`) to run once per hour instead of every minute, eliminating ~55,000 child process forks per day.
- **Actual Sleep Duration Denominator for Adaptive Drift Calibration**: `try_rtc_suspend()` now accumulates actual RTC suspend seconds (`ACCUMULATED_SLEPT_SECONDS`), and `update_adaptive_drift_trim()` computes residual `DRIFT_PPM` against actual sleep time rather than total wall-clock elapsed time, preventing awake intervals or key presses from skewing the learned crystal trim.
- **Hardened `adjust_system_time` Pipe Handling**: Uses the persistent `>&8` descriptor with `kill -0` liveness check and falls back to one-shot `luajit -e` if the persistent server is unavailable.

## 2.5.7 - 2026-10-16

Based on 46-hour empirical runtime telemetry (`kfc.log`, 4,844 lines).

### Fixed

- **606 Rejected Pre-rendered Frames & Epoch Invariant Corruption**: Fixed a critical regression introduced in 2.5.6 where applying `DRIFT_ADJUST_SECONDS` (`+1s` forward compensation) also mutated `NEXT_DISPLAY_CLOCK`, `NEXT_FRAME_EPOCH`, and `CURRENT_FRAME_EPOCH`:
  - Preserved the strict `epoch % 60 == 0` invariant across all virtual clock and frame target epochs, completely eliminating the 606 `next-minute frame rejected` errors and their 7–10s emergency full PNG fallback renders (saving ~1.4 hours of unnecessary CPU awake time per day).
  - Kept `NEXT_DISPLAY_CLOCK` anchored to real `:00` minute boundaries so top-of-the-hour refreshes occur at `:00` instead of walking into `:30s ~ :58s` and colliding with the `:38s` Wi-Fi sync deadline.
  - Restored accurate drift compensation so `adjust_system_time` is no longer canceled out by shifting `NEXT_DISPLAY_CLOCK` in the same direction.
  - Reset `REFRESH_BOUNDARY_UPTIME_CS` and `REFRESH_PLANNED_START_UPTIME_CS` after drift adjustment so uptime boundary diagnostics recalculate cleanly without shifting minute epochs.
- **1000ms Post-Wake Polling Delay on BusyBox 1.7.2**: Moved `pause_briefly` inside the `if [ "$RTC_WOKE_EARLY" = "1" ]; then` branch in `wait_for_event_or_minute()`. On Kindle 4's BusyBox 1.7.2 (which lacks `usleep` and fractional `sleep`), `pause_briefly` falls back to `sleep 1` (1000ms), which previously delayed every scheduled `rtc_late=1` wake past the minute boundary (`start_offset_ms=1420ms`).
- **Mid-Hour Battery Re-Sampling Under Load**: Preserved locked `CURRENT_FRAME_BATTERY` in `render_current_frame()` and `publish_minute_frame()` fallback so mid-hour full redraws (e.g., after SNTP sync or key events) never re-sample transient load-drooped voltage.

## 2.5.6 - 2026-10-14

Based on 52.7-hour empirical runtime telemetry (4,688 lines in `kfc.log`).

### Fixed

- **Top-of-the-Hour Dropped / Skipped Frames**: Fixed `:01` minute dropping and skipping (`18:01` and `21:01` skipped completely in v2.5.5) caused by Wi-Fi synchronization blocking across the minute boundary:
  - Immediately pre-renders the `XX:01` digit frame in background upon completing the `XX:00` full refresh, before Wi-Fi is turned on.
  - Replaced synchronous `wait "$NTP_SYNC_PID"` in the main loop with asynchronous `start_time_sync "auto"`.
  - Added a hard minute deadline in `time_sync.sh` (`current_sec >= 38` during connect, `>= 40` during sync): forces Wi-Fi to shut down and abort auto-sync before the minute boundary is ever reached.
  - Fixed re-anchor jump: when auto-sync finishes within the same minute, aligns `NEXT_DISPLAY_CLOCK` smoothly without flashing the display; if a cross-minute sync occurs under extreme latency, immediately renders and displays the current minute instead of skipping ahead to the next.
- **Battery IR Drop Distortion & Redundant `:01` Full Refresh**: Fixed battery bouncing (e.g. 100% -> 92% -> 100%) caused by sampling during Wi-Fi load drop:
  - Sample quiet open-circuit voltage (OCV) immediately upon waking before the top-of-the-hour refresh, prior to enabling Wi-Fi or refreshing the display.
  - Eliminated the redundant secondary full PNG refresh at `XX:01` (and the resulting 2.7s latency spike at `XX:02`), preserving partial DIGITS refresh for `XX:01`.
  - Added monotonic discharge filter: when not actively charging, battery percentage is clamped to never increase due to temperature fluctuations.
- **420ms / 1420ms Dual-Peak Refresh Latency**: Synchronized `NEXT_DISPLAY_CLOCK`, `NEXT_FRAME_EPOCH`, and `CURRENT_FRAME_EPOCH` with `DRIFT_ADJUST_SECONDS` when applying drift setback after suspend, eliminating the 1000ms schedule misalignment.

### Changed

- **Substantially Extended Battery Life (From ~46h to 100-140+ Hours / 4-6 Days)**:
  - Increased default `AUTO_TIME_SYNC_INTERVAL_HOURS` from `1` to `4` (since learned trim is now permanently persisted and steady-state drift is $< 0.3\,\text{s/hr}$).
  - Reduced `TIME_SYNC_TIMEOUT` from 45s to 20s.
  - Set default `BATTERY_REFRESH_SETTLE_SECONDS` to `0` (eliminating 25s of awake idling every hour).
  - Reduced default `RTC_WAKE_LEAD_SECONDS` from 3s to 2s.
- **Adaptive Calibration Safeguards**:
  - Added low-battery damping: clamps adaptive step to $\pm 500$ PPM when battery voltage $< 3600\text{mV}$ to prevent dying crystal slowdown from corrupting converged trim.
  - Expanded accepted calibration interval `ELAPSED_SEC` up to 28800s (8 hours) to support multi-hour auto-sync intervals.
  - Bumped settings schema to version 7 with automatic migration.

## 2.5.5 - 2026-10-10

Based on the 48.5-hour 2.5.4 empirical test log (39 successful hourly syncs, 794 forward drift adjustments).

### Changed

- **Forced Top-of-the-Hour Auto-Sync**: Startup time synchronization now records its timestamp independently (`LAST_SYNC_EPOCH`) without setting `LAST_AUTO_SYNC_EPOCH`. The first top-of-the-hour (`:00`) after startup and every hourly sync with `AUTO_TIME_SYNC_INTERVAL_HOURS=1` is now guaranteed to trigger whenever 300 seconds have passed since startup or manual sync, eliminating the legacy 93-minute startup gap.
- **Dynamic Damping Factor (Fast Cold-Start Convergence)**: Closed-loop adaptive calibration now adjusts step size based on residual drift rate:
  - Aggressive zone ($|\Delta \text{PPM}| \ge 3000$): 80% step (`DRIFT_PPM * 4 / 5`, capped at 10000 PPM) to lock onto physical crystal drift within 1-2 hours instead of 5-6 hours.
  - Transition zone ($1500 \le |\Delta \text{PPM}| < 3000$): 60% step (`DRIFT_PPM * 3 / 5`).
  - Steady state ($|\Delta \text{PPM}| < 1500$): 50% critical damping (`DRIFT_PPM / 2`) to filter network and measurement noise.
- **Wider Minimum Sample Window**: Minimum elapsed interval for calibration accepted down to 600 seconds (10 minutes, previously 1800s), enabling immediate drift learning on the first top-of-the-hour even when KFC starts 10-30 minutes before the hour.

### Added

- **Persistent Learned Trim**: Converged `ADAPTIVE_PPM_TRIM` is now automatically mirrored to flash (`learned_ppm.trim`) and restored upon KFC startup, allowing subsequent runs or reboot cycles to operate at steady-state precision from minute 1.

## 2.5.4 - 2026-10-08

Based on the complete 137-hour 2.5.3 discharge log (96 successful hourly syncs).

### Changed

- Removed the voltage-scaled PPM curve introduced in 2.5.2. The log showed the suspend/resume drift switching abruptly between regimes (about -13 s/h to +22 s/h before compensation), including fast drift of ~20 s/h at 3700-3567 mV where the curve applied no correction. Regime changes coincided with shifts in the `rtc_late` wake distribution, not with voltage
- Effective PPM is now `RTC_DRIFT_COMPENSATION_PPM + learned trim`, clamped to `[-8000, +12000]`. Negative values move the clock forward after each suspend, so a slow regime can be corrected
- Adaptive calibration keeps the 0.5 damping but allows steps up to ±6000 PPM per sync and limits the trim to the range the effective PPM can actually use (anti-windup). Replaying the 2.5.3 log, this controller gives a mean hourly error of about 5.0 s/h versus 8.5 s/h measured with 2.5.3
- Calibration accepts sync intervals up to 4 hours and offsets up to 120 s, and ignores residuals above 20000 PPM

### Added

- `calc_drift_adjustment()` helper with signed millisecond carry, plus unit tests for forward correction, anti-windup and sample rejection

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
