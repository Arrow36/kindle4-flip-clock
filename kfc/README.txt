kfc (Kindle Flip Clock) 2.4.5

Requirements:
- jailbroken Kindle 4 Non-Touch
- KUAL
- KOReader installed at /mnt/us/koreader

Install this directory at:
  /mnt/us/extensions/kfc

Start by selecting kfc in KUAL.

At startup, kfc enables Wi-Fi, synchronizes the system clock with KOReader
SNTP, and then turns Wi-Fi off before rendering the first clock frame. If the
network is unavailable, startup continues with the existing system time after
the configured synchronization timeout.

Exit with the Home button.
Press Back to clear the screen and force a complete redraw.
Press the Keyboard key to synchronize time immediately with KOReader SNTP.

The next minute's changed digit cards are rendered in advance. A persistent
LuaJIT worker keeps KOReader's native graphics libraries and cached 0-9 digit
cards loaded; at the minute boundary it writes only the changed-card rectangle
to /dev/fb0 and asks the Kindle 4 eInkFB driver to refresh that rectangle. An
MXCFB branch remains available for compatible later devices. Most
minutes update one card; transitions such as 09 to 10 update two cards. No PNG
is encoded for an ordinary minute. If direct framebuffer access or its
partial-refresh ioctl is unavailable, kfc disables this optimization for the
session and falls back to the complete PNG renderer.

The persistent worker creates its request pipe through mkfifo, BusyBox, or
mknod and must complete a PING/PONG startup handshake before it is used.
Handshake status text is normalized to a single Lua return value so protocol
details cannot acquire the extra replacement-count value returned by gsub().

Startup, every hour, successful time synchronization, settings/help changes,
Back, and battery-display changes still use a complete frame. The battery is
sampled after the hourly refresh and retained between samples, so it cannot
force an otherwise time-only update each minute. The scheduler targets a start
before the virtual minute boundary so the visible transition can straddle it.
During the final second, /proc/uptime is used at centisecond precision.
Driver/eips start and return times are logged for one-digit, two-digit, and
complete refreshes. Scheduling uses the fixed PARTIAL_REFRESH_DURATION_MS and
FULL_REFRESH_DURATION_MS settings; asynchronous driver return times are
diagnostics only and never change the selected timing.

Steady-state logging is one summary line per displayed minute. kfc.log is
capped at 512 KiB and the previous launch is retained as kfc.log.1. Set
DEBUG_LOG=1 in settings.conf only while collecting detailed render and RTC
diagnostics.

Wi-Fi stays off while the clock runs and is enabled only for startup or manual
time synchronization. Its original state is restored when the clock exits.

After 60 seconds without a physical-key press, the Kindle uses RTC suspend
between minute updates and wakes three seconds before each minute. The power
button wakes it and starts a new 60-second awake interval; ordinary keys restart
the interval while already awake.

A resume at least about two seconds before the scheduled RTC alarm is treated
as a power-button wake and also starts a new 60-second awake interval. Normal
minute RTC wakes do not restart the interval. Displayed minutes advance from
the current system/SNTP anchor in 60-second steps; the RTC receives a relative
whole-second delay calculated from the next target and current system time.

Runtime frames, PID files, and events are stored in /tmp/kfc. Persistent logs
are stored in /mnt/us/extensions/kfc/logs and are visible over USB.

Project documentation and licenses are in the repository root.
